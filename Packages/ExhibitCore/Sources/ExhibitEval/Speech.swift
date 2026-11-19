import AVFAudio
import ExhibitInterpret
import Foundation
import Speech

/// The ten instructions spoken for the speech check. Synthetic speech is clean and evenly paced, so these numbers
/// flatter real dictation.
let spokenInstructionIDs = ["billing-01", "billing-04", "inbox-03", "chat-06", "table-04", "editor-02", "pricing-01",
                            "pricing-05", "dashboard-03", "login-02"]

struct SpeechRow: Encodable {
    var id: String
    var said: String
    var heard: String
    var audioSeconds: Double
    var transcribeMilliseconds: Double
    var wordErrors: Int
    var words: Int
    /// Whether the grammar reads the transcript the same way as the typed instruction.
    var sameInterpretation: Bool
}

func runSpeech() async throws {
    let set = try EvalSet.load()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("exhibit-speech-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    log("SFSpeechRecognizer authorization: \(SFSpeechRecognizer.authorizationStatus().rawValue) "
        + "(0 not determined, 1 denied, 2 restricted, 3 authorized). It is not requested: that would prompt.")
    guard #available(macOS 26.0, *) else { throw EvalError("SpeechAnalyzer needs macOS 26; this is \(osVersion())") }
    let locale = Locale(identifier: "en-US")
    let probe = SpeechTranscriber(locale: locale, preset: .transcription)
    log("SpeechTranscriber available: \(SpeechTranscriber.isAvailable); asset status for en-US: "
        + "\(await AssetInventory.status(forModules: [probe])); nothing is downloaded by this tool.")
    var rows: [SpeechRow] = []
    for id in spokenInstructionIDs {
        guard let instruction = set.instructions.first(where: { $0.id == id }) else { continue }
        let url = directory.appendingPathComponent("\(id).aiff")
        try say(instruction.instruction, to: url)
        let transcript = try await transcribe(url, locale: locale)
        let heard = transcript.text, seconds = transcript.audioSeconds, milliseconds = transcript.milliseconds
        let errors = plainWords(instruction.instruction), got = plainWords(heard)
        let request = set.request(for: instruction)
        var spoken = request
        spoken.instruction = heard
        let same = GrammarInterpreter.interpret(request) == GrammarInterpreter.interpret(spoken)
        let row = SpeechRow(id: id, said: instruction.instruction, heard: heard, audioSeconds: seconds,
                            transcribeMilliseconds: milliseconds, wordErrors: wordDistance(errors, got),
                            words: errors.count, sameInterpretation: same)
        log("speech \(id): \(Int(milliseconds)) ms for \(String(format: "%.1f", seconds)) s; heard \"\(heard)\"")
        rows.append(row)
    }
    try? FileManager.default.removeItem(at: directory)
    try writeSpeech(rows)
}

private func say(_ text: String, to url: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    process.arguments = ["-o", url.path, text]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw EvalError("say exited \(process.terminationStatus)") }
}

private struct Transcript {
    var text: String
    var audioSeconds: Double
    var milliseconds: Double
}

@available(macOS 26.0, *)
private func transcribe(_ url: URL, locale: Locale) async throws -> Transcript {
    let file = try AVAudioFile(forReading: url)
    let seconds = Double(file.length) / file.processingFormat.sampleRate
    let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let clock = ContinuousClock()
    let start = clock.now
    let collector = Task {
        var text = ""
        for try await result in transcriber.results { text += String(result.text.characters) }
        return text
    }
    if let last = try await analyzer.analyzeSequence(from: file) {
        try await analyzer.finalizeAndFinish(through: last)
    } else {
        await analyzer.cancelAndFinishNow()
    }
    let text = try await collector.value
    let elapsed = clock.now - start
    let milliseconds = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    return Transcript(text: text.trimmingCharacters(in: .whitespacesAndNewlines), audioSeconds: seconds,
                      milliseconds: milliseconds)
}

/// Lowercase words without punctuation, for word error rate.
func plainWords(_ text: String) -> [String] {
    text.lowercased().components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "$'")).inverted)
        .filter { !$0.isEmpty }
}

/// Word-level edit distance: substitutions, insertions and deletions.
func wordDistance(_ lhs: [String], _ rhs: [String]) -> Int {
    guard !lhs.isEmpty else { return rhs.count }
    var previous = Array(0...rhs.count)
    for (row, left) in lhs.enumerated() {
        var current = [row + 1]
        for (column, right) in rhs.enumerated() {
            current.append(min(previous[column + 1] + 1, current[column] + 1, previous[column] + (left == right ? 0 : 1)))
        }
        previous = current
    }
    return previous[rhs.count]
}

private func writeSpeech(_ rows: [SpeechRow]) throws {
    let directory = EvalSet.root.appendingPathComponent("results")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(rows).write(to: directory.appendingPathComponent("speech.json"))
    var lines = ["| Instruction | Said | Heard | Audio s | Transcribe ms | Word errors | Grammar reads it the same |",
                 "|---|---|---|---|---|---|---|"]
    for row in rows {
        lines.append("| \(row.id) | \(row.said) | \(row.heard) | \(String(format: "%.1f", row.audioSeconds)) | "
            + "\(Int(row.transcribeMilliseconds)) | \(row.wordErrors)/\(row.words) | "
            + "\(row.sameInterpretation ? "yes" : "no") |")
    }
    let errors = rows.map(\.wordErrors).reduce(0, +), words = rows.map(\.words).reduce(0, +)
    let times = rows.dropFirst().map(\.transcribeMilliseconds).sorted()
    lines += ["", "Word error rate \(errors)/\(words). Median transcription after the first: "
        + "\(Int(Report.percentile(times, 0.5))) ms; first (cold): \(Int(rows.first?.transcribeMilliseconds ?? 0)) ms."]
    let text = lines.joined(separator: "\n")
    print(text)
    try Data((text + "\n").utf8).write(to: directory.appendingPathComponent("speech.md"))
}
