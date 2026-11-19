@testable import ExhibitCore
import Foundation
import Testing

private func roundTrip<T: Codable>(_ value: T) throws -> T {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(T.self, from: try encoder.encode(value))
}

private func json<T: Encodable>(_ value: T) throws -> String {
    String(bytes: try JSONEncoder().encode(value), encoding: .utf8) ?? ""
}

@Suite struct ModelCodingTests {
    @Test func documentRoundTrips() throws {
        let email = Target(kind: .email, text: "sam@example.com", rect: PixelRect(x: 10, y: 20, width: 120, height: 16),
                           confidence: 0.98)
        let document = CaptureDocument(
            createdAt: Date(timeIntervalSince1970: 1_795_000_000.75),
            size: PixelSize(width: 800, height: 600),
            scale: 2,
            source: CaptureSource(appName: "Safari", windowTitle: "Settings", capturedBy: .agent),
            targets: [email],
            marks: [
                .arrow(from: PixelPoint(x: 1, y: 2), to: PixelPoint(x: 30, y: 40), label: "Here"),
                .circle(PixelRect(x: 5, y: 5, width: 20, height: 10), color: .blue),
                .blur(email.rect, targetID: email.id),
                .highlight(PixelRect(x: 0, y: 0, width: 40, height: 12)),
                .text("Note", at: PixelPoint(x: 100, y: 100), color: .green),
                .box(PixelRect(x: 3, y: 4, width: 50, height: 60)),
                .step(3, at: PixelPoint(x: 70, y: 80))
            ]
        )
        #expect(document.createdAt.timeIntervalSince1970 == 1_795_000_000)
        #expect(try roundTrip(document) == document)
        #expect(document.marks.map(\.kind) == MarkKind.allCases)
    }

    @Test func geometryEncodesFlat() throws {
        let line = try json(MarkGeometry.line(from: PixelPoint(x: 1, y: 2), to: PixelPoint(x: 3, y: 4)))
        #expect(line.contains("\"from\"") && line.contains("\"to\"") && !line.contains("rect"))
        let rect = try json(MarkGeometry.rect(PixelRect(x: 1, y: 2, width: 3, height: 4)))
        #expect(rect.hasPrefix("{\"rect\":"))
    }

    @Test func unknownTargetKindsSurviveARoundTrip() throws {
        let input = Data("""
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"licensePlate","rect":{"x":1,"y":2,"width":3,"height":4}}
        """.utf8)
        let target = try JSONDecoder().decode(Target.self, from: input)
        #expect(target.kind == .unknown("licensePlate"))
        let reencoded = try json(target)
        #expect(reencoded.contains("\"kind\":\"licensePlate\""))
        #expect(TargetKind(rawValue: "email") == .email)
    }

    @Test func unknownMarkKindsFailToDecode() {
        let input = Data("""
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"pixelate",
         "geometry":{"rect":{"x":1,"y":2,"width":3,"height":4}},"style":{"color":"red"}}
        """.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Mark.self, from: input) }
    }

    @Test func arrowBoundsSpanBothEnds() {
        let arrow = Mark.arrow(from: PixelPoint(x: 50, y: 10), to: PixelPoint(x: 20, y: 40))
        #expect(arrow.bounds == PixelRect(x: 20, y: 10, width: 30, height: 30))
    }
}
