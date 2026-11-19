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

        let fresh = FreeFormSettings(settings: ModelSettings(), discoverer: { installed })
        XCTAssertNil(fresh.currentInterpreter(), "nothing known before it looks")
        let found = await fresh.interpreter()
        XCTAssertNotNil(found, "an instruction that needs a model looks for a server first")
        XCTAssertEqual(fresh.discovery, installed)
    }
}
