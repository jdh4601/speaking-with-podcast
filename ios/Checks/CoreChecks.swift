import Foundation

/// Runs without XCTest/iOS SDK: swiftc Core/*.swift Checks/CoreChecks.swift -o checks.
@main
struct CoreChecks {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw StudyError.invalid("CHECK FAILED: " + message) }
    }
    static func rejects(_ action: () throws -> Void, _ message: String) throws {
        var rejected = false
        do { try action() } catch { rejected = true }
        try expect(rejected, message)
    }
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw StudyError.invalid("Pass a Python-exported .podstudy fixture path.") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = try PackLibrary(root: root)
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let data = try Data(contentsOf: input)
        var pack = try JSONDecoder().decode(StudyPack.self, from: data)
        let episode = try storage.importFile(input)
        try expect(!episode.cards.isEmpty, "Python export imports")
        let loaded = try storage.loadEpisodes()
        try expect(loaded.count == 1 && loaded[0].id == episode.id, "episode survives reload")
        print("PASS Python export → Swift import → reload")

        let id = episode.cards[0].id
        var record = CardProgress(); record.saved = true
        let now = Date(timeIntervalSince1970: 1000)
        record.review(recalled: true, now: now)
        try expect(record.nextReviewAt == 87400, "first recall schedules tomorrow")
        record.review(recalled: true, now: now)
        try expect(record.nextReviewAt == 260200, "second recall schedules three days")
        record.review(recalled: false, now: now)
        try expect(record.nextReviewAt == 1600 && record.successes == 0, "failure resets interval")
        try storage.saveProgress([id: record])
        pack.episode.title = "Updated title"
        try storage.importData(JSONEncoder().encode(pack))
        let restored = try storage.loadProgress()
        try expect(restored[id]?.saved == true && restored[id]?.reviews == 3, "reimport preserves saved state and history")
        print("PASS recall intervals, failure reset, reimport preserves history")

        var invalid = pack; invalid.version = 99
        try rejects({ try storage.importData(JSONEncoder().encode(invalid)) }, "unsupported version")
        invalid = pack; invalid.episode.id = "../../escape"
        try rejects({ try invalid.validate() }, "path traversal")
        invalid = pack; invalid.episode.cards.append(invalid.episode.cards[0])
        try rejects({ try invalid.validate() }, "duplicate identity")
        invalid = pack; invalid.episode.sourceURL = "javascript:alert(1)"
        try rejects({ try invalid.validate() }, "unsafe source URL")
        invalid = pack; invalid.episode.cards[0].audio = OriginalAudio(base64: "bad!", duration: 2, start: 0, kind: "original-podcast-sentence")
        try rejects({ try storage.importData(JSONEncoder().encode(invalid)) }, "corrupt audio")
        let afterFailed = try storage.loadEpisodes()
        try expect(afterFailed[0].title == "Updated title", "failed import preserves existing episode")
        print("PASS invalid version, path, duplicate, link, audio rejected; old data preserved")

        pack.episode.cards[0].sourceSentence = "Verified test sentence."
        pack.episode.cards[0].audio = OriginalAudio(base64: Data("ID3test".utf8).base64EncodedString(), duration: 2, start: 0, kind: "original-podcast-sentence")
        let withAudio = try storage.importData(JSONEncoder().encode(pack))
        let audio = try Data(contentsOf: storage.audioURL(episodeID: withAudio.id, cardID: id))
        try expect(audio == Data("ID3test".utf8), "audio bytes survive import")
        try expect(withAudio.cards[0].audio?.base64 == nil, "manifest does not retain inline audio")
        print("PASS embedded audio extracted and bytes preserved")

        var tomorrow = CardProgress(); tomorrow.review(recalled: true, now: now)
        let only = Episode(id: episode.id, title: episode.title, sourceURL: episode.sourceURL, createdAt: episode.createdAt, cards: [episode.cards[0]])
        try expect(StudyQueue.today(episodes: [only], progress: [id: tomorrow], now: now).isEmpty, "future reviews excluded")
        var savedOnly = CardProgress(); savedOnly.saved = true
        try expect(StudyQueue.today(episodes: [only], progress: [id: savedOnly], now: now).count == 1, "saving is not learning")
        try expect(StudyQueue.today(episodes: [episode], progress: [:], now: now).count == min(10, episode.cards.count), "daily cap")
        try expect(savedOnly.reviews == 0, "queue navigation never rates")
        print("PASS due dates, saved/new separation, daily cap, navigation does not rate")
        try backupChecks(storage: storage, id: id)
        try recoveryChecks(pack: pack)

    }

    static func backupChecks(storage: PackLibrary, id: String) throws {
        let older = try storage.exportProgressBackup(now: Date(timeIntervalSince1970: 2000))
        let unknownID = "f4031abe-f12d-4c18-b222-0542bca878b9"
        var unknown = CardProgress(); unknown.saved = true
        var backup = try JSONDecoder().decode(ProgressBackup.self, from: older)
        backup.progress[unknownID] = unknown
        var newer = CardProgress(); newer.review(recalled: true, now: Date(timeIntervalSince1970: 5000))
        try storage.saveProgress([id: newer])
        let merged = try storage.importProgressBackup(JSONEncoder().encode(backup))
        try expect(merged[id]?.lastReviewedAt == 5000, "older backup cannot regress newer review time")
        try expect(merged[id]?.reviews == 3, "restoring never decreases review count")
        try expect(merged[id]?.saved == true, "bookmarks are unioned")
        try expect(merged[unknownID]?.saved == true, "unknown episode records retained")
        let secondRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: secondRoot) }
        let second = try PackLibrary(root: secondRoot)
        let roundTrip = try second.importProgressBackup(storage.exportProgressBackup(now: Date(timeIntervalSince1970: 6000)))
        try expect(roundTrip[id]?.lastReviewedAt == 5000 && roundTrip[unknownID]?.saved == true, "backup round trip after reinstall")
        let before = try Data(contentsOf: storage.root.appendingPathComponent("progress.json"))
        backup.version = 99
        try rejects({ try storage.importProgressBackup(JSONEncoder().encode(backup)) }, "unsupported progress version")
        backup.version = 1
        backup.progress[unknownID]?.reviews = -1
        try rejects({ try storage.importProgressBackup(JSONEncoder().encode(backup)) }, "negative counters")
        backup.progress[unknownID] = unknown
        backup.progress[unknownID.uppercased()] = unknown
        try rejects({ try storage.importProgressBackup(JSONEncoder().encode(backup)) }, "UUID case aliases")
        let recordJSON = String(decoding: try JSONEncoder().encode(unknown), as: UTF8.self)
        let duplicate = "{\"format\":\"podcast-study-progress\",\"version\":1,\"exportedAt\":1000,\"progress\":{\"\(unknownID)\":\(recordJSON),\"\(unknownID)\":\(recordJSON)}}"
        try rejects({ try storage.importProgressBackup(Data(duplicate.utf8)) }, "exact duplicate JSON keys")
        backup.progress = [id: newer]; backup.progress[id]?.nextReviewAt = -1
        try rejects({ try storage.importProgressBackup(JSONEncoder().encode(backup)) }, "invalid timestamp")
        try rejects({ try storage.importProgressBackup(Data(repeating: 32, count: PackLibrary.maxProgressBytes + 1)) }, "oversized progress backup")
        let after = try Data(contentsOf: storage.root.appendingPathComponent("progress.json"))
        try expect(before == after, "invalid backups preserve current data byte for byte")
        print("PASS progress backup round trip, merge, unknown IDs, invalid backup isolation")
    }

    static func recoveryChecks(pack input: StudyPack) throws {
        var original = input
        original.episode.title = "Original before interruption"
        for index in original.episode.cards.indices { original.episode.cards[index].audio = nil }
        var replacement = original; replacement.episode.title = "Replacement after commit"
        let manager = FileManager.default
        func scenario(_ phase: String) throws {
            let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? manager.removeItem(at: root) }
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            let transaction = ImportTransaction(transactionID: UUID().uuidString.lowercased(), episodeID: original.episode.id, hadOriginal: phase != "fresh")
            let destination = root.appendingPathComponent(original.episode.id)
            let staging = root.appendingPathComponent(".import-" + transaction.transactionID)
            let backup = root.appendingPathComponent(".backup-" + transaction.transactionID)
            let journal = root.appendingPathComponent(".transaction-" + transaction.transactionID + ".json")
            func write(_ pack: StudyPack, to path: URL) throws {
                try manager.createDirectory(at: path, withIntermediateDirectories: true)
                try JSONEncoder().encode(pack).write(to: path.appendingPathComponent("manifest.json"))
            }
            if phase == "prepared" { try write(original, to: destination); try write(replacement, to: staging) }
            if phase == "renamed" { try write(original, to: backup); try write(replacement, to: staging) }
            if phase == "committed" || phase == "corrupt" { try write(original, to: backup); try write(replacement, to: destination) }
            if phase == "fresh" { try write(replacement, to: staging) }
            try JSONEncoder().encode(transaction).write(to: journal)
            let unrelated = root.appendingPathComponent(".backup-unrelated")
            try manager.createDirectory(at: unrelated, withIntermediateDirectories: true)
            if phase == "corrupt" {
                try Data("broken json".utf8).write(to: backup.appendingPathComponent("manifest.json"))
                try rejects({ _ = try PackLibrary(root: root) }, "corrupt recovery data must not be silently discarded")
                try expect(manager.fileExists(atPath: journal.path) && manager.fileExists(atPath: backup.path) && manager.fileExists(atPath: destination.path), "corrupt artifacts preserved")
                return
            }
            let recovered = try PackLibrary(root: root)
            let loaded = try recovered.loadEpisodes()
            try expect(loaded.count == 1, "one episode survives interruption at \(phase)")
            let expected = phase == "committed" || phase == "fresh" ? replacement.episode.title : original.episode.title
            try expect(loaded[0].title == expected, "deterministic recovery at \(phase)")
            try expect(!manager.fileExists(atPath: journal.path) && !manager.fileExists(atPath: staging.path) && !manager.fileExists(atPath: backup.path), "recovered transaction cleaned at \(phase)")
            try expect(manager.fileExists(atPath: unrelated.path), "unrelated folders preserved")
            _ = try PackLibrary(root: root)
        }
        for phase in ["prepared", "renamed", "committed", "fresh", "corrupt"] { try scenario(phase) }
        print("PASS journal recovery before/after renames, fresh imports, corrupt artifact preservation")
    }
}
