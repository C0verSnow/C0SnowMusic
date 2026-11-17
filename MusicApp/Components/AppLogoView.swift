import SwiftUI

struct AppLogoView: View {
    var body: some View {
        Image("AppLogo").renderingMode(.original).resizable().scaledToFit()
            .accessibilityHidden(true)
    }
}

struct MusicUnavailableView: View {
    let title: LocalizedStringKey
    var body: some View {
        ContentUnavailableView {
            Label { Text(title) } icon: {
                AppLogoView().frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 12))
            }
        }
    }
}
