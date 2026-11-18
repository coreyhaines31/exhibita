import ExhibitCore
import Foundation
import Testing

@Suite struct ConfusablesTests {
    @Test func foldingReadsAsLatinAndKeepsOffsets() {
        #expect(Confusables.fold("Астe") == "Acme")
        #expect(Confusables.fold("АPI_TOKEN=tk_LmQØ2vВn") == "API_TOKEN=tk_LmQ02vBn")
        #expect(Confusables.fold("ＡＢＣ１２３") == "ABC123")
        #expect(Confusables.fold("555\u{2212}0132") == "555-0132")
        #expect(Confusables.fold("plain ASCII stays") == "plain ASCII stays")
        // The mask character is never folded.
        #expect(Confusables.fold("\u{2022}\u{2022}") == "\u{2022}\u{2022}")
        for text in ["Астe Dashboard", "ΑΒΓ Привет ＦＵＬＬ", "emoji 🙂 Ø"] {
            #expect(Confusables.fold(text).utf16.count == text.utf16.count)
        }
    }

    @Test func storedTextFoldsOnlyMixedWords() {
        #expect(Confusables.foldMixedWords("Астe Dashboard") == "Acme Dashboard")
        #expect(Confusables.foldMixedWords("Привет, мир") == "Привет, мир")
        #expect(Confusables.foldMixedWords("Цена 49 руб") == "Цена 49 руб")
        #expect(Confusables.foldMixedWords("Καλημέρα ΑPI") == "Καλημέρα API")
    }

    @Test func everyUnitInTheTableMapsToOneUnit() {
        for unit in UInt16(0x80)...UInt16(0xFFFD) {
            guard let folded = Confusables.latin(for: unit) else { continue }
            #expect(folded < 0x80, "U+\(String(unit, radix: 16)) folds outside ASCII")
        }
    }
}
