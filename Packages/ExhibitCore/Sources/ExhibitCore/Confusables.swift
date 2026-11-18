import Foundation

/// Folds characters OCR returns in place of Latin letters and digits (Cyrillic and Greek look-alikes, `Ø`,
/// fullwidth forms, odd dashes and spaces) to the Latin character a person reads.
///
/// Vision's accurate recognizer sometimes reads Latin text as look-alikes from other scripts, for example "Acme" as
/// Cyrillic "Астe", even with English as the only recognition language. Secret patterns and text selectors work on
/// folded text so a look-alike never hides a secret or breaks a match.
///
/// Every mapping is one UTF-16 code unit to one UTF-16 code unit, so a folded string has the same length and the
/// same offsets as the original: spans, masks and boxes computed on either line up with the other.
public enum Confusables {
    /// `text` with every known look-alike replaced by its Latin character.
    public static func fold(_ text: String) -> String {
        var changed = false
        let units = text.utf16.map { unit -> UInt16 in
            guard let folded = latin(for: unit) else { return unit }
            changed = true
            return folded
        }
        return changed ? String(decoding: units, as: UTF16.self) : text
    }

    /// `text` with look-alikes folded only inside words that also hold an ASCII letter or digit, such as "Астe" or
    /// "АPI_TOKEN". Words written wholly in another script, like Russian or Greek text, are left as they are.
    /// This is the form stored in a target's `text`.
    public static func foldMixedWords(_ text: String) -> String {
        var units = Array(text.utf16)
        var start = 0
        while start < units.count {
            guard !isSpace(units[start]) else {
                start += 1
                continue
            }
            var end = start
            var hasASCII = false
            while end < units.count, !isSpace(units[end]) {
                if isASCIIAlphanumeric(units[end]) { hasASCII = true }
                end += 1
            }
            if hasASCII {
                for index in start..<end { units[index] = latin(for: units[index]) ?? units[index] }
            }
            start = end
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// The Latin stand-in for one UTF-16 code unit, or nil when it is not a known look-alike.
    public static func latin(for unit: UInt16) -> UInt16? {
        // Fullwidth ASCII (U+FF01 to U+FF5E) sits at a fixed offset from ASCII.
        if (0xFF01...0xFF5E).contains(unit) { return unit - 0xFF01 + 0x21 }
        return table[unit]
    }

    private static func isSpace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0xA0 || unit == 0x3000
    }

    private static func isASCIIAlphanumeric(_ unit: UInt16) -> Bool {
        (0x30...0x39).contains(unit) || (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit)
    }

    private static let pairs: [(Character, Character)] = [
        // Cyrillic capitals.
        ("А", "A"), ("В", "B"), ("Е", "E"), ("К", "K"), ("М", "M"), ("Н", "H"), ("О", "O"), ("Р", "P"), ("С", "C"),
        ("Т", "T"), ("Х", "X"), ("У", "Y"), ("Ѕ", "S"), ("І", "I"), ("Ј", "J"), ("Ԛ", "Q"), ("Ԝ", "W"),
        // Cyrillic small letters, including those OCR uses for Latin m, n, k and r.
        ("а", "a"), ("в", "b"), ("е", "e"), ("о", "o"), ("р", "p"), ("с", "c"), ("у", "y"), ("х", "x"), ("і", "i"),
        ("ј", "j"), ("ѕ", "s"), ("һ", "h"), ("ԁ", "d"), ("ԛ", "q"), ("ԝ", "w"), ("ӏ", "l"), ("т", "m"), ("п", "n"),
        ("к", "k"), ("г", "r"), ("ь", "b"),
        // Greek.
        ("Α", "A"), ("Β", "B"), ("Ζ", "Z"), ("Ε", "E"), ("Η", "H"), ("Ι", "I"), ("Κ", "K"), ("Μ", "M"), ("Ν", "N"),
        ("Ο", "O"), ("Ρ", "P"), ("Τ", "T"), ("Υ", "Y"), ("Χ", "X"), ("ο", "o"), ("ν", "v"), ("ρ", "p"), ("ι", "i"),
        ("κ", "k"), ("α", "a"), ("τ", "t"), ("υ", "u"), ("χ", "x"),
        // Slashed and dotless forms.
        ("Ø", "0"), ("ø", "o"), ("ı", "i"), ("ℓ", "l"),
        // Dashes, minus signs and spaces that read as their ASCII forms.
        ("\u{2010}", "-"), ("\u{2011}", "-"), ("\u{2012}", "-"), ("\u{2013}", "-"), ("\u{2212}", "-"),
        ("\u{00A0}", " "), ("\u{2007}", " "), ("\u{202F}", " "), ("\u{3000}", " ")
    ]

    private static let table: [UInt16: UInt16] = {
        var table: [UInt16: UInt16] = [:]
        for (from, to) in pairs {
            let source = Array(String(from).utf16)
            let target = Array(String(to).utf16)
            precondition(source.count == 1 && target.count == 1, "Confusables must map one code unit to one")
            table[source[0]] = target[0]
        }
        return table
    }()
}
