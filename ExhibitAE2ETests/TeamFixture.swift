import CoreGraphics
import ExhibitCore

/// A made-up team settings page at 2x for the instruction and bridge tests: a Pricing link, two example.com
/// addresses, a made-up key and an Invite button. Drawn in code; nothing from the real screen.
func teamFixture() -> Fixture {
    drawFixture(width: 700, height: 420, scale: 2) { screen in
        let ink = Ink(0.11, 0.11, 0.12)
        let muted = Ink(0.45, 0.45, 0.5)
        screen.fill(CGRect(x: 0, y: 0, width: 700, height: 420), Ink(1, 1, 1))
        screen.fill(CGRect(x: 0, y: 0, width: 180, height: 420), Ink(0.95, 0.95, 0.96))
        screen.text("Acme Cloud", at: CGPoint(x: 24, y: 22), size: 18, bold: true, ink)
        for (index, item) in ["Home", "Pricing", "Docs"].enumerated() {
            screen.text(item, at: CGPoint(x: 24, y: 76 + Double(index) * 36), size: 15, ink, name: item.lowercased())
        }
        screen.text("Team members", at: CGPoint(x: 210, y: 24), size: 20, bold: true, ink)
        screen.text("Ada Park", at: CGPoint(x: 210, y: 84), size: 14, ink)
        screen.text("ada.park@example.com", at: CGPoint(x: 400, y: 84), size: 14, ink, name: "email1")
        screen.text("Lee Ortiz", at: CGPoint(x: 210, y: 124), size: 14, ink)
        screen.text("lee.ortiz@example.com", at: CGPoint(x: 400, y: 124), size: 14, ink, name: "email2")
        screen.text("Deploy key", at: CGPoint(x: 210, y: 190), size: 12, muted)
        screen.text(FixtureValues.githubKey, at: CGPoint(x: 210, y: 210), size: 13, ink, name: "key")
        screen.button("Invite", frame: CGRect(x: 560, y: 350, width: 110, height: 34), primary: true, name: "invite")
    }
}
