@testable import ExhibitCLI
import ExhibitCore
import ExhibitInterpret
import Foundation
import Testing

/// Interpretations must be appliable by the CLI's own `marks.json` reader, so voice and `say` reuse `apply`.
struct InterpretApplyTests {
    @Test func applyEntriesDecodeAsMarksFileSpecs() throws {
        let target = Target(kind: .text, text: "Pricing", rect: PixelRect(x: 10, y: 20, width: 60, height: 14))
        let operations = [
            InterpretedOperation(mark: .blur, picks: [.kind(.email), .kind(.key)]),
            InterpretedOperation(mark: .circle, picks: [.id(target.id)]),
            InterpretedOperation(mark: .arrow, picks: [.text("Sign up")], label: "Start here")
        ]
        let entries = operations.map { $0.applyEntry(in: [target]) }
        let specs = try ApplyFile.specs(from: try JSONEncoder().encode(entries))
        #expect(specs.map(\.kind) == [.blur, .circle, .arrow])
        #expect(specs[0].selectors == [.kind(.email), .kind(.key)])
        #expect(specs[1].selectors == [.rect(target.rect)])
        #expect(specs[2].selectors == [.text("Sign up")])
        #expect(specs[2].label == "Start here")
        #expect(specs.map(\.all) == [true, true, true])
    }
}
