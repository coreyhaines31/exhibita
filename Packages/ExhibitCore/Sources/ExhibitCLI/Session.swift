import CoreGraphics
import ExhibitCore
import ExhibitTargets
import Foundation

/// The input of one command: a plain image file or a `.exhibit` bundle, with its targets.
struct Session {
    let inputURL: URL
    let original: CGImage
    /// Set when the input is a bundle.
    let bundle: CaptureBundle.Loaded?
    private(set) var targets: [Target] = []
    /// True when targets came from the bundle's document instead of a fresh OCR pass.
    private(set) var targetsReused = false
    private var targetsLoaded = false
    /// The capture id, when the input was given as one and the capture is an agent's with blurs: outputs then
    /// name the id, not the bundle, so an agent given a redacted capture is not handed the path to the original.
    private(set) var withheldID: String?

    var imageSize: PixelSize { PixelSize(width: original.width, height: original.height) }
    /// The bundle's scale, or nil for plain files so the renderer infers one from the image size.
    var scale: Double? { bundle?.document.scale }
    var layout: MarkLayout { MarkLayout(scale: scale, imageSize: imageSize) }
    /// The input as outputs name it: the capture id when the bundle path is withheld, else the path.
    var reportedInput: String { withheldID ?? inputURL.path }
    /// The bundle path for outputs, or nil when there is no bundle or its path is withheld.
    var reportedBundle: String? { withheldID == nil ? bundle?.url.path : nil }

    static func open(_ path: String) throws -> Session {
        let url = try CaptureID.resolve(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw CLIError.io("No file at \(url.path).")
        }
        if isDirectory.boolValue {
            let loaded: CaptureBundle.Loaded
            do {
                loaded = try CaptureBundle.load(from: url)
            } catch let error as ExhibitError {
                throw CLIError.io("\(url.path) is not a readable .exhibit bundle: \(error.description)")
            }
            var session = Session(inputURL: url, original: loaded.original, bundle: loaded)
            let givenAsID = url.path != URL(fileURLWithPath: path).standardizedFileURL.path
            if givenAsID, loaded.document.source?.capturedBy == .agent,
               loaded.document.marks.contains(where: { $0.kind == .blur }) {
                session.withheldID = path.trimmingCharacters(in: .whitespaces)
            }
            return session
        }
        guard let data = try? Data(contentsOf: url) else { throw CLIError.io("Could not read \(url.path).") }
        guard let image = try? PNG.decode(data) else {
            throw CLIError.io("\(url.path) is not an image this tool can read. Use a PNG or JPEG.")
        }
        return Session(inputURL: url, original: image, bundle: nil)
    }

    /// Loads targets once: from the bundle's document when it has any, otherwise by reading the image.
    mutating func loadTargets() throws {
        guard !targetsLoaded else { return }
        targetsLoaded = true
        if let document = bundle?.document, !document.targets.isEmpty {
            targets = document.targets
            targetsReused = true
            return
        }
        do {
            targets = try TargetFinder().findTargets(in: original)
        } catch {
            throw CLIError(code: "targets", message: "Finding targets failed: \(error.localizedDescription)",
                           status: .failure)
        }
    }

    // MARK: Output

    /// Where the rendered PNG goes. Never the input, never an existing file, unless `force`.
    func outputURL(requested: String?, force: Bool) throws -> URL {
        guard let requested else { return Self.defaultOutput(for: inputURL) }
        let url = URL(fileURLWithPath: requested).standardizedFileURL
        guard url.pathExtension.lowercased() == "png" else {
            throw CLIError.usage("-o must name a .png file; exports are always PNG.")
        }
        let parent = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: parent.appendingPathComponent(CaptureBundle.documentFileName).path) {
            throw CLIError.usage("-o points inside a capture bundle. Write the export somewhere else.")
        }
        if FileManager.default.fileExists(atPath: url.path), !force {
            let what = url.path == inputURL.path ? "is the input" : "already exists"
            throw CLIError(code: "output_exists", message: "\(url.path) \(what). Pass --force to overwrite it.",
                           status: .failure)
        }
        return url
    }

    /// `name.png` becomes `name-marked.png`, then `name-marked-2.png` and so on, whichever is free first. A name
    /// that already ends in `-marked` or `-marked-<n>` keeps its base, so chained calls count up instead of
    /// growing the name.
    static func defaultOutput(for input: URL) -> URL {
        let directory = input.deletingLastPathComponent()
        var base = input.deletingPathExtension().lastPathComponent
        if let range = base.range(of: #"-marked(-[0-9]+)?$"#, options: .regularExpression) {
            base.removeSubrange(range)
        }
        var counter = 1
        while true {
            let name = counter == 1 ? "\(base)-marked.png" : "\(base)-marked-\(counter).png"
            let candidate = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    /// Renders `newMarks` (after any marks the bundle already has) to `output`. For a bundle, the new marks, and
    /// targets found in this run, are saved to `document.json` too, so they stay editable.
    func write(_ newMarks: [Mark], to output: URL) throws {
        let png: Data
        if let bundle {
            var document = bundle.document
            document.marks += newMarks
            if !targetsReused, targetsLoaded { document.targets = targets }
            png = try PNG.encode(Renderer.render(document, original: original))
            try writeFile(png, to: output)
            do {
                try CaptureBundle.saveDocument(document, to: bundle.url)
            } catch {
                throw CLIError.io("Wrote \(output.path) but could not update \(bundle.url.path): \(error)")
            }
        } else {
            png = try Renderer.renderPNG(original: original, marks: newMarks, scale: nil)
            try writeFile(png, to: output)
        }
    }

    private func writeFile(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw CLIError.io("Could not write \(url.path).")
        }
    }
}
