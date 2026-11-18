import CoreGraphics
import ExhibitCore
import ExhibitStore
import Foundation
import Testing

func temporaryStore() throws -> CaptureStore {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ExhibitStoreTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("Captures", isDirectory: true)
    return CaptureStore(directory: url)
}

func solidImage(width: Int = 80, height: Int = 50, gray: CGFloat = 0.5) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: gray, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private let day: TimeInterval = 86_400

@Suite struct CaptureStoreTests {
    @Test func preparesADirectoryOutsideBackupsAndSpotlight() throws {
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory.deletingLastPathComponent()) }
        try store.prepare()
        try store.prepare()
        #expect(store.isExcludedFromBackup)
        let marker = store.directory.appendingPathComponent(CaptureStore.neverIndexFileName)
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(store.list().isEmpty)
    }

    @Test func defaultDirectoryIsUnderApplicationSupport() throws {
        let url = try CaptureStore.defaultDirectory()
        #expect(url.path.hasSuffix("Application Support/Exhibit A/Captures"))
    }

    @Test func createsAndListsNewestFirst() throws {
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let older = try store.create(image: solidImage(), scale: 2, capturedBy: .person, appName: "Safari",
                                     now: now.addingTimeInterval(-60))
        let id = UUID()
        let newer = try store.create(image: solidImage(width: 40, height: 30), scale: 1, capturedBy: .agent, id: id,
                                     now: now)
        #expect(newer.id == id)
        #expect(newer.url == store.url(for: id))

        let items = store.list()
        #expect(items.map(\.id) == [id, older.id])
        #expect(items[0].byAgent)
        #expect(items[0].size == PixelSize(width: 40, height: 30))
        #expect(items[1].appName == "Safari")
        #expect(items[1].pointSize == (40, 25))
        #expect(items[1].markCount == 0)

        let loaded = try store.load(id)
        #expect(loaded.document.source?.capturedBy == .agent)
        #expect(loaded.original.width == 40)
    }

    @Test func savesMarksAndTargetsInPlace() throws {
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory.deletingLastPathComponent()) }
        let item = try store.create(image: solidImage(), scale: 1, capturedBy: .person)
        let target = Target(kind: .text, text: "Pricing", rect: PixelRect(x: 4, y: 4, width: 30, height: 10))
        try store.updateTargets([target], for: item.id)
        var document = try store.load(item.id).document
        document.marks.append(.box(PixelRect(x: 2, y: 2, width: 20, height: 20)))
        try store.save(document)
        try store.updateTargets([target, target], for: item.id)

        let listed = try #require(store.list().first)
        #expect(listed.markCount == 1)
        #expect(listed.targetCount == 2)
        #expect(try store.load(item.id).document.marks.count == 1)
    }

    @Test func listSkipsHalfWrittenUnknownAndNewerBundles() throws {
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory.deletingLastPathComponent()) }
        let kept = try store.create(image: solidImage(), scale: 1, capturedBy: .person)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: store.directory.appendingPathComponent(".\(UUID().uuidString).exhibit.partial"),
                                        withIntermediateDirectories: true)
        try fileManager.createDirectory(at: store.directory.appendingPathComponent("notes.exhibit"),
                                        withIntermediateDirectories: true)
        let newer = try store.create(image: solidImage(), scale: 1, capturedBy: .person)
        let json = newer.url.appendingPathComponent(CaptureBundle.documentFileName)
        let text = try String(contentsOf: json, encoding: .utf8)
            .replacingOccurrences(of: "\"formatVersion\" : 1", with: "\"formatVersion\" : 9")
        try Data(text.utf8).write(to: json)

        #expect(store.list().map(\.id) == [kept.id])
    }

    @Test func deletesOneAndPurgesAll() throws {
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory.deletingLastPathComponent()) }
        let first = try store.create(image: solidImage(), scale: 1, capturedBy: .person)
        let second = try store.create(image: solidImage(), scale: 1, capturedBy: .agent)
        try store.delete(first.id)
        try store.delete(first.id)
        #expect(store.list().map(\.id) == [second.id])
        #expect(!FileManager.default.fileExists(atPath: first.url.path))

        _ = try store.create(image: solidImage(), scale: 1, capturedBy: .person)
        try FileManager.default.createDirectory(
            at: store.directory.appendingPathComponent(".\(UUID().uuidString).exhibit.partial"),
            withIntermediateDirectories: true)
        #expect(try store.purgeAll() == 2)
        let left = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        #expect(left == [CaptureStore.neverIndexFileName])
    }

    @Test func exportsBesideACaptureGoWithIt() throws {
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory.deletingLastPathComponent()) }
        let first = try store.create(image: solidImage(), scale: 1, capturedBy: .agent)
        let second = try store.create(image: solidImage(), scale: 1, capturedBy: .agent)
        let name = first.id.uuidString
        #expect(store.exportURL(for: first.id).lastPathComponent == "\(name).png")
        let exports = ["\(name).png", "\(name)-marked.png", "\(name)-marked-3.png"]
        let kept = ["\(second.id.uuidString).png", "\(name)-notes.png", "\(name).txt"]
        for file in exports + kept {
            try Data([1]).write(to: store.directory.appendingPathComponent(file))
        }
        try store.delete(first.id)
        let left = Set(try FileManager.default.contentsOfDirectory(atPath: store.directory.path))
        #expect(left.isDisjoint(with: exports))
        #expect(left.isSuperset(of: kept))

        #expect(try store.purgeAll() == 1)
        let afterPurge = Set(try FileManager.default.contentsOfDirectory(atPath: store.directory.path))
        #expect(afterPurge == [CaptureStore.neverIndexFileName, "\(name)-notes.png", "\(name).txt"])
    }

    @Test func sweepDeletesOnlyExpiredCaptures() throws {
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func capture(daysAgo: Double) throws -> HistoryItem {
            try store.create(image: solidImage(), scale: 1, capturedBy: .person, now: now.addingTimeInterval(-daysAgo * day))
        }
        let old = try capture(daysAgo: 31)
        let edge = try capture(daysAgo: 30)
        let fresh = try capture(daysAgo: 29)
        let staging = store.directory.appendingPathComponent(".\(UUID().uuidString).exhibit.partial")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let swept = try store.sweep(policy: .default, now: now)
        #expect(Set(swept) == [old.id, edge.id])
        #expect(store.list().map(\.id) == [fresh.id])
        #expect(!FileManager.default.fileExists(atPath: staging.path))

        #expect(try store.sweep(policy: .days(1), now: now) == [fresh.id])
    }

    @Test func discardOnExportDeletesTheExportedCapture() throws {
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory.deletingLastPathComponent()) }
        let item = try store.create(image: solidImage(), scale: 1, capturedBy: .person)
        #expect(try store.didExport(item.id, policy: .default) == false)
        #expect(store.list().count == 1)
        #expect(try store.didExport(item.id, policy: .discardOnExport))
        #expect(store.list().isEmpty)
    }

    @Test func makesSmallThumbnails() throws {
        let store = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory.deletingLastPathComponent()) }
        let item = try store.create(image: solidImage(width: 1600, height: 1000), scale: 2, capturedBy: .person)
        let thumbnail = try #require(store.thumbnail(for: item.id, maxPixelSize: 160))
        #expect(max(thumbnail.width, thumbnail.height) == 160)
        #expect(store.thumbnail(for: UUID(), maxPixelSize: 160) == nil)
    }
}
