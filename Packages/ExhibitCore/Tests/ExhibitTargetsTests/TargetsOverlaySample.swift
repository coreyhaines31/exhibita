import ExhibitCore
import ExhibitFixtures
import ExhibitTargets
import Foundation
import Testing

/// Writes `docs/samples/targets-overlay.png` when run with `EXHIBIT_RECORD_GOLDENS=1`: the sample fixture with
/// every found target boxed (text blue, sensitive red, faces green), so a person can check detection by eye.
@Suite struct TargetsOverlaySample {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    @Test func overlay() throws {
        let fixture = sampleFixture()
        let targets = try TargetFinder().findTargets(in: fixture.image)
        let marks = targets.map { target -> Mark in
            switch target.kind {
            case .text: .box(target.rect, color: .blue, targetID: target.id)
            case .face: .box(target.rect, color: .green, targetID: target.id)
            default: .box(target.rect, color: .red, targetID: target.id)
            }
        }
        let output = try Renderer.render(original: fixture.image, marks: marks, scale: fixture.scale)
        #expect(output.width == fixture.image.width)
        guard ProcessInfo.processInfo.environment["EXHIBIT_RECORD_GOLDENS"] == "1" else { return }
        let samples = Self.repoRoot.appendingPathComponent("docs/samples")
        try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
        try PNG.encode(output).write(to: samples.appendingPathComponent("targets-overlay.png"), options: .atomic)
    }
}
