import SwiftUI
import WebKit

struct YouTubeLoginView: View {
    @Environment(YouTubeAccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var webView: WKWebView?

    var body: some View {
        @Bindable var account = account
        YouTubeLoginBrowser(data: account.websiteData, view: $webView)
            .localizedNavigationTitle("登录 YouTube").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存登录") {
                        guard let webView else { return }
                        Task { if await account.capture(from: webView) { await account.refreshProfile(); dismiss() } }
                    }.disabled(account.checking)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("返回", systemImage: "chevron.left") { webView?.goBack() }
                    Spacer()
                    Button("返回 YouTube") { webView?.load(URLRequest(url: URL(string: "https://m.youtube.com/")!)) }
                    Spacer()
                    Button("刷新", systemImage: "arrow.clockwise") { webView?.reload() }
                }
            }
            .alert("登录状态", isPresented: Binding(get: { account.error != nil }, set: { if !$0 { account.error = nil } })) {
                Button("好") { account.error = nil }
            } message: { Text(account.error ?? "") }
    }
}

private struct YouTubeLoginBrowser: UIViewRepresentable {
    let data: WKWebsiteDataStore
    @Binding var view: WKWebView?

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = data
        let browser = WKWebView(frame: .zero, configuration: configuration)
        browser.navigationDelegate = context.coordinator
        browser.load(URLRequest(url: URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fm.youtube.com%2F")!))
        DispatchQueue.main.async { view = browser }
        return browser
    }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
            let host = url.host ?? ""
            let trusted = host == "google.com" || host.hasSuffix(".google.com") || host == "youtube.com" || host.hasSuffix(".youtube.com")
            decisionHandler(url.scheme == "https" && trusted ? .allow : .cancel)
        }
    }
}
