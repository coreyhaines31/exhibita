import CoreGraphics
@testable import ExhibitBridge
import Foundation
import Testing

@Suite struct BridgeProtocolTests {
    @Test func requestsRoundTripAsOneLine() throws {
        let request = BridgeRequest(id: "r1", method: .capture,
                                    capture: CaptureParameters(display: 2, region: BridgeRect(x: 1, y: 2, width: 3,
                                                                                              height: 4)))
        let line = try BridgeJSON.encodeLine(request)
        #expect(line.last == 0x0A)
        #expect(!line.dropLast().contains(0x0A))
        let text = try #require(String(data: line, encoding: .utf8))
        #expect(text == #"{"capture":{"display":2,"region":{"height":4,"width":3,"x":1,"y":2}},"id":"r1","#
                + #""method":"capture","v":1}"# + "\n")
        #expect(try BridgeJSON.decode(BridgeRequest.self, from: line.dropLast()) == request)
    }

    @Test func responsesRoundTrip() throws {
        let id = UUID()
        let result = CaptureResult(id: id, bundle: "/x/\(id).exhibit", image: "/x/\(id).png", width: 10, height: 20,
                                   scale: 2, appName: "Safari", windowTitle: nil,
                                   autoBlur: .init(enabled: true, blurred: 2, kinds: ["email": 2]),
                                   blackedOut: [], targets: 5)
        for response in [BridgeResponse(id: "a", capture: result),
                         BridgeResponse(id: "b", open: OpenResult(id: id, shown: true)),
                         BridgeResponse(id: "c", pong: true),
                         BridgeResponse(id: "d", error: BridgeError(.ambiguousWindow, "Two windows", candidates: [
                            WindowSummary(app: "Safari", title: "One", bundleIdentifier: "com.apple.Safari")
                         ]))] {
            let line = try BridgeJSON.encodeLine(response)
            #expect(try BridgeJSON.decode(BridgeResponse.self, from: line.dropLast()) == response)
        }
    }

    @Test func unknownMethodsAndCodesStillDecode() throws {
        let request = try BridgeJSON.decode(BridgeRequest.self, from: Data(#"{"v":1,"id":"x","method":"zap"}"#.utf8))
        #expect(request.method == "zap")
        let response = try BridgeJSON.decode(BridgeResponse.self, from: Data(
            #"{"v":1,"id":"x","error":{"code":"brand_new","message":"m"}}"#.utf8))
        #expect(response.error?.code == "brand_new")
    }

    @Test func parametersResolveToATarget() throws {
        #expect(try CaptureParameters().target() == .display(1, region: nil))
        #expect(try CaptureParameters(window: "Safari").target() == .window("Safari"))
        #expect(try CaptureParameters(display: 2, region: BridgeRect(x: 0, y: 0, width: 5, height: 6)).target()
                == .display(2, region: CGRect(x: 0, y: 0, width: 5, height: 6)))
        let bad = [CaptureParameters(window: "Safari", display: 1), CaptureParameters(window: " "),
                   CaptureParameters(display: 0),
                   CaptureParameters(region: BridgeRect(x: 0, y: 0, width: 0, height: 6)),
                   CaptureParameters(region: BridgeRect(x: .nan, y: 0, width: 4, height: 6))]
        for parameters in bad {
            #expect(throws: BridgeError.self) { try parameters.target() }
            #expect((try? parameters.target()) == nil)
        }
        do {
            _ = try CaptureParameters(window: "Safari", region: BridgeRect(x: 0, y: 0, width: 1, height: 1)).target()
        } catch let error as BridgeError {
            #expect(error.code == "bad_request")
        }
    }

    @Test func errorCodesAreStable() {
        #expect(BridgeError.Code.allCases.map(\.rawValue) == [
            "permission_not_granted", "window_not_found", "ambiguous_window", "never_capture", "display_not_found",
            "unknown_capture", "capture_failed", "bad_request", "unsupported_version", "unknown_method"
        ])
    }
}
