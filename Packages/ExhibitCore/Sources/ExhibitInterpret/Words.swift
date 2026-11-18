import ExhibitCore
import Foundation

/// Instructions and screen text as lists of lowercase words, so both sides compare the same way.
enum Words {
    /// Lowercase words with look-alike letters folded, `_` and `-` read as spaces, possessives dropped and
    /// punctuation removed. Characters that carry meaning on screens (`$ % @ # .` inside numbers) stay.
    static func of(_ text: String) -> [String] {
        var cleaned = Confusables.fold(text).lowercased()
        for apostrophe in ["'s ", "\u{2019}s "] { cleaned = cleaned.replacingOccurrences(of: apostrophe, with: " ") }
        if cleaned.hasSuffix("'s") || cleaned.hasSuffix("\u{2019}s") { cleaned.removeLast(2) }
        let kept = cleaned.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || "$%@#./".unicodeScalars.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        let words = String(kept).split(separator: " ").map { word in
            String(word).trimmingCharacters(in: CharacterSet(charactersIn: "./"))
        }.filter { !$0.isEmpty }
        return joinSpelledEmail(words)
    }

    /// Dictation writes "email" as "e mail" or "e-mail".
    private static func joinSpelledEmail(_ words: [String]) -> [String] {
        var joined: [String] = []
        var index = 0
        while index < words.count {
            if words[index] == "e", index + 1 < words.count, words[index + 1].hasPrefix("mail") {
                joined.append("e" + words[index + 1])
                index += 2
            } else {
                joined.append(words[index])
                index += 1
            }
        }
        return joined
    }

    /// Two words are the same when they differ only by a plural ending: "button" and "buttons", "address" and
    /// "addresses".
    static func same(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || lhs + "s" == rhs || lhs == rhs + "s" || lhs + "es" == rhs || lhs == rhs + "es"
    }

    static func equal(_ lhs: [String], _ rhs: [String]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy(same)
    }

    /// Whether `phrase` appears in `line` as whole consecutive words.
    static func contains(_ line: [String], _ phrase: [String]) -> Bool {
        guard !phrase.isEmpty, phrase.count <= line.count else { return false }
        return (0...(line.count - phrase.count)).contains { start in
            zip(line[start..<(start + phrase.count)], phrase).allSatisfy(same)
        }
    }

    /// Levenshtein distance between two short strings.
    static func distance(_ lhs: String, _ rhs: String) -> Int {
        let lhs = Array(lhs), rhs = Array(rhs)
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }
        var previous = Array(0...rhs.count)
        for (row, left) in lhs.enumerated() {
            var current = [row + 1]
            for (column, right) in rhs.enumerated() {
                current.append(min(previous[column + 1] + 1, current[column] + 1,
                                   previous[column] + (left == right ? 0 : 1)))
            }
            previous = current
        }
        return previous[rhs.count]
    }
}
