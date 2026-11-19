import ExhibitInterpret
import XCTest

/// The shared setting's defaulting: never chosen uses the recommended model, a choice is kept, and an instruction
/// that needs a model looks for a server first. Discovery is a fixed answer: no network.
@MainActor
final class FreeFormSettingsTests: XCTestCase {
    private var suiteName = ""

    override func setUp() async throws {
        suiteName = "com.exhibitaformac.tests.\(UUID().uuidString)"
        Preferences.defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        Preferences.defaults.removePersistentDomain(forName: suiteName)
        Preferences.defaults = .standard
    }

    func testNeverChosenUsesTheDefaultAndAChoiceIsKept() async throws {
        let ollama = URL(string: "http://127.0.0.1:11434")!
        let installed = Discovery(probes: [.found(ModelServer(kind: .ollama, url: ollama, models: ["qwen3.8:27b"]))])
        let settings = FreeFormSettings(settings: ModelSettings(), discovery: installed)
        XCTAssertNil(settings.settings.effectiveChoice, "never chosen")
        XCTAssertNotNil(settings.currentInterpreter(), "the recommended model with no click")
        XCTAssertEqual(settings.status.message, "Using qwen3.8:27b from Ollama on this Mac.")
        settings.settings.choice = ModelSettings.Choice.none
        XCTAssertNil(settings.currentInterpreter(), "None is kept with a model installed")
        XCTAssertEqual(FreeFormSettings().settings.choice, ModelSettings.Choice.none, "kept in preferences")

        // A found server that is not this Mac: the model it gives refuses before sending, so nothing goes out.
        let elsewhere = Discovery(probes: [.found(ModelServer(kind: .ollama, url: URL(string: "http://192.0.2.1:11434")!,
                                                              models: ["qwen3.8:27b"]))])
        let lookups = LookupCounter()
        let fresh = FreeFormSettings(settings: ModelSettings(), discoverer: {
            await lookups.increment()
            return elsewhere
        })
        XCTAssertNil(fresh.currentInterpreter(), "nothing known before it looks")
        let lazy = try XCTUnwrap(fresh.interpreter(), "a model step that looks only when used")
        var lookupCount = await lookups.value
        XCTAssertEqual(lookupCount, 0, "asking for the step looks for nothing")
        do {
            _ = try await lazy.interpret(InterpretRequest(instruction: "hide anything personal", targets: []))
            XCTFail("the found model is not on this Mac")
        } catch {
            XCTAssertEqual(error as? ModelError, .notLoopback("192.0.2.1"), "the found model was used, and refused")
        }
        lookupCount = await lookups.value
        XCTAssertEqual(lookupCount, 1, "using it looks once")
        XCTAssertEqual(fresh.discovery, elsewhere)

        let nothing = Discovery(probes: [.notRunning(.ollama, ollama)])
        let empty = FreeFormSettings(settings: ModelSettings(), discoverer: { nothing })
        let unavailable = try XCTUnwrap(empty.interpreter())
        do {
            _ = try await unavailable.interpret(InterpretRequest(instruction: "hide anything personal", targets: []))
            XCTFail("no model was found")
        } catch {
            XCTAssertTrue(error is ModelUnavailable)
        }
        XCTAssertNil(empty.interpreter(), "found nothing just now: needs a model at once, no second look")
    }
}

private actor LookupCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
