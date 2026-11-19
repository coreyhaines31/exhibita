import ExhibitCLI
import ExhibitFixtures
import Foundation
import Testing

/// Writes `docs/samples/cli-demo.png` when run with `EXHIBIT_RECORD_GOLDENS=1`, by running the real binary on
/// the sample screen: blur the email and key, then one batch circling the price and pointing at "Update plan".
@Suite(.timeLimit(.minutes(2))) struct CLIDemoSample {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    @Test func demo() throws {
        guard ProcessInfo.processInfo.environment["EXHIBIT_RECORD_GOLDENS"] == "1" else { return }
        let directory = try temporaryDirectory()
        let input = try writePNG(sampleFixture(), named: "billing.png", in: directory)
        let blurred = try runBinary(["blur", input, "--kind", "email", "--kind", "key"])
        #expect(blurred.status == .success, "\(blurred.stderr)")
        let marks = directory.appendingPathComponent("marks.json")
        try Data("""
            [
              {"kind": "circle", "text": "$49/mo"},
              {"kind": "arrow", "to": "Update plan", "label": "Change your plan here"}
            ]
            """.utf8).write(to: marks)
        let output = Self.repoRoot.appendingPathComponent("docs/samples/cli-demo.png").path
        let result = try runBinary(["apply", directory.appendingPathComponent("billing-marked.png").path, marks.path,
                                    "-o", output, "--force"])
        #expect(result.status == .success, "\(result.stderr)")
    }
}
