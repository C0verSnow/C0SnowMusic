import SwiftUI

struct AccountView: View {
    @Environment(YouTubeAccountStore.self) private var account
    @Environment(OnlineMusicStore.self) private var online
    @Environment(\.dismiss) private var dismiss
    @State private var login = false
    @AppStorage("appLanguage") private var language = "system"

    var body: some View {
        @Bindable var account = account
        List {
            Section {
                HStack(spacing: 16) {
                    AccountAvatar().frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.profile?.name ?? (account.isSignedIn ? "YouTube" : AppLanguage.text("未登录", language: language))).font(.title3.bold())
                        Text(AppLanguage.text(account.isSignedIn ? (account.sessionVerified ? "已连接 YouTube Music" : "会话待验证，请刷新账户") : "登录 YouTube 账户", language: language))
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let handle = account.profile?.handle { Text(handle).font(.caption).foregroundStyle(.secondary) }
                    }
                }.padding(.vertical, 12)
                if !account.isSignedIn {
                    Button("YouTube 网页登录", systemImage: "person.badge.key") { login = true }
                        .accessibilityIdentifier("googleSignIn")
                } else {
                    Button("刷新账户", systemImage: "arrow.clockwise") { Task { await account.refreshProfile() } }.disabled(account.checking)
                    Button("重新登录") { login = true }
                    Button("退出登录", role: .destructive) { online.resetSession(); Task { await account.signOut() } }
                }
            }
            Section {
                NavigationLink { SettingsView() } label: { Label("Music Settings", systemImage: "gearshape") }
                    .accessibilityIdentifier("musicSettings")
            }
            Section {
                Text("通过 Google 网页登录 YouTube，搜索和下载会使用该账户。登录状态只保存在此设备。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .localizedNavigationTitle("账户").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .sheet(isPresented: $login) { NavigationStack { YouTubeLoginView() } }
        .alert("登录状态", isPresented: Binding(get: { account.error != nil }, set: { if !$0 { account.error = nil } })) {
            Button("好") { account.error = nil }
        } message: { Text(account.error ?? "") }
    }
}

struct AccountAvatar: View {
    @Environment(YouTubeAccountStore.self) private var account
    var body: some View {
        AsyncImage(url: account.profile?.avatarURL) { image in image.resizable().scaledToFill() } placeholder: {
            Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary)
        }.clipShape(.circle()).accessibilityHidden(true)
    }
}
