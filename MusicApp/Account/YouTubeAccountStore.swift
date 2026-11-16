import Foundation
import Observation
import Security
import WebKit

struct WebCookie: Codable, Sendable, Equatable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let secure: Bool
    let httpOnly: Bool
    let expires: Double?

    init(_ cookie: HTTPCookie) {
        name = cookie.name; value = cookie.value; domain = cookie.domain; path = cookie.path
        secure = cookie.isSecure; httpOnly = cookie.isHTTPOnly; expires = cookie.expiresDate?.timeIntervalSince1970
    }

    var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path, .secure: secure ? "TRUE" : "FALSE"]
        if let expires { properties[.expires] = Date(timeIntervalSince1970: expires) }
        if httpOnly { properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE" }
        return HTTPCookie(properties: properties)
    }
    var isCurrent: Bool { expires.map { $0 > Date.now.timeIntervalSince1970 } ?? true }
    var isYouTube: Bool { domain == "youtube.com" || domain.hasSuffix(".youtube.com") }

    func matches(_ url: URL) -> Bool {
        let host = url.host ?? ""
        let suffix = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        return isCurrent && (host == suffix || (domain.hasPrefix(".") && host.hasSuffix("." + suffix))) && url.path.hasPrefix(path) && (!secure || url.scheme == "https")
    }
}

@MainActor @Observable final class YouTubeAccountStore {
    var isSignedIn = false
    var checking = false
    var profile: YouTubeProfile?
    var sessionVerified = false
    var error: String?
    @ObservationIgnored let websiteData = WKWebsiteDataStore.nonPersistent()
    @ObservationIgnored private var cookies: [WebCookie] = []
    @ObservationIgnored private let storageAccount: String

    init(storageAccount: String = "web-session") { self.storageAccount = storageAccount }

    func restore() async {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { return }
        guard status == errSecSuccess, let data = item as? Data else {
            error = AppLanguage.text("无法读取已保存的 YouTube 登录状态。")
            return
        }
        do {
            if let saved = try? JSONDecoder().decode(SavedWebSession.self, from: data) {
                cookies = saved.cookies.filter(\.isCurrent); profile = saved.profile
            } else { cookies = try JSONDecoder().decode([WebCookie].self, from: data).filter(\.isCurrent) }
            for cookie in cookies.compactMap(\.cookie) { await websiteData.httpCookieStore.setCookie(cookie) }
            isSignedIn = cookies.contains { $0.isYouTube && Self.authCookieNames.contains($0.name) }
        } catch { self.error = error.localizedDescription }
    }

    func capture(from view: WKWebView) async -> Bool {
        guard let host = view.url?.host, host == "youtube.com" || host.hasSuffix(".youtube.com") else {
            error = AppLanguage.text("请先在网页中完成登录，再返回 YouTube。")
            return false
        }
        checking = true
        defer { checking = false }
        do {
            let loggedIn = try await view.evaluateJavaScript("Boolean(window.ytcfg?.get?.('LOGGED_IN') || window.ytcfg?.data_?.LOGGED_IN)") as? Bool ?? false
            let snapshot = await websiteData.httpCookieStore.allCookies()
                .filter { $0.domain == "youtube.com" || $0.domain.hasSuffix(".youtube.com") || $0.domain == "google.com" || $0.domain.hasSuffix(".google.com") }
                .map(WebCookie.init).filter(\.isCurrent)
            guard loggedIn, snapshot.contains(where: { $0.isYouTube && Self.authCookieNames.contains($0.name) }) else {
                error = AppLanguage.text("尚未确认 YouTube 已登录，请完成网页登录后重试。")
                return false
            }
            let data = try JSONEncoder().encode(SavedWebSession(cookies: snapshot, profile: nil))
            let status = SecItemUpdate(keychainQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var entry = keychainQuery
                entry[kSecValueData as String] = data
                entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw SessionStorageError() }
            } else if status != errSecSuccess { throw SessionStorageError() }
            cookies = snapshot; profile = nil; isSignedIn = true; sessionVerified = true; error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func downloadCookies() -> [WebCookie] { cookies.filter { $0.isYouTube && $0.isCurrent } }

    func refreshProfile() async {
        guard isSignedIn, !checking else { return }
        checking = true
        defer { checking = false }
        do {
            let loaded = try await YouTubeMusicClient().profile(cookies: downloadCookies())
            let data = try JSONEncoder().encode(SavedWebSession(cookies: cookies, profile: loaded))
            guard SecItemUpdate(keychainQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess else { throw SessionStorageError() }
            profile = loaded; sessionVerified = true; error = nil
        } catch { sessionVerified = false; self.error = error.localizedDescription }
    }

    func signOut() async {
        let status = SecItemDelete(keychainQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { error = SessionStorageError().localizedDescription; return }
        for cookie in await websiteData.httpCookieStore.allCookies() { await websiteData.httpCookieStore.deleteCookie(cookie) }
        cookies = []; isSignedIn = false; profile = nil; sessionVerified = false; error = nil
    }

    private static let authCookieNames: Set<String> = ["SID", "SAPISID", "__Secure-1PAPISID", "__Secure-3PAPISID", "__Secure-1PSID", "__Secure-3PSID"]
    private var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "org.c0versnow.C0SnowMusic.youtube", kSecAttrAccount as String: storageAccount]
    }
}

private struct SavedWebSession: Codable {
    let cookies: [WebCookie]
    let profile: YouTubeProfile?
}

private struct SessionStorageError: LocalizedError {
    var errorDescription: String? { AppLanguage.text("无法保存或清除 YouTube 登录状态，请重试。") }
}
