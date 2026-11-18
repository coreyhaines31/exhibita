import ExhibitCore
import ExhibitShell
import ExhibitStore
import Foundation
import Testing

@Suite struct HistoryPresentationTests {
    let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    let english = Locale(identifier: "en_US")
    /// 2026-11-18 15:41 UTC.
    let now = Date(timeIntervalSince1970: 1_795_016_460)
    let day: TimeInterval = 86_400

    func item(_ createdAt: Date, capturedBy: CapturedBy = .person, app: String? = nil) -> HistoryItem {
        HistoryItem(id: UUID(), createdAt: createdAt, size: PixelSize(width: 1800, height: 1120), scale: 2,
                    capturedBy: capturedBy, appName: app, url: URL(fileURLWithPath: "/tmp/x.exhibit"))
    }

    @Test func describesWhenInPlainWords() {
        #expect(HistoryPresentation.when(now, now: now, calendar: utc, locale: english) == "Today 3:41 PM")
        #expect(HistoryPresentation.when(now.addingTimeInterval(-day), now: now, calendar: utc, locale: english)
            == "Yesterday 3:41 PM")
        #expect(HistoryPresentation.when(now.addingTimeInterval(-6 * day), now: now, calendar: utc, locale: english)
            == "Nov 12, 3:41 PM")
    }

    @Test func rowsCarryTitleSizeAgentTagAndSelection() {
        let agent = item(now, capturedBy: .agent)
        let person = item(now.addingTimeInterval(-60), app: "Safari")
        let rows = HistoryPresentation.rows([agent, person], policy: .default, selected: person.id, now: now,
                                            calendar: utc, locale: english)
        #expect(rows.map(\.title) == ["Capture", "Safari"])
        #expect(rows[0].subtitle == "Today 3:41 PM · 900 × 560")
        #expect(rows[0].tag == "by agent")
        #expect(rows[1].tag == nil)
        #expect(rows.map(\.isSelected) == [false, true])
        #expect(rows.allSatisfy { $0.expiry == nil })
    }

    @Test func showsExpiryOnlyNearTheSweep() {
        let rows = HistoryPresentation.rows(
            [item(now.addingTimeInterval(-27 * day)), item(now.addingTimeInterval(-29.5 * day)),
             item(now.addingTimeInterval(-26 * day))],
            policy: .default, now: now, calendar: utc, locale: english)
        #expect(rows.map(\.expiry) == ["Deleted in 3 days", "Deleted tomorrow", nil])
    }

    @Test func emptyStateNamesBothHotkeys() {
        let bindings = HotkeyBindings()
        let hint = HistoryPresentation.emptyHint(edit: bindings.combo(for: .captureAndEdit),
                                                 clipboard: bindings.combo(for: .captureToClipboard))
        #expect(hint == "Press ⌥⇧4 to capture and mark up, or ⌃⌥⇧4 to copy a capture.")
    }

    @Test func summarisesCountAndRetention() {
        #expect(HistoryPresentation.summary(count: 1, policy: .default) == "1 capture, kept 30 days")
        #expect(HistoryPresentation.summary(count: 3, policy: .discardOnExport) == "3 captures, kept until exported")
    }

    @Test func copyHasNoEmDashes() {
        let bindings = HotkeyBindings()
        var copy = [HistoryPresentation.emptyHint(edit: bindings.combo(for: .captureAndEdit),
                                                  clipboard: bindings.combo(for: .captureToClipboard))]
        for state in [ScreenRecordingState.granted, .notAsked, .denied] {
            copy += [state.title, state.message, state.buttonTitle]
        }
        copy += HotkeyAction.allCases.flatMap { [$0.title, $0.detail] }
        copy += [HotkeyIssue.needsModifier.message, HotkeyIssue.takenBySystem(.saveSelection).message]
        #expect(copy.allSatisfy { !$0.contains("\u{2014}") })
    }
}

@Suite struct PanelStateTests {
    @Test func permissionComesFirst() {
        #expect(ScreenRecordingState(preflight: true, hasAsked: false) == .granted)
        #expect(ScreenRecordingState(preflight: false, hasAsked: false) == .notAsked)
        #expect(ScreenRecordingState(preflight: false, hasAsked: true) == .denied)
        #expect(PanelContent.resolve(permission: .denied, historyCount: 4) == .permission(.denied))
        #expect(PanelContent.resolve(permission: .granted, historyCount: 0) == .empty)
        #expect(PanelContent.resolve(permission: .granted, historyCount: 2) == .history)
    }

    @Test func policyAllowsEverythingForNow() {
        let policy = CapturePolicy()
        #expect(policy.decision(for: CaptureSubject(bundleIdentifier: "com.apple.keychainaccess")) == .allow)
        #expect(policy.decision(for: CaptureSubject()) == .allow)
    }
}
