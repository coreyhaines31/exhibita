import AppKit
import ExhibitEditor
import Foundation

/// Issue 109: copy and delete, from the editor or the panel, and the panel's Copy Path.
extension EditorWindows {
    /// Copies `png` and, only if that worked, closes any editor on the capture and deletes it for good. The
    /// editor closes without writing back and without the "until exported" delete; `OpenCaptures.delete` runs
    /// after anything already queued, so nothing recreates the bundle. History reloads either way.
    @discardableResult
    func copyAndDelete(_ id: UUID, png: Data, on screen: NSScreen?) async -> CopyAndDelete.Outcome {
        let outcome = await CopyAndDelete.run(copy: { Self.copyToClipboard(png) }, delete: { [self] in
            takeWindow(id)?.closeDeleted()
            try await captures.delete(id)
        })
        let message = CopyAndDelete.message(for: outcome)
        switch outcome {
        case .copyFailed:
            if let controller = windows[id] { controller.editor.show(message) } else { showNote(message, screen) }
            NSSound.beep()
        case .copiedAndDeleted, .deleteFailed:
            showNote(message, screen)
        }
        await model.reload()
        return outcome
    }

    /// The panel's Copy and Delete: the capture's marked-up image, from its open editor or from disk.
    func copyAndDelete(_ id: UUID) async {
        guard let png = await markedPNG(id) else {
            showNote(CopyAndDelete.message(for: .copyFailed), nil)
            NSSound.beep()
            return
        }
        await copyAndDelete(id, png: png, on: nil)
    }

    /// The panel's Copy Path: the marked-up image written to the exports folder, its path on the clipboard.
    func copyPath(_ id: UUID) async {
        let folder = Self.exportsFolder
        let url: URL?
        if let controller = windows[id], let png = controller.markedPNG() {
            url = try? EditorExport.write(png, named: EditorExport.fileName(for: controller.editor.document),
                                          in: folder)
        } else {
            let store = model.store
            url = try? await captures.writer.perform {
                let loaded = try store.load(id)
                let png = try EditorExport.png(loaded.document, original: loaded.original)
                return try EditorExport.write(png, named: EditorExport.fileName(for: loaded.document), in: folder)
            }
        }
        guard let url else {
            NSSound.beep()
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
        showNote("Path copied", nil)
    }

    /// The marked-up PNG of a capture: the open editor's document if there is one, otherwise the saved one.
    private func markedPNG(_ id: UUID) async -> Data? {
        if let controller = windows[id] { return controller.markedPNG() }
        let store = model.store
        return try? await captures.writer.perform {
            let loaded = try store.load(id)
            return try EditorExport.png(loaded.document, original: loaded.original)
        }
    }

    /// Puts a PNG on the clipboard. True only when the pasteboard took it.
    static func copyToClipboard(_ png: Data) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setData(png, forType: .png)
    }
}
