import Foundation
import XCTest
@testable import DexCleanerCore

final class ScanCacheClockRegressionTests: XCTestCase {
    func testFutureDatedCacheRecordIsRejectedAndPrunedBeforeSave() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("DexCleanerClockTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let target = home.appendingPathComponent("Library/Caches/Homebrew")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let now = Date()
        let cache = ScanCache(home: home.path, maximumAge: 60)
        cache.store(path: target.path, sizeBytes: 1234, scannedAt: now.addingTimeInterval(30))

        XCTAssertNil(cache.cachedRecord(path: target.path, now: now))

        cache.pruneExpired(now: now)
        cache.save()

        let cacheURL = home.appendingPathComponent("Library/Caches/DexCleaner/scan-cache.json")
        let data = try Data(contentsOf: cacheURL)
        let records = try JSONDecoder().decode([String: ScanCacheRecord].self, from: data)
        XCTAssertNil(records[SafetyEngine.lexicalNormalize(target.path)])
    }
}
