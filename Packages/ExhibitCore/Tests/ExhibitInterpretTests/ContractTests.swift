import ExhibitCore
@testable import ExhibitInterpret
import Foundation
import Testing

struct ContractTests {
    @Test func listingUsesShortRefsAndHidesSecrets() {
        let listing = TargetListing(InterpretRequest(instruction: "", targets: Screen.targets))
        #expect(listing.entries.first?.ref == "t1")
        #expect(listing.text.contains("t1 \"Pricing\" 20,2\n"))
        #expect(listing.text.contains("email (hidden email address)"))
        #expect(listing.target(ref: "T1")?.id == Screen.pricing.id)
        #expect(listing.target(ref: "t999") == nil)
    }

    @Test func listingDropsAFullyMaskedLineThatDuplicatesItsSecret() {
        let listing = TargetListing(InterpretRequest(instruction: "", targets: Screen.targets))
        let ids = listing.entries.map(\.target.id)
        #expect(!ids.contains(Screen.keyLine.id))
        #expect(ids.contains(Screen.key.id))
        // A partly masked line says something the secret does not, so it stays.
        #expect(ids.contains(Screen.emailLine.id))
    }

    @Test func listingNamesTheTargetUnderThePointer() {
        let request = InterpretRequest(instruction: "", targets: Screen.targets, pointer: PixelPoint(x: 205, y: 25))
        let listing = TargetListing(request)
        #expect(listing.pointerText(request.pointer) == "The pointer is at 21,3, over t1.")
        #expect(listing.pointerText(nil) == nil)
    }

    @Test func picksResolveLikeTheCLISelectors() {
        #expect(TargetPick.text("PRICING").targets(in: Screen.targets).map(\.id) == [Screen.pricing.id, Screen.heading.id])
        #expect(TargetPick.kind(.email).targets(in: Screen.targets).map(\.id) == [Screen.email.id])
        #expect(TargetPick.id(Screen.total.id).targets(in: Screen.targets).map(\.id) == [Screen.total.id])
        // Masked text never matches the secret it hides.
        #expect(TargetPick.text("@example.com").targets(in: Screen.targets).isEmpty)
    }

    @Test func operationBecomesAnApplyEntry() throws {
        let operation = InterpretedOperation(mark: .arrow, picks: [.id(Screen.signUp.id), .kind(.key), .text("Total")],
                                             label: "here")
        let entry = operation.applyEntry(in: Screen.targets)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = try #require(String(bytes: try encoder.encode(entry), encoding: .utf8))
        #expect(json == #"{"all":true,"kind":"arrow","kinds":["key"],"label":"here","#
                + #""rect":[{"height":14,"width":80,"x":1100,"y":20}],"text":["Total"]}"#)
    }
}
