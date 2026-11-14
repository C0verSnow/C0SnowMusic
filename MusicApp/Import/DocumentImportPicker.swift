import SwiftUI
import UniformTypeIdentifiers

struct DocumentImportPicker: UIViewControllerRepresentable {
    let types: [UTType]
    var multiple = false
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Copy mode hands the app a local file, including when the provider cannot grant in-place access.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = multiple
        picker.delegate = context.coordinator
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--picker-fixture") { picker.directoryURL = .documentsDirectory }
        #endif
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentImportPicker
        init(parent: DocumentImportPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { parent.onPick(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { parent.onCancel() }
    }
}
