import ExhibitCore
import Foundation

/// A sensitive item found in a line of text.
public struct SensitiveMatch: Sendable, Equatable {
    /// `.email`, `.key`, `.card` or `.phone`.
    public var kind: TargetKind
    /// What was matched, like "card number" or "GitHub token". Safe to show; never contains the match itself.
    public var name: String
    /// The matched characters, in UTF-16 offsets of the searched text.
    public var range: NSRange

    public init(kind: TargetKind, name: String, range: NSRange) {
        self.kind = kind
        self.name = name
        self.range = range
    }
}

/// Pattern matching for emails, keys, cards and phone numbers in recognized text.
///
/// The key and card patterns come from On Hand's clipboard filter. OCR output inserts spaces and swaps look-alike
/// characters, so card numbers tolerate spaces and letters that read as digits, and a generic rule catches long
/// mixed-case tokens no named pattern knows. When in doubt the patterns over-detect: a blurred word costs less
/// than a leaked secret. Every quantifier is bounded so a long line cannot backtrack for long.
public enum SensitivePatterns {
    /// Every match in `text`, ordered by position. A match inside a larger match of the same kind is dropped,
    /// and an email or phone number that overlaps a card or key is dropped: digit runs read as phone numbers,
    /// and `user:password@host` reads as an email.
    public static func matches(in text: String) -> [SensitiveMatch] {
        let whole = NSRange(text.startIndex..., in: text)
        var found = cards(in: text, range: whole) + socialSecurityNumbers(in: text, range: whole)
        for (name, pattern) in keyPatterns {
            for match in pattern.matches(in: text, range: whole) {
                found.append(SensitiveMatch(kind: .key, name: name, range: secretRange(of: match, in: pattern)))
            }
        }
        let secrets = found
        let insideSecret = { (range: NSRange) in
            secrets.contains { NSIntersectionRange($0.range, range).length > 0 }
        }
        for match in emails.matches(in: text, range: whole) where !insideSecret(match.range) {
            found.append(SensitiveMatch(kind: .email, name: "email address", range: match.range))
        }
        for match in phones?.matches(in: text, range: whole) ?? [] where match.resultType == .phoneNumber {
            let digits = (text as NSString).substring(with: match.range).filter(\.isNumber).count
            guard (7...15).contains(digits), !insideSecret(match.range) else { continue }
            found.append(SensitiveMatch(kind: .phone, name: "phone number", range: match.range))
        }
        return dropNested(found).sorted {
            ($0.range.location, $0.range.length) < ($1.range.location, $1.range.length)
        }
    }

    // MARK: Cards and Social Security numbers (from On Hand)

