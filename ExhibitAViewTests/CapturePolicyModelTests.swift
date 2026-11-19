import ExhibitShell
import XCTest

/// The model behind Settings' never-capture section, on a policy file in a temporary folder.
@MainActor
final class CapturePolicyModelTests: XCTestCase {
    private var folder: URL?

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ExhibitPolicy-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        if let folder { try? FileManager.default.removeItem(at: folder) }
    }

    private func file() throws -> CapturePolicyFile {
        CapturePolicyFile(supportDirectory: try XCTUnwrap(folder))
    }

    func testStartsWithTheDefaultsAndSavesEveryChange() throws {
        let file = try file()
        let model = CapturePolicyModel(file: file)
        XCTAssertEqual(model.policy, CapturePolicy())
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path), "Nothing is written until a change")

        let vault = NeverCaptureApp(name: "Vault", bundleIdentifier: "com.example.vault")
        model.add(vault)
        model.setAgentAutoBlur(false)
        XCTAssertEqual(file.load().policy, model.policy)
        XCTAssertEqual(model.snapshot.current, model.policy)
        XCTAssertTrue(model.policy.neverCapture.contains(vault))
        XCTAssertFalse(model.snapshot.current.agentAutoBlur)

        let keychain = try XCTUnwrap(model.policy.neverCapture.first { $0.name == "Keychain Access" })
        model.remove(keychain)
        XCTAssertEqual(model.snapshot.current.decision(for: CaptureSubject(appName: "Keychain Access")), .allow)

        model.restoreDefaults()
        XCTAssertEqual(CapturePolicyModel(file: file).policy, CapturePolicy())
    }

    func testDamagedFileShowsAProblemAndUsesTheDefaults() throws {
        let file = try file()
        try FileManager.default.createDirectory(at: try XCTUnwrap(folder), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: file.url)
        let model = CapturePolicyModel(file: file)
        XCTAssertEqual(model.policy, CapturePolicy())
        XCTAssertNotNil(model.problem)
        model.setAgentAutoBlur(false)
        XCTAssertNil(model.problem)
        XCTAssertFalse(file.load().policy.agentAutoBlur)
    }
}
