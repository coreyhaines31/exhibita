import CoreGraphics
import ExhibitCore

/// A Retina-sized fake billing settings window, for `docs/samples/all-marks.png`.
public func sampleFixture() -> Fixture {
    drawFixture(width: 760, height: 480, scale: 2) { screen in
        let ink = Ink(0.11, 0.11, 0.12)
        let muted = Ink(0.45, 0.45, 0.5)
        screen.fill(CGRect(x: 0, y: 0, width: 760, height: 480), Ink(0.93, 0.93, 0.95))

        // Window chrome.
        screen.fill(CGRect(x: 0, y: 0, width: 760, height: 40), Ink(0.97, 0.97, 0.98))
        screen.fill(CGRect(x: 0, y: 40, width: 760, height: 1), 0.85)
        for (index, gray) in [0.78, 0.82, 0.86].enumerated() {
            screen.dot(center: CGPoint(x: 20 + Double(index) * 20, y: 20), radius: 6, Ink(gray, gray, gray))
        }
        screen.text("Northwind Console", at: CGPoint(x: 316, y: 12), size: 13, bold: true, muted)

        // Sidebar.
        screen.fill(CGRect(x: 0, y: 41, width: 190, height: 439), Ink(0.95, 0.95, 0.96))
        screen.fill(CGRect(x: 190, y: 41, width: 1, height: 439), 0.87)
        let items = ["General", "Billing", "Team", "API keys", "Notifications"]
        for (index, item) in items.enumerated() {
            let top = 64 + Double(index) * 34
            if item == "Billing" {
                screen.fill(CGRect(x: 12, y: top - 7, width: 166, height: 30), Ink(0.86, 0.9, 0.98), radius: 6)
            }
            screen.text(item, at: CGPoint(x: 28, y: top), size: 13, bold: item == "Billing", ink, name: "nav-\(item)")
        }

        // Content.
        screen.fill(CGRect(x: 191, y: 41, width: 569, height: 439), Ink(1, 1, 1))
        screen.text("Billing", at: CGPoint(x: 220, y: 62), size: 22, bold: true, ink)
        screen.text("Manage your plan, payment details and invoices.", at: CGPoint(x: 220, y: 96), size: 13, muted)

        screen.fill(CGRect(x: 220, y: 130, width: 510, height: 132), Ink(0.98, 0.98, 0.99), radius: 10)
        screen.stroke(CGRect(x: 220, y: 130, width: 510, height: 132), Ink(0.88, 0.88, 0.9), radius: 10)
        screen.text("Current plan", at: CGPoint(x: 240, y: 148), size: 11, muted)
        screen.text("Pro", at: CGPoint(x: 240, y: 166), size: 17, bold: true, ink)
        screen.text("$49/mo", at: CGPoint(x: 640, y: 166), size: 17, bold: true, ink, name: "price")
        screen.text("Renews on December 1, 2026", at: CGPoint(x: 240, y: 196), size: 13, ink, name: "renews")
        screen.text("Includes 10 seats and priority support.", at: CGPoint(x: 240, y: 218), size: 13, muted)
        screen.button("Update plan", frame: CGRect(x: 600, y: 210, width: 110, height: 32), primary: true, name: "update")

        screen.text("Billing email", at: CGPoint(x: 220, y: 290), size: 11, muted)
        screen.text("jordan.lee@example.com", at: CGPoint(x: 220, y: 306), size: 13, ink, name: "email")
        screen.text("API key", at: CGPoint(x: 460, y: 290), size: 11, muted)
        screen.text("nw_live_7Hq2LmX9pT4vR8sK3dWzB6", at: CGPoint(x: 460, y: 306), size: 13, ink, name: "key")

        screen.fill(CGRect(x: 220, y: 344, width: 510, height: 1), 0.9)
        screen.text("Invoices", at: CGPoint(x: 220, y: 362), size: 15, bold: true, ink)
        for (index, row) in ["Nov 1, 2026    $49.00    Paid", "Oct 1, 2026    $49.00    Paid"].enumerated() {
            screen.text(row, at: CGPoint(x: 220, y: 392 + Double(index) * 24), size: 13, ink)
        }
        screen.button("Cancel plan", frame: CGRect(x: 610, y: 430, width: 120, height: 32), primary: false, name: "cancel")
    }
}
