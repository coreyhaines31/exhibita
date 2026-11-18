@testable import ExhibitCLI
import ExhibitCore
import ExhibitFixtures
import ExhibitInterpret
import Foundation
import Testing

/// A model endpoint that answers with fixed content, like Ollama's `/api/chat`, and counts calls.
final class CannedModel: ModelTransport, @unchecked Sendable {
    let content: String
    let status: Int
    private let lock = NSLock()
    private var count = 0

    init(_ content: String, status: Int = 200) {
        self.content = content
        self.status = status
    }

    var calls: Int { lock.withLock { count } }

    func post(_ url: URL, body: Data, timeout: TimeInterval) throws -> ModelHTTPResponse {
        lock.withLock { count += 1 }
        let reply = try JSONSerialization.data(withJSONObject: ["message": ["role": "assistant", "content": content]])
        return ModelHTTPResponse(status: status, body: reply)
    }
}

/// `exhibit say` on bundles whose targets are planted in the document, so no OCR runs and the screen is exact.
@Suite(.timeLimit(.minutes(2))) struct SayTests {
    let directory: URL
    static let pricing = Target(kind: .text, text: "Pricing", rect: PixelRect(x: 100, y: 40, width: 80, height: 20))
    static let signUp = Target(kind: .text, text: "Sign up", rect: PixelRect(x: 400, y: 40, width: 80, height: 20))
    static let emailLine = Target(kind: .text, text: "Contact \u{2022}\u{2022}\u{2022}\u{2022}",
                                  rect: PixelRect(x: 100, y: 200, width: 300, height: 20))
    static let email = Target(kind: .email, rect: PixelRect(x: 180, y: 200, width: 220, height: 20))
    static let otherEmail = Target(kind: .email, rect: PixelRect(x: 180, y: 260, width: 220, height: 20))
    static let targets = [pricing, signUp, emailLine, email, otherEmail]
    static let noModel: [String: String] = [:]

    init() throws {
        directory = try temporaryDirectory()
    }

    func makeBundle() throws -> URL {
        let fixture = sampleFixture()
        let document = CaptureDocument(size: PixelSize(width: fixture.image.width, height: fixture.image.height),
                                       scale: 2, targets: Self.targets)
        return try CaptureBundle.save(document, original: fixture.image, in: directory)
    }

    @Test func theGrammarAnswersWithoutAModel() throws {
        let bundle = try makeBundle()
        let model = CannedModel("{}")
        let result = CLI.run(arguments: ["say", bundle.path, "blur the emails and circle pricing"],
                             environment: [ModelOptions.modelVariable: "test-model"], transport: model)
        #expect(result.status == .success, "\(result.stderr)")
        #expect(model.calls == 0)
        let body = try json(result.stdout)
        #expect(body["interpreter"] as? String == "grammar")
        #expect(body["model"] == nil)
        #expect(body["summary"] as? String == "Blurred 2 emails, circled \"Pricing\".")
        #expect(body["notFound"] as? [String] == [])
        #expect(body["complete"] as? Bool == true)
        #expect(try marks(result).map { $0["kind"] as? String } == ["blur", "blur", "circle"])
        let saved = try CaptureBundle.load(from: bundle).document
        #expect(saved.marks.map(\.targetID) == [Self.email.id, Self.otherEmail.id, Self.pricing.id])
    }

    @Test func declinedWithoutAModelNeedsAModelAndChangesNothing() throws {
        let bundle = try makeBundle()
        let result = CLI.run(arguments: ["say", bundle.path, "hide anything that identifies the customer"],
                             environment: Self.noModel)
        #expect(result.status == .needsModel)
        #expect(result.status.rawValue == 5)
        #expect(result.stdout.isEmpty)
        let error = try errorBody(result)
        #expect(error["code"] as? String == "needs_model")
        #expect((error["message"] as? String)?.contains("--model") == true)
        #expect((error["message"] as? String)?.contains("EXHIBIT_MODEL") == true)
        #expect(try CaptureBundle.load(from: bundle).document.marks.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
    }

    @Test func theModelAnswersWhatTheGrammarDeclinesAndUnknownRefsAreDropped() throws {
        let bundle = try makeBundle()
        // The listing is t1 Pricing, t2 Sign up, t3 Contact line, t4 email, t5 email. t9 does not exist.
        let model = CannedModel(#"{"parts":[{"words":"the customer","mark":"blur","targets":["t4","t9"]}]}"#)
        let result = CLI.run(arguments: ["say", bundle.path, "hide anything that identifies the customer"],
                             environment: [ModelOptions.modelVariable: "test-model"], transport: model)
        #expect(result.status == .success, "\(result.stderr)")
        #expect(model.calls == 1)
        let body = try json(result.stdout)
        #expect(body["interpreter"] as? String == "model")
        #expect(body["model"] as? String == "test-model")
        #expect(body["summary"] as? String == "Blurred 1 email.")
        #expect(try CaptureBundle.load(from: bundle).document.marks.map(\.targetID) == [Self.email.id])
    }

    @Test func partialResultsApplyWhatWasFoundAndExitZero() throws {
        let bundle = try makeBundle()
        let result = CLI.run(arguments: ["say", bundle.path, "circle pricing and blur the card numbers"],
                             environment: Self.noModel)
        #expect(result.status == .success, "\(result.stderr)")
        let body = try json(result.stdout)
        #expect(body["notFound"] as? [String] == ["card numbers"])
        #expect(body["complete"] as? Bool == false)
        #expect(body["summary"] as? String == "Circled \"Pricing\". Couldn't find: card numbers.")
        #expect(try marks(result).count == 1)
    }

    @Test func nothingFoundExitsThreeAndWritesNothing() throws {
        let bundle = try makeBundle()
        let result = CLI.run(arguments: ["say", bundle.path, "blur the faces"], environment: Self.noModel)
        #expect(result.status == .noMatch)
        let error = try errorBody(result)
        #expect(error["code"] as? String == "no_match")
        #expect(error["notFound"] as? [String] == ["faces"])
        #expect(try CaptureBundle.load(from: bundle).document.marks.isEmpty)
    }

    @Test func thePointerAnswersThis() throws {
        let bundle = try makeBundle()
        let result = CLI.run(arguments: ["say", bundle.path, "circle this", "--pointer", "420,50"],
                             environment: Self.noModel)
        #expect(result.status == .success, "\(result.stderr)")
        #expect(try json(result.stdout)["summary"] as? String == "Circled \"Sign up\".")
        let bad = CLI.run(arguments: ["say", bundle.path, "circle this", "--pointer", "here"], environment: Self.noModel)
        #expect(bad.status == .usage)
    }

    @Test func aRemoteEndpointIsRefusedBeforeAnythingIsSent() throws {
        let bundle = try makeBundle()
        let model = CannedModel("{}")
        let result = CLI.run(arguments: ["say", bundle.path, "hide anything personal", "--model", "m",
                                         "--model-endpoint", "http://192.168.1.20:11434"],
                             environment: Self.noModel, transport: model)
        #expect(result.status == .usage)
        #expect(try errorBody(result)["code"] as? String == "endpoint_not_loopback")
        #expect(model.calls == 0)
        let fromEnvironment = CLI.run(arguments: ["say", bundle.path, "hide anything personal"],
                                      environment: [ModelOptions.modelVariable: "m",
                                                    ModelOptions.endpointVariable: "https://models.example.com/v1"],
                                      transport: model)
        #expect(try errorBody(fromEnvironment)["code"] as? String == "endpoint_not_loopback")
        #expect(model.calls == 0)
    }

    @Test func aFailingModelExitsSixAndChangesNothing() throws {
        let bundle = try makeBundle()
        let model = CannedModel("not json at all")
        let result = CLI.run(arguments: ["say", bundle.path, "hide anything personal", "--model", "m"],
                             environment: Self.noModel, transport: model)
        #expect(result.status == .modelFailed)
        #expect(try errorBody(result)["code"] as? String == "model_failed")
        #expect(try CaptureBundle.load(from: bundle).document.marks.isEmpty)
    }

    @Test func noModelFlagKeepsToTheGrammar() throws {
        let bundle = try makeBundle()
        let model = CannedModel("{}")
        let result = CLI.run(arguments: ["say", bundle.path, "hide anything personal", "--no-model"],
                             environment: [ModelOptions.modelVariable: "m"], transport: model)
        #expect(result.status == .needsModel)
        #expect(model.calls == 0)
    }

    @Test func anEndpointWithoutAModelNameIsAUsageError() throws {
        let bundle = try makeBundle()
        let result = CLI.run(arguments: ["say", bundle.path, "blur the emails"],
                             environment: [ModelOptions.endpointVariable: "http://127.0.0.1:1234/v1"])
        #expect(result.status == .usage)
    }

    @Test func stepsAreNumberedInTheOrderSaid() throws {
        let bundle = try makeBundle()
        let result = CLI.run(arguments: ["say", bundle.path, "step one sign up step two pricing"],
                             environment: Self.noModel)
        #expect(result.status == .success, "\(result.stderr)")
        let saved = try CaptureBundle.load(from: bundle).document.marks
        #expect(saved.map(\.targetID) == [Self.signUp.id, Self.pricing.id])
        #expect(saved.map(\.style.stepNumber) == [1, 2])
    }

    @Test func neverOverwritesWithoutForce() throws {
        let input = try writePNG(sampleFixture(), named: "shot.png", in: directory)
        let result = CLI.run(arguments: ["say", input, "circle pricing", "-o", input], environment: Self.noModel)
        #expect(result.status == .failure)
        #expect(try errorBody(result)["code"] as? String == "output_exists")
    }
}

/// The real binary, grammar only, on a real image read with OCR.
@Suite(.timeLimit(.minutes(2))) struct SayEndToEndTests {
    @Test func blursTheEmailAndCirclesPricing() throws {
        let directory = try temporaryDirectory()
        let input = try writePNG(targetsFixture(scale: 2), named: "shot.png", in: directory)
        let result = try runBinary(["say", input, "blur the emails and circle pricing", "--no-model"])
        #expect(result.status == .success, "\(result.stderr)")
        let body = try json(result.stdout)
        #expect(body["interpreter"] as? String == "grammar")
        #expect((body["summary"] as? String)?.hasPrefix("Blurred 1 email, circled") == true)
        let output = try #require(body["output"] as? String)
        #expect(output.hasSuffix("/shot-marked.png"))
        #expect(FileManager.default.fileExists(atPath: output))

        let needsModel = try runBinary(["say", input, "hide anything that identifies the customer", "--no-model"])
        #expect(needsModel.status.rawValue == 5)
        #expect(try errorBody(needsModel)["code"] as? String == "needs_model")
    }
}
