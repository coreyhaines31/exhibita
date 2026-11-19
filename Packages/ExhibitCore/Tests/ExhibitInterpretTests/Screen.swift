import ExhibitCore
@testable import ExhibitInterpret
import Foundation

/// A small screen: a nav bar, a pricing heading, buttons, two "Archive" lines and some secrets.
enum Screen {
    static func line(_ text: String, _ x: Double, _ y: Double, width: Double = 80) -> Target {
        Target(kind: .text, text: text, rect: PixelRect(x: x, y: y, width: width, height: 14))
    }

    static let pricing = line("Pricing", 200, 20)
    static let heading = line("Simple pricing for teams", 300, 120, width: 300)
    static let signUp = line("Sign up", 1100, 20)
    static let signIn = line("Sign in", 1000, 20)
    static let reply = line("Reply", 600, 400)
    static let forward = line("Forward", 680, 400)
    static let archiveButton = line("Archive", 780, 400)
    static let archiveNav = line("Archive", 20, 220)
    static let total = line("Total", 300, 600)
    static let emailLine = line("Contact: \u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}", 300, 300, width: 200)
    static let email = Target(kind: .email, rect: PixelRect(x: 370, y: 300, width: 130, height: 14))
    static let keyLine = line(String(repeating: "\u{2022}", count: 20), 300, 340, width: 200)
    static let key = Target(kind: .key, rect: PixelRect(x: 300, y: 340, width: 200, height: 14))
    static let openTickets = line("Open tickets", 900, 300)

    static let targets = [pricing, signIn, signUp, heading, archiveNav, emailLine, email, keyLine, key, openTickets,
                          reply, forward, archiveButton, total]
}
