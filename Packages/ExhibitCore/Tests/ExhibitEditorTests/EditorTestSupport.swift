import CoreGraphics
import ExhibitCore
@testable import ExhibitEditor
import ExhibitFixtures
import ExhibitShell
import ExhibitStore
import Foundation

/// The sample billing window with the targets the finder would report for it, built from the fixture's own
/// boxes so no OCR runs in these tests.
struct EditorFixture {
    let fixture: Fixture
    let document: CaptureDocument
    let emailID = UUID()
    let keyID = UUID()
    let updateID = UUID()
    let renewsID = UUID()

    init(withTargets: Bool = true) {
        let fixture = sampleFixture()
        self.fixture = fixture
        var document = CaptureDocument(size: PixelSize(width: fixture.image.width, height: fixture.image.height),
                                       scale: fixture.scale, source: CaptureSource(appName: "Safari", capturedBy: .person))
        if withTargets {
            let email = fixture["email"]
            let key = fixture["key"]
            let renews = fixture["renews"]
            let renewsText = "Renews on December 1, 2026"
            let firstWord = PixelRect(x: renews.x, y: renews.y, width: renews.width * 0.25, height: renews.height)
            let rest = PixelRect(x: renews.x + renews.width * 0.3, y: renews.y, width: renews.width * 0.7,
                                 height: renews.height)
            document.targets = [
                Target(id: renewsID, kind: .text, text: renewsText, rect: renews,
                       spans: [TextSpan(start: 0, length: 6, rect: firstWord),
                               TextSpan(start: 7, length: renewsText.utf16.count - 7, rect: rest)]),
                Target(id: updateID, kind: .text, text: "Update plan", rect: fixture["update"]),
                Target(kind: .text, text: String(repeating: "•", count: 22), rect: email),
                Target(id: emailID, kind: .email, rect: email),
                Target(kind: .text, text: String(repeating: "•", count: 30), rect: key),
                Target(id: keyID, kind: .key, rect: key)
            ]
        }
        self.document = document
    }

    func point(in rect: PixelRect) -> PixelPoint {
        PixelPoint(x: rect.midX, y: rect.midY)
    }

    subscript(name: String) -> PixelRect { fixture[name] }
}

/// Records every document written, in order.
final class RecordingSink: DocumentSaving, @unchecked Sendable {
    private let lock = NSLock()
    private var saved: [CaptureDocument] = []

    func save(_ document: CaptureDocument) throws {
        lock.lock()
        saved.append(document)
        lock.unlock()
    }

    var documents: [CaptureDocument] {
        lock.lock()
        defer { lock.unlock() }
        return saved
    }
}

@MainActor
func makeEditor(_ fixture: EditorFixture = EditorFixture(), targetsLoaded: Bool = true,
                sink: RecordingSink = RecordingSink(), delay: TimeInterval = 0.05) -> CaptureEditor {
    let owner = DocumentOwner(document: fixture.document, targetsLoaded: targetsLoaded,
                              writer: DocumentWriter(sink: sink, delay: delay))
    return CaptureEditor(owner: owner)
}

extension CaptureEditor {
    func click(_ point: PixelPoint) {
        pointerDown(at: point)
        pointerUp(at: point)
    }

    func drag(from start: PixelPoint, to end: PixelPoint) {
        pointerDown(at: start)
        pointerDragged(to: PixelPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2))
        pointerDragged(to: end)
        pointerUp(at: end)
    }

    func press(_ letters: String, _ modifiers: KeyModifiers = []) {
        for letter in letters {
            _ = handle(.character(String(letter)), modifiers: modifiers)
        }
    }
}

func temporaryStore() -> CaptureStore {
    CaptureStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("ExhibitEditorTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("Captures", isDirectory: true))
}

func removeStore(_ store: CaptureStore) {
    try? FileManager.default.removeItem(at: store.directory.deletingLastPathComponent())
}
