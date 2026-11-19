import ExhibitCore
import ExhibitFixtures

/// One mark of each kind, placed on the golden fixture.
func goldenMark(_ kind: MarkKind, on fixture: Fixture) -> Mark {
    switch kind {
    case .arrow: .arrow(from: fixture.point(120, 168), to: fixture.point(208, 158), label: "Click")
    case .circle: .circle(fixture["price"])
    case .blur: .blur(fixture["email"])
    case .highlight: .highlight(fixture["heading"])
    case .text: .text("Looks good", at: fixture.point(186, 24), color: .blue)
    case .box: .box(fixture["save"], color: .green)
    case .step: .step(2, at: fixture.point(198, 158))
    }
}

func sampleMarks(on fixture: Fixture) -> [Mark] {
    let update = fixture["update"]
    let navBilling = fixture["nav-Billing"]
    return [
        .blur(fixture["email"]),
        .blur(fixture["key"]),
        .highlight(fixture["renews"]),
        .box(PixelRect(x: 214 * 2, y: 124 * 2, width: 522 * 2, height: 144 * 2), color: .blue),
        .circle(fixture["price"]),
        .arrow(from: fixture.point(520, 172), to: PixelPoint(x: update.minX - 6, y: update.minY + 4), label: "Click here"),
        .step(1, at: PixelPoint(x: 150 * 2, y: navBilling.midY)),
        .step(2, at: PixelPoint(x: fixture["cancel"].minX - 26 * 2, y: fixture["cancel"].midY)),
        .text("Secrets are blurred", at: fixture.point(560, 382), color: .yellow)
    ]
}
