import Foundation

/// What each model is good at, in a few plain words, for the line under Settings' model picker.
///
/// Only what Exhibit A measured goes in `measured`: the interpreter eval on this repo's instructions, on an M4 Pro
/// with 48 GB (`docs/product/model-latency.md`, Warming up; `docs/product/heldout2-results.md`). Change an entry
/// only together with those docs, and keep `RecommendedModels.ordered` in step. A model not listed is described by
/// what its server reports, and says it was not measured.
public enum ModelGuide {
    public static let measured: [String: String] = [
        "qwen3.8:27b": "Most accurate: 94% of test instructions right. About 2 s per instruction once it has read "
            + "the screen, 5 to 6 s otherwise. Needs about 25 GB of memory.",
        "gemma4:26b-nvfp4": "Fast: about 1 s per instruction. Misses some looser redactions (90% right). Needs "
            + "about 16 to 24 GB of memory.",
        "ornith-1.5:9b": "Fastest small model: about 1 s per instruction. Misses harder requests (84% right). Needs "
            + "about 6 GB of memory."
    ]

    /// The description of a model: what was measured, or else what the server reports about it.
    public static func description(of model: String, installed: InstalledModel?) -> String {
        if let facts = measured[model] { return facts }
        var reported: [String] = []
        if let parameters = installed?.parameterSize { reported.append("\(parameters) parameters") }
        if let bytes = installed?.bytes, bytes > 0 { reported.append("\(size(bytes)) on disk") }
        let notMeasured = "Not measured by Exhibit A."
        return reported.isEmpty ? notMeasured : reported.joined(separator: ", ") + ". " + notMeasured
    }

    /// "18 GB", "6.6 GB", "950 MB", in decimal units as Ollama prints them.
    static func size(_ bytes: Int64) -> String {
        let gigabytes = Double(bytes) / 1e9
        if gigabytes >= 10 { return "\(Int(gigabytes.rounded())) GB" }
        if gigabytes >= 1 { return String(format: "%.1f GB", gigabytes) }
        return "\(Int((Double(bytes) / 1e6).rounded())) MB"
    }
}
