import Foundation
import XCTest
@testable import PodcastStudyCore

final class StudyTests: XCTestCase {
    func pack(audio: Bool = true, count: Int = 1) -> StudyPack {
        StudyPack(format: "podcast-study-pack", version: 1, exportedAt: 1000,
                  episode: Episode(id: UUID().uuidString.lowercased(), title: "Test episode", sourceURL: "https://example.com/podcast", createdAt: 1000,
                                   cards: (0..<count).map { _ in StudyCard(id: UUID().uuidString.lowercased(), expression: "I see your point", meaning: "무슨 말인지 이해해요", quote: "I see your point.", sourceSentence: "I see your point.", sourceSentenceTranslation: "무슨 말인지 이해해요.", example: "A practice example.", exampleTranslation: "연습 예문입니다.", tip: "공감할 때", audio: audio ? OriginalAudio(base64: Data("ID3test".utf8).base64EncodedString(), duration: 2, start: 1, kind: "original-podcast-sentence") : nil, audioUnavailableReason: nil) }))
    }

    func library() throws -> PackLibrary {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try PackLibrary(root: root)
    }

    func testImportExtractsOriginalAudioAndReloadsWithoutBase64() throws {
        let storage = try library(), original = pack()
        let episode = try storage.importData(JSONEncoder().encode(original))
        XCTAssertNil(episode.cards[0].audio?.base64)
        XCTAssertEqual(try Data(contentsOf: storage.audioURL(episodeID: episode.id, cardID: episode.cards[0].id)), Data("ID3test".utf8))
        XCTAssertEqual(try storage.loadEpisodes().first?.cards.first?.expression, "I see your point")
    }

    func testReimportUpdatesEpisodeAndPreservesProgress() throws {
        let storage = try library()
        var original = pack()
        try storage.importData(JSONEncoder().encode(original))
        let id = original.episode.cards[0].id
        var progress = CardProgress(); progress.saved = true; progress.review(recalled: true, now: Date(timeIntervalSince1970: 1000))
        try storage.saveProgress([id: progress])
        original.episode.title = "Updated episode"
        try storage.importData(JSONEncoder().encode(original))
        XCTAssertEqual(try storage.loadEpisodes().count, 1)
        XCTAssertEqual(try storage.loadEpisodes()[0].title, "Updated episode")
        XCTAssertEqual(try storage.loadProgress()[id]?.reviews, 1)
        XCTAssertTrue(try XCTUnwrap(storage.loadProgress()[id]).saved)
    }

    func testInvalidImportPreservesExistingEpisode() throws {
        let storage = try library()
        var original = pack()
        try storage.importData(JSONEncoder().encode(original))
        original.episode.title = "Should never replace"
        original.episode.cards[0].audio?.base64 = "not base64!"
        XCTAssertThrowsError(try storage.importData(JSONEncoder().encode(original)))
        XCTAssertEqual(try storage.loadEpisodes()[0].title, "Test episode")
    }

    func testVersionTraversalDuplicatesAndUnsafeLinksRejected() throws {
        var value = pack()
        value.version = 2
        XCTAssertThrowsError(try value.validate())
        value = pack(); value.episode.id = "../../secret"
        XCTAssertThrowsError(try value.validate())
        value = pack(); value.episode.cards.append(value.episode.cards[0])
        XCTAssertThrowsError(try value.validate())
        value = pack(); value.episode.sourceURL = "javascript:alert(1)"
        XCTAssertThrowsError(try value.validate())
    }

    func testTextOnlyPackImports() throws {
        let storage = try library()
        try storage.importData(JSONEncoder().encode(pack(audio: false)))
        XCTAssertNil(try storage.loadEpisodes()[0].cards[0].audio)
    }

    func testRecallSchedulingAndFailureReset() {
        let now = Date(timeIntervalSince1970: 1000)
        var record = CardProgress()
        record.review(recalled: true, now: now)
        XCTAssertEqual(record.nextReviewAt, 1000 + 86400)
        record.review(recalled: true, now: now)
        XCTAssertEqual(record.nextReviewAt, 1000 + 3 * 86400)
        record.review(recalled: false, now: now)
        XCTAssertEqual(record.successes, 0)
        XCTAssertEqual(record.nextReviewAt, 1600)
        XCTAssertEqual(record.reviews, 3)
    }

