import SwiftUI

struct AccountView: View {
    @Environment(GoogleAccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var account = account
        List {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 48)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.name ?? AppLanguage.text("未登录")).font(.title3.bold())
                        Text(account.email ?? AppLanguage.text("登录 Google 账户")).font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 12)
                if account.email == nil {
                    Button("使用 Google 登录", systemImage: "person.badge.key") { Task { await account.signIn() } }
                        .disabled(account.isSigningIn).accessibilityIdentifier("googleSignIn")
                } else {
                    Button("退出登录", role: .destructive) { account.signOut() }
                }
            }
            Section {
                NavigationLink { SettingsView() } label: { Label("Music Settings", systemImage: "gearshape") }
                    .accessibilityIdentifier("musicSettings")
            }
            Section {
                Text("登录用于识别 Google 账户。本地音乐、公开搜索与下载无需登录。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("账户").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .alert("Google 登录失败", isPresented: Binding(get: { account.error != nil }, set: { if !$0 { account.error = nil } })) {
            Button("好") { account.error = nil }
        } message: { Text(account.error ?? "") }
    }
}
