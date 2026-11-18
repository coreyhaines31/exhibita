import CoreGraphics
import ExhibitCore

/// Made-up sensitive values for detection fixtures. Keys are assembled at run time so no realistic key sits in
/// the source.
public enum FixtureValues {
    public static let email = "sam.rivera@example.com"
    // 4242 4242 4242 4242 is the well-known test Visa number; it passes Luhn.
    public static let card = String(repeating: "4242 ", count: 3) + "4242"
    public static let phone = "(415) 555-0132"
    public static var githubKey: String { "gh" + "p_" + String(repeating: "Rk7m", count: 9) }
    /// A made-up token that OCR misreads with look-alike letters in `lookalikeFixture`.
    public static var lookalikeKey: String { "tk_" + "Zx81LmQ02vBn77PqRsT4uVw9" }
}

/// A plain settings page with one line per kind of target, for detection tests.
public func targetsFixture(scale: Double) -> Fixture {
    drawFixture(width: 560, height: 260, scale: scale) { screen in
        let muted = Ink(0.45, 0.45, 0.5)
        screen.fill(CGRect(x: 0, y: 0, width: 560, height: 260), Ink(1, 1, 1))
        screen.text("See Pricing and plans", at: CGPoint(x: 24, y: 20), size: 15, name: "pricing-line",
                    parts: ["Pricing": "Pricing"])
        screen.text("Contact \(FixtureValues.email)", at: CGPoint(x: 24, y: 60), size: 15, name: "email-line",
                    parts: ["email": FixtureValues.email])
        screen.text("Card \(FixtureValues.card)", at: CGPoint(x: 24, y: 100), size: 15, name: "card-line",
                    parts: ["card": FixtureValues.card])
        screen.text("Call \(FixtureValues.phone)", at: CGPoint(x: 24, y: 140), size: 15, name: "phone-line",
                    parts: ["phone": FixtureValues.phone])
        screen.text("Token \(FixtureValues.githubKey)", at: CGPoint(x: 24, y: 180), size: 15, name: "key-line",
                    parts: ["key": FixtureValues.githubKey])
        screen.text("Muted footnote text", at: CGPoint(x: 24, y: 222), size: 12, muted, name: "muted-line")
    }
}

/// A heading and an env line in Helvetica Bold that Vision's accurate recognizer (macOS 26) reads with Cyrillic
/// look-alikes: "Acme" as "Астe" and the key with a Cyrillic х and В. Reproduces issue 20.
public func lookalikeFixture() -> Fixture {
    drawFixture(width: 640, height: 130, scale: 1) { screen in
        let ink = Ink(0.07, 0.07, 0.07)
        screen.fill(CGRect(x: 0, y: 0, width: 640, height: 130), Ink(1, 1, 1))
        screen.text("Acme Dashboard", at: CGPoint(x: 40, y: 20), size: 32, ink, name: "heading", font: "Helvetica-Bold")
        screen.text("ACME_KEY=\(FixtureValues.lookalikeKey)", at: CGPoint(x: 40, y: 80), size: 20, ink, name: "env-line",
                    parts: ["key": FixtureValues.lookalikeKey], font: "Helvetica-Bold")
    }
}