    func testTodayPrioritizesDueAndDoesNotTreatSavedAsLearned() {
        let episode = pack(count: 15).episode
        let now = Date(timeIntervalSince1970: 1000)
        var progress: [String: CardProgress] = [:]
        for card in episode.cards.prefix(8) {
            var record = CardProgress(); record.review(recalled: false, now: Date(timeIntervalSince1970: 0))
            progress[card.id] = record
        }
        var saved = CardProgress(); saved.saved = true
        progress[episode.cards[8].id] = saved
        let queue = StudyQueue.today(episodes: [episode], progress: progress, now: now)
        XCTAssertEqual(queue.count, 10)
        XCTAssertTrue(queue.prefix(7).allSatisfy { progress[$0.id]?.reviews == 1 })
        XCTAssertTrue(queue.suffix(3).allSatisfy { (progress[$0.id]?.reviews ?? 0) == 0 })
        XCTAssertTrue(queue.contains { $0.id == episode.cards[8].id })
    }

    func testNoReviewBeforeDueAndNoMutationFromQueueNavigation() {
        let episode = pack().episode
        var progress = CardProgress(); progress.review(recalled: true, now: Date(timeIntervalSince1970: 1000))
        XCTAssertTrue(StudyQueue.today(episodes: [episode], progress: [episode.cards[0].id: progress], now: Date(timeIntervalSince1970: 1001)).isEmpty)
        XCTAssertEqual(progress.reviews, 1)
    }

    func testPythonExportCompatibility() throws {
        guard let path = ProcessInfo.processInfo.environment["PODSTUDY_FIXTURE"] else { throw XCTSkip("Python export fixture not provided") }
        let storage = try library()
        let episode = try storage.importFile(URL(fileURLWithPath: path))
        XCTAssertFalse(episode.cards.isEmpty)
        XCTAssertEqual(try storage.loadEpisodes().count, 1)
    }

    func testProgressBackupMergePreservesNewerHistoryAndUnknownIDs() throws {
        let storage = try library()
        let id = UUID().uuidString.lowercased(), unknownID = UUID().uuidString.lowercased()
        var older = CardProgress(); older.saved = true
        older.review(recalled: false, now: Date(timeIntervalSince1970: 1000))
        var unknown = CardProgress(); unknown.saved = true
        try storage.saveProgress([id: older, unknownID: unknown])
        let backup = try storage.exportProgressBackup(now: Date(timeIntervalSince1970: 2000))
        var newer = CardProgress(); newer.review(recalled: true, now: Date(timeIntervalSince1970: 3000))
        try storage.saveProgress([id: newer])
        let merged = try storage.importProgressBackup(backup)
        XCTAssertEqual(merged[id]?.lastReviewedAt, 3000)
        XCTAssertEqual(merged[id]?.nextReviewAt, 3000 + 86400)
        XCTAssertTrue(try XCTUnwrap(merged[id]).saved)
        XCTAssertTrue(try XCTUnwrap(merged[unknownID]).saved)
        XCTAssertEqual(try storage.loadProgress()[unknownID]?.reviews, 0)
    }

    func testProgressBackupRejectsCorruptionWithoutReplacingCurrentData() throws {
        let storage = try library()
        let id = UUID().uuidString.lowercased()
        var progress = CardProgress(); progress.saved = true
        try storage.saveProgress([id: progress])
        let before = try Data(contentsOf: storage.root.appendingPathComponent("progress.json"))
        var backup = ProgressBackup(exportedAt: 1000, progress: [id: progress])
        backup.progress[id]?.reviews = -1
        XCTAssertThrowsError(try storage.importProgressBackup(JSONEncoder().encode(backup)))
        backup.progress[id] = progress
        backup.progress[id.uppercased()] = progress
        XCTAssertThrowsError(try storage.importProgressBackup(JSONEncoder().encode(backup)))
        let after = try Data(contentsOf: storage.root.appendingPathComponent("progress.json"))
        XCTAssertEqual(before, after)
    }

    func testInterruptedReplacementRestoresOriginalEpisode() throws {
        let storage = try library()
        var original = pack(audio: false)
        try storage.importData(JSONEncoder().encode(original))
        let transaction = ImportTransaction(transactionID: UUID().uuidString.lowercased(), episodeID: original.episode.id, hadOriginal: true)
        let destination = storage.root.appendingPathComponent(original.episode.id)
        let backup = storage.root.appendingPathComponent(".backup-" + transaction.transactionID)
        let staging = storage.root.appendingPathComponent(".import-" + transaction.transactionID)
        let journal = storage.root.appendingPathComponent(".transaction-" + transaction.transactionID + ".json")
        try FileManager.default.moveItem(at: destination, to: backup)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        original.episode.title = "Uncommitted replacement"
        try JSONEncoder().encode(original).write(to: staging.appendingPathComponent("manifest.json"))
        try JSONEncoder().encode(transaction).write(to: journal)
        let recovered = try PackLibrary(root: storage.root)
        XCTAssertEqual(try recovered.loadEpisodes()[0].title, "Test episode")
        XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
    }

