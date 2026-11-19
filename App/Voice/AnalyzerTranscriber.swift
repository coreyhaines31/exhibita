@preconcurrency import AVFoundation
import ExhibitEditor
import Foundation
@preconcurrency import Speech

/// macOS 26 and later: `SpeechAnalyzer` with `SpeechTranscriber`, on device. The spike measured it at 77 ms per
/// utterance on synthetic speech (`docs/product/spike-interpreter.md`). If the language's model isn't installed,
/// it is downloaded once, with progress, and can be cancelled.
@available(macOS 26.0, *)
@MainActor
final class AnalyzerTranscriber: SpeechTranscribing {
    private let locale: Locale
    private var module: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<String, Never>?
    private var tap: MicrophoneTap?

    init(locale: Locale) {
        self.locale = locale
    }

    func prepare() async -> SpeechReadiness {
        guard Microphone.isConnected else { return .unavailable("No microphone is connected.") }
        guard await Microphone.authorize() else { return .microphoneDenied }
        guard SpeechTranscriber.isAvailable else { return .unavailable("On-device speech isn't available on this Mac.") }
        let name = SpeechTranscription.name(of: locale)
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            return .unavailable("On-device speech doesn't support \(name).")
        }
        let module = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        self.module = module
        // The spike saw "supported" for a locale that was installed and worked, so installed locales count too.
        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier(.bcp47) == supported.identifier(.bcp47) }) { return .ready }
        switch await AssetInventory.status(forModules: [module]) {
        case .installed: return .ready
        case .supported, .downloading: return .needsDownload(bytes: nil)
        case .unsupported: return .unavailable("On-device speech doesn't support \(name).")
        @unknown default: return .needsDownload(bytes: nil)
        }
    }

    func download(progress: @escaping @MainActor (Double) -> Void) async throws {
        guard let module, let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else {
            return
        }
        let box = UncheckedBox(request.progress)
        let poll = Task { @MainActor in
            while !Task.isCancelled {
                progress(box.value.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { poll.cancel() }
        try await withTaskCancellationHandler {
            try await request.downloadAndInstall()
        } onCancel: {
            box.value.cancel()
        }
        progress(1)
    }

    func start(hints: [String], partial: @escaping @MainActor (String) -> Void) async throws {
        guard let module else { throw SpeechError("Speech isn't ready.") }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw SpeechError("No audio format works for on-device speech.")
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        if !hints.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = hints
            try? await analyzer.setContext(context)
        }
        try await analyzer.prepareToAnalyze(in: format)
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        results = Task { @MainActor in
            var final = ""
            do {
                for try await result in module.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        final += text
                        partial(Self.tidy(final))
                    } else {
                        partial(Self.tidy(final + text))
                    }
                }
            } catch {}
            return Self.tidy(final)
        }
        let converter = BufferConverter(to: format)
        let tap = MicrophoneTap()
        try tap.start { buffer in
            if let converted = converter.convert(buffer) { continuation.yield(AnalyzerInput(buffer: converted)) }
        }
        self.tap = tap
        self.analyzer = analyzer
        input = continuation
        try await analyzer.start(inputSequence: stream)
    }

    func finish() async -> String {
        tap?.stop()
        tap = nil
        input?.finish()
        input = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        let text = await results?.value ?? ""
        analyzer = nil
        results = nil
        return text
    }

    func cancel() {
        tap?.stop()
        tap = nil
        input?.finish()
        input = nil
        results?.cancel()
        results = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        analyzer = nil
    }

    private static func tidy(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
