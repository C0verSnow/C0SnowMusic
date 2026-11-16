import SwiftUI

struct AccountView: View {
    @Environment(YouTubeAccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var login = false

    var body: some View {
        List {
            Section {
                if account.isSignedIn {
                    NavigationLink { AccountConnectionView() } label: { profile }
                } else {
                    Button { login = true } label: { profile }.buttonStyle(.plain)
                        .accessibilityIdentifier("googleSignIn")
                }
            }
            Section {
                NavigationLink { SettingsView() } label: {
                    Label("Music Settings", systemImage: "gearshape").foregroundStyle(.pink)
                }.accessibilityIdentifier("musicSettings")
            } footer: {
                Text("Your music, playlists, and favorites. Free and open source.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 8) {
                    Image(systemName: "music.note.circle.fill").foregroundStyle(.pink).accessibilityHidden(true)
                    Text("c0vermusic Account")
                }.font(.headline).fixedSize()
            }.sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close Account", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                    .accessibilityIdentifier("closeAccount")
            }
        }
        .task { if !account.sessionVerified { await account.refreshProfile() } }
        .sheet(isPresented: $login) { NavigationStack { YouTubeLoginView() } }
    }

    private var profile: some View {
        HStack(spacing: 12) {
            AccountAvatar().frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.profile?.name ?? "Sign In").font(.headline)
                Text(account.isSignedIn ? "Account and connection settings" : "Bring your YouTube music with you")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }
}

private struct AccountConnectionView: View {
    @Environment(YouTubeAccountStore.self) private var account
    @Environment(OnlineMusicStore.self) private var online
    @Environment(CloudMusicStore.self) private var cloud
    @State private var login = false
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AccountAvatar().frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.profile?.name ?? "YouTube").font(.headline)
                        if let handle = account.profile?.handle { Text(handle).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }
            Section {
                Button("Refresh Account") { Task { await account.refreshProfile() } }.disabled(account.checking)
                Button("Refresh Library") { Task { await online.loadLibrary(cookies: account.downloadCookies(), cloud: cloud) } }.disabled(online.loadingLibrary)
                Button("Sign In Again") { login = true }
                Button("Sign Out", role: .destructive) { online.resetSession(); Task { await account.signOut() } }
            } footer: {
                Text("Your YouTube sign-in is stored securely on this iPhone.")
            }
        }
        .navigationTitle("YouTube Account").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $login) { NavigationStack { YouTubeLoginView() } }
        .alert("Couldn't Update Your Account", isPresented: Binding(get: { account.error != nil }, set: { if !$0 { account.error = nil } })) {
            Button("OK") { account.error = nil }
        } message: { Text("Complete sign-in and try again. Your saved music is still available.") }
    }
}

struct AccountAvatar: View {
    @Environment(YouTubeAccountStore.self) private var account
    var body: some View {
        AsyncImage(url: account.profile?.avatarURL) { image in image.resizable().scaledToFill() } placeholder: {
            ZStack {
                Color.secondary.opacity(0.25)
                if let name = account.profile?.name {
                    Text(name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()).font(.headline)
                } else { Image(systemName: "person.fill").foregroundStyle(.secondary) }
            }
        }.clipShape(.circle).accessibilityHidden(true)
    }
}
