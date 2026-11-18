import ExhibitCore
import ExhibitFixtures
import ExhibitTargets
import Foundation
import Testing

/// Many callers at once from Swift concurrency must all finish. Before Vision work moved to its own queue, these
/// deadlocked: every cooperative thread sat in `perform`, waiting for work that needed one of those threads.
@Suite(.timeLimit(.minutes(1))) struct ConcurrentFindingTests {
    static let callers = 32

    @Test func manyBlockingCallsFromTasksAllFinish() async throws {
        let image = targetsFixture(scale: 1).image
        let counts = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<Self.callers {
                // The synchronous form, blocking a cooperative thread, which is what deadlocked.
                group.addTask { try TargetFinder().findTargets(in: image).count }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(counts.count == Self.callers)
        #expect(Set(counts).count == 1)
    }

    @Test func manyAsyncCallsAllFinish() async throws {
        let image = targetsFixture(scale: 1).image
        let counts = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<Self.callers {
                group.addTask { try await TargetFinder().findTargets(in: image).count }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(counts.count == Self.callers)
        #expect(Set(counts).count == 1)
    }
}