    /// 13 to 19 digits, optionally grouped by spaces or dashes. O, I, l and | read as digits, as OCR may swap them.
    nonisolated(unsafe) private static let cardCandidates =
        expression(#"(?<![\dOIl|.-])\d(?:[ -]{0,2}[\dOIl|]){12,18}(?![\dOIl|.-])"#)

    /// A candidate can run on into the next number ("4242 4242 4242 4242 12"), so when the whole run fails,
    /// shorter runs ending at a group break are tried, longest first.
    private static func cards(in text: String, range: NSRange) -> [SensitiveMatch] {
        let source = text as NSString
        return cardCandidates.matches(in: text, range: range).compactMap { match in
            let candidate = source.substring(with: match.range)
            var ends = [candidate.utf16.count]
            for (offset, unit) in candidate.utf16.enumerated().reversed() where unit == 0x20 || unit == 0x2D {
                if offset > 0, let last = ends.last, last != offset { ends.append(offset) }
            }
            for end in ends {
                let prefix = (candidate as NSString).substring(to: end)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " -"))
                let digits = String(prefix.compactMap(digitValue))
                if hasCardPrefix(digits), passesLuhn(digits) {
                    let length = prefix.utf16.count
                    return SensitiveMatch(kind: .card, name: "card number",
                                          range: NSRange(location: match.range.location, length: length))
                }
            }
            return nil
        }
    }

    private static func digitValue(_ character: Character) -> Character? {
        switch character {
        case "O": "0"
        case "I", "l", "|": "1"
        default: character.isASCII && character.isNumber ? character : nil
        }
    }

    nonisolated(unsafe) private static let ssnCandidates =
        expression(#"(?<![\d-])(\d{3})([- ])(\d{2})\2(\d{4})(?![\d-])"#)

    /// US Social Security numbers. They are reported as keys: an identifier to hide, not something to dial.
    private static func socialSecurityNumbers(in text: String, range: NSRange) -> [SensitiveMatch] {
        ssnCandidates.matches(in: text, range: range).compactMap { match in
            let part = { Int((text as NSString).substring(with: match.range(at: $0))) ?? 0 }
            let area = part(1)
            guard area != 0, area != 666, area < 900, part(3) != 0, part(4) != 0 else { return nil }
            return SensitiveMatch(kind: .key, name: "Social Security number", range: match.range)
        }
    }

    static func hasCardPrefix(_ digits: String) -> Bool {
        let length = digits.count
        let prefix = { Int(digits.prefix($0)) ?? 0 }
        switch true {
        case digits.hasPrefix("4"): return [13, 16, 19].contains(length)
        case (51...55).contains(prefix(2)), (2221...2720).contains(prefix(4)): return length == 16
        case [34, 37].contains(prefix(2)): return length == 15
        case prefix(4) == 6011, (644...649).contains(prefix(3)), prefix(2) == 65, prefix(2) == 62,
             (3528...3589).contains(prefix(4)):
            return (16...19).contains(length)
        case (300...305).contains(prefix(3)), [36, 38, 39].contains(prefix(2)): return (14...19).contains(length)
        default: return false
        }
    }

    static func passesLuhn(_ digits: String) -> Bool {
        let sum = digits.reversed().compactMap(\.wholeNumberValue).enumerated().reduce(0) { total, item in
            let doubled = item.offset.isMultiple(of: 2) ? item.element : item.element * 2
            return total + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum.isMultiple(of: 10)
    }

    // MARK: Keys and tokens (from On Hand, plus a generic rule)

    /// Checked in order. A pattern with a `secret` group reports only that group, so a database URL marks its
    /// password and an `.env` line marks its value.
    nonisolated(unsafe) private static let keyPatterns: [(name: String, pattern: NSRegularExpression)] = [
        ("private key", #"-----BEGIN (?:[A-Z]{1,20} )?PRIVATE KEY-----"#),
        ("AWS access key", #"\bAKIA[0-9A-Z]{16}\b"#),
        ("Stripe secret key", #"\b[rs]k_live_[0-9A-Za-z]{20,256}"#),
        ("GitHub token", #"\bgh[pousr]_[A-Za-z0-9]{36,256}"#),
        ("GitHub token", #"\bgithub_pat_[A-Za-z0-9_]{40,256}"#),
        ("Slack token", #"\bxox[abprs]-[A-Za-z0-9-]{10,256}"#),
        ("Anthropic API key", #"\bsk-ant-[A-Za-z0-9_-]{20,256}"#),
        ("OpenAI API key", #"\bsk-(?:proj-)?[A-Za-z0-9_-]{32,256}"#),
        ("Google API key", #"\bAIza[0-9A-Za-z_-]{35}\b"#),
        ("Google OAuth client secret", #"\bGOCSPX-[A-Za-z0-9_-]{28}\b"#),
        ("Stripe webhook secret", #"\bwhsec_[A-Za-z0-9]{32,256}"#),
        ("GitLab token", #"\bglpat-[A-Za-z0-9_-]{20,256}"#),
        ("npm token", #"\bnpm_[A-Za-z0-9]{36}\b"#),
        ("PyPI token", #"\bpypi-AgEIcHlwaS5vcmc[A-Za-z0-9_-]{50,256}"#),
        ("Hugging Face token", #"\bhf_[A-Za-z0-9]{34,256}"#),
        ("SendGrid API key", #"\bSG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}"#),
        ("Shopify token", #"\bshp(?:at|ca|pa|ss)_[a-fA-F0-9]{32}\b"#),
        ("DigitalOcean token", #"\bdo[por]_v1_[a-f0-9]{64}\b"#),
        ("Linear API key", #"\blin_api_[A-Za-z0-9]{40}\b"#),
        ("Notion token", #"\b(?:secret_[A-Za-z0-9]{43}|ntn_[0-9]{11}[A-Za-z0-9]{35})\b"#),
        ("Postman API key", #"\bPMAK-[a-f0-9]{24}-[a-f0-9]{34}\b"#),
        ("Supabase token", #"\bsbp_[a-f0-9]{40}\b"#),
        ("Mailgun API key", #"\bkey-[0-9a-f]{32}\b"#),
        ("Doppler token", #"\bdp\.(?:pt|st|sa|ct|scim|audit)\.[A-Za-z0-9]{40,256}"#),
        ("database password", #"\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|rediss?|amqps?)://"#
            + #"[^:@\s/]{0,256}:(?<secret>[^@\s/]{1,256})@"#),
        // An .env or config line like API_KEY=value or password: value, in any case. Values that start with $
        // refer to another variable. OCR lines rarely begin at the setting, so this anchors on a word boundary.
        ("secret", #"\b(?:export[ \t]{1,8})?(?i:[A-Z0-9_]{0,64}"#
            + #"(?:SECRET|TOKEN|API_KEY|APIKEY|PASSWORD|PASSWD|PRIVATE_KEY)[A-Z0-9_]{0,64})"#
            + #"[ \t]{0,8}[=:][ \t]{0,8}['"]?(?<secret>[^\s'"$]{8,512})"#),
        // Anything else that looks generated: 20 or more letters, digits, - or _, with upper case, lower case
        // and at least two digits. Ordinary words and identifiers rarely have all three.
        ("token", #"(?<![A-Za-z0-9_-])(?=(?:[A-Za-z_-]{0,511}[0-9]){2})"#
            + #"(?=[A-Za-z0-9_-]{0,511}[a-z])(?=[A-Za-z0-9_-]{0,511}[A-Z])[A-Za-z0-9_-]{20,512}(?![A-Za-z0-9_-])"#),
        // Long hex strings: hashes, signing secrets, session ids.
        ("token", #"(?<![A-Za-z0-9_-])(?=[a-fA-F0-9]{0,511}[a-fA-F])(?=[a-fA-F0-9]{0,511}[0-9])"#
            + #"[a-fA-F0-9]{32,512}(?![A-Za-z0-9_-])"#)
    ].map { ($0.0, expression($0.1)) }

    private static func secretRange(of match: NSTextCheckingResult, in pattern: NSRegularExpression) -> NSRange {
        guard pattern.pattern.contains("(?<secret>") else { return match.range }
        let group = match.range(withName: "secret")
        return group.location == NSNotFound ? match.range : group
    }

    // MARK: Emails and phone numbers

    /// Tolerates a space either side of the @, which OCR sometimes inserts.
    nonisolated(unsafe) private static let emails = expression(
        #"(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]{1,64} ?@ ?[A-Za-z0-9-]{1,63}(?:\.[A-Za-z0-9-]{1,63}){0,8}"#
            + #"\.[A-Za-z]{2,24}(?![A-Za-z0-9-])"#
    )

    /// Foundation's phone detector knows international formats better than a regex would. It also accepts
    /// long digit runs, so matches are limited to 7 to 15 digits (the longest international number).
    nonisolated(unsafe) private static let phones = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue
    )

    // MARK: Helpers

    private static func dropNested(_ matches: [SensitiveMatch]) -> [SensitiveMatch] {
        var kept: [SensitiveMatch] = []
        // Larger first, so a nested match finds its container already kept. Ties keep the earlier pattern.
        let ordered = matches.enumerated().sorted {
            ($1.element.range.length, $0.offset) < ($0.element.range.length, $1.offset)
        }
        for (_, match) in ordered {
            let nested = kept.contains { other in
                other.kind == match.kind && NSIntersectionRange(other.range, match.range) == match.range
            }
            if !nested { kept.append(match) }
        }
        return kept
    }

    private static func expression(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants covered by tests.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern)
    }
}
