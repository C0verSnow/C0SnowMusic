import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var excludeBackup = UserDefaults.standard.bool(forKey: "excludeMusicFromBackup")
    @State private var changingBackup = false
    @State private var importing = false
    var body: some View {
        @Bindable var library = library
        Form {
            Section("General") {
                NavigationLink { OnlineCacheView() } label: { Label("Audio cache", systemImage: "externaldrive") }
                NavigationLink { CloudLibrarySettingsView() } label: { Label("Music warehouse", systemImage: "cloud") }
            }
            Section("Import settings") {
                Button("Import from Files", systemImage: "folder") { importing = true }
                    .accessibilityIdentifier("importMusic")
                    .disabled(library.importProgress != nil)
                Picker("Duplicate files", selection: $library.duplicatePolicy) {
                    ForEach(DuplicatePolicy.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                Text("Choose whether to skip identical files or keep another copy.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Last import") {
                Text(library.importStatus.isEmpty ? "No imports yet." : library.importStatus)
                ForEach(Array(library.importFailures.enumerated()), id: \.offset) { _, failure in Text(failure).font(.footnote).foregroundStyle(.red) }
            }
            Section("Local storage") {
                LabeledContent("Songs", value: "\(library.songs.count)")
                LabeledContent("Audio files", value: ByteCountFormatter.string(fromByteCount: library.songs.reduce(0) { $0 + $1.fileSize }, countStyle: .file))
                Toggle("Exclude music files from device backup", isOn: Binding(get: { excludeBackup }, set: { new in
                    changingBackup = true
                    Task {
                        do { try await library.importer.setBackupExcluded(new); excludeBackup = new }
                        catch { library.error = error.localizedDescription }
                        changingBackup = false
                    }
                })).disabled(changingBackup)
                Text("Device backup is enabled by default. If excluded, you must restore your original music after reinstalling or changing devices.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Reimport files whose records were removed") { library.restoreRemovedFiles() }.disabled(library.importProgress != nil)
            }
            Section("Audio formats") {
                Text("Choose MP3, FLAC, M4A, AAC, ALAC, WAV, or AIFF files.")
                Text("Some audio formats may need to be converted before they can play on your device.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("About c0vermusic") {
                Text("Native local music player").font(.headline)
                Text("Local music works offline. Connecting a warehouse saves online downloads to Telegram. Imported local music is not uploaded automatically.")
                Text("Version 1.2.0").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .localizedNavigationTitle("Music Settings").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $importing) {
            DocumentImportPicker(types: AudioImportService.contentTypes, multiple: true) { urls in
                importing = false; library.startImport(urls)
            } onCancel: { importing = false }
        }
    }
}
