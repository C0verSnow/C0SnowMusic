import SwiftUI

enum AppLanguage {
    static func text(_ key: String, language selection: String? = nil) -> String {
        Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))?
            .localizedString(forKey: key, value: key, table: nil) ?? key
    }
}

extension View {
    func localizedNavigationTitle(_ key: String) -> some View { navigationTitle(AppLanguage.text(key)) }
}