    func testCorruptRecoveryArtifactsArePreserved() throws {
        let storage = try library(), original = pack(audio: false)
        try storage.importData(JSONEncoder().encode(original))
        let transaction = ImportTransaction(transactionID: UUID().uuidString.lowercased(), episodeID: original.episode.id, hadOriginal: true)
        let backup = storage.root.appendingPathComponent(".backup-" + transaction.transactionID)
        let journal = storage.root.appendingPathComponent(".transaction-" + transaction.transactionID + ".json")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try Data("corrupt".utf8).write(to: backup.appendingPathComponent("manifest.json"))
        try JSONEncoder().encode(transaction).write(to: journal)
        XCTAssertThrowsError(try PackLibrary(root: storage.root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.root.appendingPathComponent(original.episode.id).path))
    }

    func testSwipeDirectionMatchesSaveAndSkip() {
        XCTAssertEqual(ReviewSwipeAction.resolve(horizontal: 110, vertical: 10, projectedHorizontal: 115, cardWidth: 360), .save)
        XCTAssertEqual(ReviewSwipeAction.resolve(horizontal: -110, vertical: -10, projectedHorizontal: -115, cardWidth: 360), .skip)
        XCTAssertEqual(ReviewSwipeAction.resolve(horizontal: 55, vertical: 5, projectedHorizontal: 200, cardWidth: 360), .save)
        XCTAssertEqual(ReviewSwipeAction.resolve(horizontal: -55, vertical: 5, projectedHorizontal: -200, cardWidth: 360), .skip)
    }

    func testReadingScrollAndShortDragsDoNotCommit() {
        let ignored: [(Double, Double, Double, Double)] = [
            (25, 0, 500, 360), (70, 0, 70, 360), (120, 200, 150, 360),
            (90, 80, 150, 360), (55, 5, -300, 360), (110, 0, 110, 0),
            (.infinity, 0, 150, 360), (110, .nan, 150, 360), (110, 0, .nan, 360)
        ]
        for (x, y, end, width) in ignored {
            XCTAssertNil(ReviewSwipeAction.resolve(horizontal: x, vertical: y, projectedHorizontal: end, cardWidth: width))
        }
    }

    func testSwipeRecordsExposureWithoutClaimingRecall() {
        let now = Date(timeIntervalSince1970: 1000)
        var skipped = CardProgress()
        skipped.recordSwipe(save: false, now: now)
        XCTAssertFalse(skipped.saved)
        XCTAssertEqual(skipped.reviews, 1)
        XCTAssertEqual(skipped.successes, 0)
        XCTAssertEqual(skipped.nextReviewAt, 87400)
        var saved = CardProgress()
        saved.recordSwipe(save: true, now: now)
        XCTAssertTrue(saved.saved)
        saved.recordSwipe(save: false, now: now.addingTimeInterval(10))
        XCTAssertTrue(saved.saved, "Left swipe never removes an existing bookmark")
        XCTAssertEqual(saved.successes, 0)
    }

    func testSwipePreservesLaterScheduleAndBacksUpBothChanges() throws {
        let storage = try library(), original = pack(audio: false)
        let id = original.episode.cards[0].id
        var record = CardProgress()
        record.review(recalled: true, now: Date(timeIntervalSince1970: 1000))
        record.review(recalled: true, now: Date(timeIntervalSince1970: 2000))
        let scheduled = record.nextReviewAt
        record.recordSwipe(save: true, now: Date(timeIntervalSince1970: 3000))
        XCTAssertEqual(record.nextReviewAt, scheduled)
        XCTAssertEqual(record.successes, 2)
        try storage.saveProgress([id: record])
        let restored = try library().importProgressBackup(storage.exportProgressBackup())
        XCTAssertTrue(try XCTUnwrap(restored[id]).saved)
        XCTAssertEqual(restored[id]?.reviews, 3)
        XCTAssertEqual(restored[id]?.successes, 2)
        XCTAssertTrue(StudyQueue.today(episodes: [original.episode], progress: restored, now: Date(timeIntervalSince1970: 3001)).isEmpty)
    }

}
