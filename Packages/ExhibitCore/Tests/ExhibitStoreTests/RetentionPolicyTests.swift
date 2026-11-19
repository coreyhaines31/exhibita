import ExhibitStore
import Foundation
import Testing

@Suite struct RetentionPolicyTests {
    let created = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400

    @Test func defaultKeepsThirtyDays() {
        #expect(RetentionPolicy.default == .days(30))
        #expect(!RetentionPolicy.default.isExpired(createdAt: created, now: created.addingTimeInterval(30 * day - 1)))
        #expect(RetentionPolicy.default.isExpired(createdAt: created, now: created.addingTimeInterval(30 * day)))
    }

    @Test func discardOnExportStillSweepsUnexportedCaptures() {
        let policy = RetentionPolicy.discardOnExport
        #expect(policy.discardsOnExport)
        #expect(policy.keptDays == RetentionPolicy.fallbackDays)
        #expect(policy.isExpired(createdAt: created, now: created.addingTimeInterval(30 * day)))
        #expect(!RetentionPolicy.days(7).discardsOnExport)
    }

    @Test func countsDaysLeftRoundingUp() {
        let policy = RetentionPolicy.days(7)
        #expect(policy.daysLeft(createdAt: created, now: created) == 7)
        #expect(policy.daysLeft(createdAt: created, now: created.addingTimeInterval(6.5 * day)) == 1)
        #expect(policy.daysLeft(createdAt: created, now: created.addingTimeInterval(7 * day)) == 0)
        #expect(policy.daysLeft(createdAt: created, now: created.addingTimeInterval(40 * day)) == 0)
    }

    @Test func roundTripsThroughStorage() {
        for policy in RetentionPolicy.choices {
            #expect(RetentionPolicy(storageValue: policy.storageValue) == policy)
        }
        #expect(RetentionPolicy(storageValue: "days:0") == nil)
        #expect(RetentionPolicy(storageValue: "forever") == nil)
        #expect(RetentionPolicy.choices.map(\.title) == ["Until exported", "1 day", "7 days", "30 days", "90 days"])
    }

    @Test func aZeroDayPolicyStillKeepsOneDay() {
        #expect(RetentionPolicy.days(0).keptDays == 1)
    }
}
