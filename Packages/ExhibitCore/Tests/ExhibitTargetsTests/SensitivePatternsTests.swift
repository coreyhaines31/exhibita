import ExhibitCore
@testable import ExhibitTargets
import Foundation
import Testing

/// Fake keys are assembled at run time, so no realistic key ever sits in the source.
enum FakeKeys {
    static func repeated(_ unit: String, _ count: Int) -> String { String(repeating: unit, count: count) }
    static var github: String { "gh" + "p_" + repeated("Ab1x", 9) }
    static var stripe: String { "sk" + "_live_" + repeated("Zq9w", 6) }
    static var aws: String { "AK" + "IA" + repeated("Q7", 8) }
    static var anthropic: String { "sk-" + "ant-" + repeated("aB3_", 6) }
    static var slack: String { "xo" + "xb-" + repeated("1234-", 3) + "abcd" }
    static var generic: String { "nw" + "_live_" + "7Hq2LmX9pT4vR8sK3dWzB6" }
    static var hex: String { repeated("9f3a", 10) }
    // 4242 4242 4242 4242 is the well-known test Visa number; it passes Luhn.
    static var visa: String { repeated("4242 ", 3) + "4242" }
    static var amex: String { "3782 " + "822463 " + "10005" }
}

private struct Found {
    let kind: TargetKind
    let name: String
    let text: String
}

private func found(_ text: String) -> [Found] {
    SensitivePatterns.matches(in: text).map {
        Found(kind: $0.kind, name: $0.name, text: (text as NSString).substring(with: $0.range))
    }
}

private func kinds(_ text: String) -> [TargetKind] { found(text).map(\.kind) }

@Suite struct SensitivePatternsTests {
    @Test func namedKeysAreFoundWithTheirNames() {
        let cases: [(String, String)] = [
            (FakeKeys.github, "GitHub token"),
            (FakeKeys.stripe, "Stripe secret key"),
            (FakeKeys.aws, "AWS access key"),
            (FakeKeys.anthropic, "Anthropic API key"),
            (FakeKeys.slack, "Slack token"),
            ("-----BEGIN RSA " + "PRIVATE KEY-----", "private key")
        ]
        for (key, name) in cases {
            let result = found("token \(key) here")
            #expect(result.count == 1, "\(name): \(result)")
            #expect(result.first?.kind == .key)
            #expect(result.first?.name == name)
            #expect(result.first?.text == key)
        }
    }

    @Test func genericTokensAndHexAreKeys() {
        #expect(found("API key \(FakeKeys.generic)").map(\.text) == [FakeKeys.generic])
        #expect(found("hash \(FakeKeys.hex) done").map(\.text) == [FakeKeys.hex])
    }

    @Test func ordinaryTextIsNotAKey() {
        for text in ["Manage your plan, payment details and invoices.", "Renews on December 1, 2026",
                     "Nov 1, 2026    $49.00    Paid", "NSRegularExpression", "the_quick_brown_fox_jumps",
                     "/Users/example/Library/Application Support", "v1.2.3-beta4"] {
            #expect(kinds(text).isEmpty, "\(text): \(found(text))")
        }
    }

    @Test func databaseURLsMarkOnlyThePassword() {
        let url = "postgres://app:" + "hunter2hunter" + "@db.example.com/main"
        #expect(found(url).map(\.text) == ["hunter2hunter"])
    }

    @Test func envLinesMarkOnlyTheValue() {
        let value = "s3cr3t" + "value99"
        #expect(found("export STRIPE_API_KEY=\(value)").map(\.text) == [value])
        #expect(found("Password: \(value)").map(\.text) == [value])
        #expect(kinds("API_KEY=$OTHER_VARIABLE").isEmpty)
    }

    @Test func cardsNeedLuhnAndAKnownPrefix() {
        #expect(found("Card \(FakeKeys.visa) exp").map(\.kind) == [.card])
        #expect(found("Card \(FakeKeys.visa) exp").map(\.text) == [FakeKeys.visa])
        #expect(found(FakeKeys.amex).map(\.kind) == [.card])
        #expect(kinds("4242 4242 4242 4241").isEmpty, "fails Luhn")
        #expect(kinds("1234 5678 9012 3456").isEmpty, "unknown prefix")
    }

    @Test func cardsTolerateOCRNoise() {
        // Unspaced, doubled spaces, and look-alike letters for 0 and 1.
        #expect(kinds("4242424242424242") == [.card])
        #expect(kinds("4242  4242  4242  4242") == [.card])
        let lookalike = "3782 822463 lOOO5"
        #expect(found(lookalike).map(\.text) == [lookalike])
    }

    @Test func aCardFollowedByAnotherNumberIsStillFound() {
        let text = "\(FakeKeys.visa) 12 28"
        #expect(found(text).map(\.text) == [FakeKeys.visa])
    }

    @Test func socialSecurityNumbersAreKeys() {
        #expect(found("SSN 123-45-6789").map(\.name) == ["Social Security number"])
        // An impossible area number is not a Social Security number (it may still read as a phone number).
        #expect(!kinds("SSN 000-45-6789").contains(.key))
    }

    @Test func emailsAreFoundWithOCRSpacing() {
        #expect(found("Billing jordan.lee@example.com.").map(\.text) == ["jordan.lee@example.com"])
        #expect(found("sam @example.com").map(\.kind) == [.email])
        #expect(kinds("no at sign example.com").isEmpty)
    }

    @Test func phonesAreFoundButNotInsideCards() {
        #expect(kinds("Call (415) 555-0132 today") == [.phone])
        #expect(kinds("+44 20 7946 0958") == [.phone])
        #expect(kinds(FakeKeys.visa) == [.card])
    }

    @Test func nestedMatchesOfOneKindCollapse() {
        // The Stripe key also fits the generic token rule; only the named match is kept.
        #expect(found(FakeKeys.stripe).map(\.name) == ["Stripe secret key"])
    }

    @Test func longLinesFinishQuickly() {
        let line = String(repeating: "aB3_", count: 5_000) + " " + String(repeating: "4 ", count: 5_000)
            + String(repeating: "A", count: 20_000) + "@"
        let start = Date()
        _ = SensitivePatterns.matches(in: line)
        #expect(Date().timeIntervalSince(start) < 2)
    }
}
