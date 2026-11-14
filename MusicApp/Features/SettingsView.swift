import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var excludeBackup = UserDefaults.standard.bool(forKey: "excludeMusicFromBackup")
    @State private var changingBackup = false
    var body: some View {
        @Bindable var library = library
        Form {
            Section("导入设置") {
                Picker("重复文件", selection: $library.duplicatePolicy) {
                    ForEach(DuplicatePolicy.allCases) { Text($0.rawValue).tag($0) }
                }
                Text("通过文件内容的 SHA-256 检测完全相同的文件。不同编码的同一首歌曲可分别导入。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("上次导入") {
                Text(library.importStatus.isEmpty ? "还没有导入记录。" : library.importStatus)
                ForEach(Array(library.importFailures.enumerated()), id: \.offset) { _, failure in Text(failure).font(.footnote).foregroundStyle(.red) }
            }
            Section("本地存储") {
                LabeledContent("歌曲", value: "\(library.songs.count)")
                LabeledContent("音频文件", value: ByteCountFormatter.string(fromByteCount: library.songs.reduce(0) { $0 + $1.fileSize }, countStyle: .file))
                Toggle("音乐文件不参与设备备份", isOn: $excludeBackup).disabled(changingBackup)
                Text("默认保留设备备份。开启后，重新安装应用或更换设备时需要自行恢复原始音乐文件。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("重新导入仅移除记录的文件") { library.restoreRemovedFiles() }.disabled(library.importProgress != nil)
            }
            Section("音频格式") {
                Text("可选择 MP3、FLAC、M4A、AAC、ALAC、WAV、AIFF 文件。")
                Text("导入会检查文件内容、音轨和首段 PCM 解码。系统无法解码的文件会报错，请转换成 ALAC、M4A 或 WAV。具体编码、位深和采样率的兼容性以设备实际播放为准。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("关于 C0SnowMusic") {
                Text("原生本地音乐播放器").font(.headline)
                Text("无需登录，无在线曲库，不上传音乐。界面使用系统字体、SF Symbols 与原生 Liquid Glass。")
                Text("iOS 26 · SwiftUI · AVFoundation · SwiftData").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .onChange(of: excludeBackup) { old, new in
            changingBackup = true
            Task {
                do { try await library.importer.setBackupExcluded(new) }
                catch { excludeBackup = old; library.error = error.localizedDescription }
                changingBackup = false
            }
        }
    }
}
