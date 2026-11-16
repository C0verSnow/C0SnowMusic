import SwiftUI

struct AccountView: View {
    @Environment(YouTubeAccountStore.self) private var account
    @Environment(OnlineMusicStore.self) private var online
    @Environment(\.dismiss) private var dismiss
    @State private var login = false

    var body: some View {
        @Bindable var account = account
        List {
            Section {
                HStack(spacing: 16) {
                    AccountAvatar().frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.profile?.name ?? (account.isSignedIn ? "YouTube" : AppLanguage.text("Not signed in"))).font(.title3.bold())
                        Text(AppLanguage.text(account.isSignedIn ? (account.sessionVerified ? "Connected to YouTube Music" : "Sign in again to update your music.") : "Sign in to your YouTube account"))
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let handle = account.profile?.handle { Text(handle).font(.caption).foregroundStyle(.secondary) }
                    }
                }.padding(.vertical, 12)
                if !account.isSignedIn {
                    Button("Sign In", systemImage: "person.badge.key") { login = true }
                        .accessibilityIdentifier("googleSignIn")
                } else {
                    Button("Refresh account", systemImage: "arrow.clockwise") { Task { await account.refreshProfile() } }.disabled(account.checking)
                    Button("Sign in again") { login = true }
                    Button("Sign out", role: .destructive) { online.resetSession(); Task { await account.signOut() } }
                }
            }
            Section {
                NavigationLink { SettingsView() } label: { Label("Music Settings", systemImage: "gearshape") }
                    .accessibilityIdentifier("musicSettings")
            }
            Section {
                Text("Connect your YouTube account to bring your playlists, albums, and favorites into c0vermusic. Your sign-in stays on this device.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .localizedNavigationTitle("c0vermusic Account").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { if !account.sessionVerified { await account.refreshProfile() } }
        .sheet(isPresented: $login) { NavigationStack { YouTubeLoginView() } }
        .alert("Sign-in status", isPresented: Binding(get: { account.error != nil }, set: { if !$0 { account.error = nil } })) {
            Button("OK") { account.error = nil }
        } message: { Text("Your account couldn’t be updated. Complete sign-in and try again.") }
    }
}

struct AccountAvatar: View {
    @Environment(YouTubeAccountStore.self) private var account
    var body: some View {
        AsyncImage(url: account.profile?.avatarURL) { image in image.resizable().scaledToFill() } placeholder: {
            Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary)
        }.clipShape(.circle).accessibilityHidden(true)
    }
}
