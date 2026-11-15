import GoogleSignIn
import Observation
import UIKit

@MainActor @Observable final class GoogleAccountStore {
    var name: String?
    var email: String?
    var isSigningIn = false
    var error: String?

    func restore() async {
        guard configured else { return }
        do { update(try await GIDSignIn.sharedInstance.restorePreviousSignIn()) }
        catch { update(nil) }
    }

    func signIn() async {
        guard configured else {
            error = AppLanguage.text("此构建尚未配置 Google 登录，请联系应用提供者。")
            return
        }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        while let presented = presenter.presentedViewController { presenter = presented }
        isSigningIn = true
        defer { isSigningIn = false }
        do { update(try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter).user) }
        catch {
            let failure = error as NSError
            // GIDSignIn.h defines cancellation as -5 in this error domain.
            if failure.domain != kGIDSignInErrorDomain || failure.code != -5 { self.error = error.localizedDescription }
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        update(nil)
    }

    private var configured: Bool {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              id.hasSuffix(".apps.googleusercontent.com"), !id.contains("$(") else { return false }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: id)
        return true
    }

    private func update(_ user: GIDGoogleUser?) {
        name = user?.profile?.name
        email = user?.profile?.email
    }
}
