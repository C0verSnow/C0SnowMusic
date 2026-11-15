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
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 48)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.isSignedIn ? "YouTube" : AppLanguage.text("未登录")).font(.title3.bold())
                        Text(account.isSignedIn ? AppLanguage.text("YouTube 登录状态已保存") : AppLanguage.text("登录 YouTube 账户"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 12)
                if !account.isSignedIn {
                    Button("YouTube 网页登录", systemImage: "person.badge.key") { login = true }
                        .accessibilityIdentifier("googleSignIn")
                } else {
                    Button("退出登录", role: .destructive) { online.resetSession(); Task { await account.signOut() } }
                }
            }
            Section {
                NavigationLink { SettingsView() } label: { Label("Music Settings", systemImage: "gearshape") }
                    .accessibilityIdentifier("musicSettings")
            }
            Section {
                Text("通过 Google 网页登录 YouTube。登录状态只保存在本机，用于 YouTube 搜索与下载；无需 Client ID。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("账户").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .sheet(isPresented: $login) { NavigationStack { YouTubeLoginView() } }
        .alert("登录状态", isPresented: Binding(get: { account.error != nil }, set: { if !$0 { account.error = nil } })) {
            Button("好") { account.error = nil }
        } message: { Text(account.error ?? "") }
    }
}
