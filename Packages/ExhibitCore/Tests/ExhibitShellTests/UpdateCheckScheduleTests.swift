import ExhibitShell
import Foundation
import Testing

@Suite struct UpdateCheckScheduleTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func checksWhenTheLastCheckIsOverAnHourOld() {
        let old = now.addingTimeInterval(-3601)
        #expect(UpdateCheckSchedule.isDueAtLaunch(lastCheck: old, now: now, checksAutomatically: true))
        #expect(UpdateCheckSchedule.isDueAtLaunch(lastCheck: now.addingTimeInterval(-86_400 * 9), now: now,
                                                  checksAutomatically: true))
    }

    @Test func waitsWithinTheHour() {
        #expect(!UpdateCheckSchedule.isDueAtLaunch(lastCheck: now.addingTimeInterval(-3599), now: now,
                                                   checksAutomatically: true))
        #expect(!UpdateCheckSchedule.isDueAtLaunch(lastCheck: now.addingTimeInterval(-3600), now: now,
                                                   checksAutomatically: true), "exactly an hour is not more")
        #expect(!UpdateCheckSchedule.isDueAtLaunch(lastCheck: now, now: now, checksAutomatically: true))
    }

    @Test func checksWhenNeverCheckedOrTheClockMovedBack() {
        #expect(UpdateCheckSchedule.isDueAtLaunch(lastCheck: nil, now: now, checksAutomatically: true))
        #expect(UpdateCheckSchedule.isDueAtLaunch(lastCheck: now.addingTimeInterval(600), now: now,
                                                  checksAutomatically: true))
    }

    @Test func neverChecksWithAutomaticChecksOff() {
        for last in [nil, now.addingTimeInterval(-86_400), now] as [Date?] {
            #expect(!UpdateCheckSchedule.isDueAtLaunch(lastCheck: last, now: now, checksAutomatically: false))
        }
    }
}
