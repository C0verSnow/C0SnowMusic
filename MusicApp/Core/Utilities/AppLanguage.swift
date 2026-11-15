import SwiftUI

enum AppLanguage {
    static func text(_ key: String, language selection: String? = nil) -> String {
        let language = selection ?? UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        let bundle = language == "system" ? Bundle.main : Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}

extension View {
    func localizedNavigationTitle(_ key: String) -> some View { modifier(AppNavigationTitle(key: key)) }
}

private struct AppNavigationTitle: ViewModifier {
    let key: String
    @AppStorage("appLanguage") private var language = "system"
    func body(content: Content) -> some View { content.navigationTitle(AppLanguage.text(key, language: language)) }
}
