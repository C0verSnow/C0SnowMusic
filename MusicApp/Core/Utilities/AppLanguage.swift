import Foundation

enum AppLanguage {
    static func text(_ key: String) -> String {
        let language = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        let bundle = language == "system" ? Bundle.main : Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
