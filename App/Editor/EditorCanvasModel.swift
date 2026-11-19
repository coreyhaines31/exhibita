import CoreGraphics
import ExhibitCore
import Observation

/// The committed marks flattened by `Renderer`, exactly as an export would be, so what the canvas shows is what
/// gets copied. Blurs show their real redacted fill. Rendering runs off the main thread, latest change wins.
@MainActor
@Observable
final class EditorCanvasModel {
    let original: CGImage
    let scale: Double
    /// The last render. Never the bare original while a blur exists: the first render happens before the
    /// window shows.
    private(set) var rendered: CGImage?
    private(set) var renderedMarks: [Mark]?
    @ObservationIgnored private var generation = 0
    /// Where the canvas is laid out in its window, top-left origin, in points. Read by the end-to-end tests to aim
    /// their clicks.
    @ObservationIgnored var frameInWindow: CGRect?

    init(original: CGImage, scale: Double) {
        self.original = original
        self.scale = scale
    }

    var pixelSize: CGSize { CGSize(width: original.width, height: original.height) }

    /// Renders on the calling thread. Used once before the window shows, and by offscreen renders.
    func renderNow(_ marks: [Mark]) {
        rendered = try? Renderer.render(original: original, marks: marks, scale: scale)
        renderedMarks = marks
    }

    /// Renders in the background; a result older than the latest request is dropped.
    func refresh(_ marks: [Mark]) async {
        guard marks != renderedMarks else { return }
        generation += 1
        let mine = generation
        let job = RenderJob(original: original, marks: marks, scale: scale)
        let image = await Task.detached(priority: .userInitiated) { job.run() }.value
        guard mine == generation, let image = image.image else { return }
        rendered = image
        renderedMarks = marks
    }
}

/// A render handed to a background task. CGImage is immutable, so sharing it is safe.
private struct RenderJob: @unchecked Sendable {
    let original: CGImage
    let marks: [Mark]
    let scale: Double

    func run() -> RenderedImage {
        RenderedImage(image: try? Renderer.render(original: original, marks: marks, scale: scale))
    }
}

private struct RenderedImage: @unchecked Sendable {
    let image: CGImage?
}
