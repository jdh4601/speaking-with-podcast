import Foundation

/// Foundation-only storage also runs in the Mac test suite.
final class PackLibrary {
    let root: URL
    private let manager = FileManager.default
    static let maxBytes = 64 * 1024 * 1024
    static let maxProgressBytes = 4 * 1024 * 1024
    static let maxProgressRecords = 10_000
    private static let latestTimestamp = 253_402_300_799.0

    init(root: URL) throws {
        self.root = root
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try recoverPendingImports()
    }

    func loadEpisodes() throws -> [Episode] {
        try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .map { try readStoredPack(at: $0, expectedID: $0.lastPathComponent).episode }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func loadProgress() throws -> [String: CardProgress] {
        let path = root.appendingPathComponent("progress.json")
        guard manager.fileExists(atPath: path.path) else { return [:] }
        let data = try readProgressFile(path)
        try rejectDuplicateJSONKeys(data)
        return try validatedProgress(JSONDecoder().decode([String: CardProgress].self, from: data))
    }

    func saveProgress(_ progress: [String: CardProgress]) throws {
        let normalized = try validatedProgress(progress)
        let data = try JSONEncoder().encode(normalized)
        guard data.count <= Self.maxProgressBytes else { throw StudyError.invalid("복습 기록이 4MB를 넘습니다.") }
        try data.write(to: root.appendingPathComponent("progress.json"), options: .atomic)
    }

    func exportProgressBackup(now: Date = Date()) throws -> Data {
        let timestamp = now.timeIntervalSince1970
        guard Self.validTimestamp(timestamp) else { throw StudyError.invalid("백업 시간이 올바르지 않습니다.") }
        let backup = ProgressBackup(exportedAt: timestamp, progress: try loadProgress())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(backup)
        guard data.count <= Self.maxProgressBytes else { throw StudyError.invalid("복습 백업이 4MB를 넘습니다.") }
        return data
    }

    /// Keep the newer review schedule, never decrease review count, and union bookmarks.
    /// Records for episodes not currently on this device are retained for later reimports.
    @discardableResult
    func importProgressBackup(_ data: Data) throws -> [String: CardProgress] {
        guard !data.isEmpty, data.count <= Self.maxProgressBytes else { throw StudyError.invalid("4MB 이하의 복습 백업을 선택하세요.") }
        try rejectDuplicateJSONKeys(data)
        let backup = try JSONDecoder().decode(ProgressBackup.self, from: data)
        guard backup.format == "podcast-study-progress", backup.version == 1, Self.validTimestamp(backup.exportedAt) else {
            throw StudyError.invalid("지원하지 않거나 손상된 복습 백업입니다.")
        }
        let incoming = try validatedProgress(backup.progress)
        var merged = try loadProgress()
        for (id, imported) in incoming {
            if let existing = merged[id] {
                let incomingTime = imported.lastReviewedAt ?? -1
                let existingTime = existing.lastReviewedAt ?? -1
                var chosen = incomingTime > existingTime || (incomingTime == existingTime && imported.reviews > existing.reviews) ? imported : existing
                chosen.reviews = max(existing.reviews, imported.reviews)
                chosen.saved = existing.saved || imported.saved
                merged[id] = chosen
            } else { merged[id] = imported }
        }
        // Validate the complete merge before replacing any current records.
        try saveProgress(merged)
        return merged
    }

    private static func validTimestamp(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= latestTimestamp
    }

    private func validatedProgress(_ records: [String: CardProgress]) throws -> [String: CardProgress] {
        guard records.count <= Self.maxProgressRecords else { throw StudyError.invalid("복습 기록은 10,000개까지 가져올 수 있습니다.") }
        var normalized: [String: CardProgress] = [:]
        for (id, record) in records {
            guard let uuid = UUID(uuidString: id), id.lowercased() == uuid.uuidString.lowercased(),
                  normalized[uuid.uuidString.lowercased()] == nil,
                  (0...1_000_000).contains(record.reviews), (0...6).contains(record.successes),
                  record.successes <= record.reviews else {
                throw StudyError.invalid("복습 기록의 ID·중복·횟수가 올바르지 않습니다.")
            }
            if record.reviews == 0 {
                guard record.lastReviewedAt == nil, record.nextReviewAt == nil else {
                    throw StudyError.invalid("아직 학습하지 않은 표현에 잘못된 복습 시간이 있습니다.")
                }
            } else {
                guard let last = record.lastReviewedAt, let next = record.nextReviewAt,
                      Self.validTimestamp(last), Self.validTimestamp(next), next >= last else {
                    throw StudyError.invalid("복습 시간이 올바르지 않습니다.")
                }
            }
            normalized[uuid.uuidString.lowercased()] = record
        }
        return normalized
    }

    private func readProgressFile(_ path: URL) throws -> Data {
        let size = try path.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= Self.maxProgressBytes else { throw StudyError.invalid("저장된 복습 기록의 크기가 올바르지 않습니다.") }
        return try Data(contentsOf: path)
    }

    /// JSONDecoder silently accepts duplicate object keys. Reject them before decoding,
    /// including escaped spelling and UUID case aliases, so a backup cannot hide records.
    private func rejectDuplicateJSONKeys(_ data: Data) throws {
        let bytes = Array(data)
        var index = 0
        var objects: [Set<String>] = []
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 123 { objects.append([]); index += 1 }
            else if byte == 125 { if !objects.isEmpty { objects.removeLast() }; index += 1 }
            else if byte == 34 {
                let start = index
                index += 1
                var closed = false
                while index < bytes.count {
                    if bytes[index] == 92 { index += 2 }
                    else if bytes[index] == 34 { index += 1; closed = true; break }
                    else { index += 1 }
                }
                guard closed else { throw StudyError.invalid("복습 백업의 JSON 문자열이 손상되었습니다.") }
                var next = index
                while next < bytes.count && [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
                if next < bytes.count, bytes[next] == 58, !objects.isEmpty {
                    let key = try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])).lowercased()
                    guard objects[objects.count - 1].insert(key).inserted else {
                        throw StudyError.invalid("복습 백업에 중복된 항목이 있습니다.")
                    }
                }
            } else { index += 1 }
        }
    }

    @discardableResult
    func importFile(_ url: URL) throws -> Episode {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= Self.maxBytes else { throw StudyError.invalid("64MB 이하의 학습 꾸러미를 선택하세요.") }
        return try importData(Data(contentsOf: url))
    }

    @discardableResult
    func importData(_ data: Data) throws -> Episode {
        guard data.count <= Self.maxBytes else { throw StudyError.invalid("꾸러미가 64MB를 넘습니다.") }
        var pack = try JSONDecoder().decode(StudyPack.self, from: data)
        try pack.validate()
        pack.episode.id = pack.episode.id.lowercased()
        for index in pack.episode.cards.indices { pack.episode.cards[index].id = pack.episode.cards[index].id.lowercased() }
        let transactionID = UUID().uuidString.lowercased()
        let staging = root.appendingPathComponent(".import-" + transactionID)
        let backup = root.appendingPathComponent(".backup-" + transactionID)
        let journal = root.appendingPathComponent(".transaction-" + transactionID + ".json")
        let destination = root.appendingPathComponent(pack.episode.id)
        var journalWritten = false
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { if !journalWritten { try? manager.removeItem(at: staging) } }
        for index in pack.episode.cards.indices {
            let card = pack.episode.cards[index]
            if let encoded = card.audio?.base64, let audio = Data(base64Encoded: encoded) {
                try audio.write(to: staging.appendingPathComponent(card.id + ".mp3"), options: .atomic)
                pack.episode.cards[index].audio?.base64 = nil
            }
        }
        try JSONEncoder().encode(pack).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
        let existing = manager.fileExists(atPath: destination.path)
        if existing { _ = try readStoredPack(at: destination, expectedID: pack.episode.id) }
        let transaction = ImportTransaction(transactionID: transactionID, episodeID: pack.episode.id, hadOriginal: existing)
        // Persist the recovery plan before either rename can remove the visible episode.
        try JSONEncoder().encode(transaction).write(to: journal, options: .atomic)
        journalWritten = true
        do {
            if existing { try manager.moveItem(at: destination, to: backup) }
            try manager.moveItem(at: staging, to: destination)
        } catch {
            try recoverTransaction(transaction, journal: journal)
            throw error
        }
        // If cleanup is interrupted, the next launch validates the committed destination
        // and finishes cleanup from this same journal.
        try recoverTransaction(transaction, journal: journal)
        return pack.episode
    }

    private func readStoredPack(at folder: URL, expectedID: String) throws -> StudyPack {
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw StudyError.invalid("저장된 에피소드 폴더가 올바르지 않습니다.")
        }
        let pack = try JSONDecoder().decode(StudyPack.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        try pack.validate(requireAudioData: false)
        guard pack.episode.id == expectedID else { throw StudyError.invalid("저장된 에피소드 ID가 일치하지 않습니다.") }
        return pack
    }

    private func recoverPendingImports() throws {
        let journals = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".transaction-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for journal in journals {
            let transaction = try JSONDecoder().decode(ImportTransaction.self, from: Data(contentsOf: journal))
            guard transaction.version == 1,
                  let id = UUID(uuidString: transaction.transactionID), id.uuidString.lowercased() == transaction.transactionID,
                  let episode = UUID(uuidString: transaction.episodeID), episode.uuidString.lowercased() == transaction.episodeID,
                  journal.lastPathComponent == ".transaction-" + transaction.transactionID + ".json" else {
                throw StudyError.invalid("중단된 가져오기 기록이 손상되었습니다. 원본 파일을 보존했습니다.")
            }
            try recoverTransaction(transaction, journal: journal)
        }
    }

    private func recoverTransaction(_ transaction: ImportTransaction, journal: URL) throws {
        let staging = root.appendingPathComponent(".import-" + transaction.transactionID)
        let backup = root.appendingPathComponent(".backup-" + transaction.transactionID)
        let destination = root.appendingPathComponent(transaction.episodeID)
        let hasDestination = manager.fileExists(atPath: destination.path)
        let hasBackup = manager.fileExists(atPath: backup.path)
        let hasStaging = manager.fileExists(atPath: staging.path)
        // Validate every existing artifact first. A corrupt folder must not cause the
        // recovery process to overwrite or silently discard any user data.
        if hasDestination { _ = try readStoredPack(at: destination, expectedID: transaction.episodeID) }
        if hasBackup { _ = try readStoredPack(at: backup, expectedID: transaction.episodeID) }
        if hasStaging { _ = try readStoredPack(at: staging, expectedID: transaction.episodeID) }
        if !hasDestination {
            if hasBackup { try manager.moveItem(at: backup, to: destination) }
            else if !transaction.hadOriginal && hasStaging { try manager.moveItem(at: staging, to: destination) }
            else { throw StudyError.invalid("중단된 가져오기의 원본을 찾지 못했습니다. 남은 파일을 보존했습니다.") }
        }
        if manager.fileExists(atPath: backup.path) { try manager.removeItem(at: backup) }
        if manager.fileExists(atPath: staging.path) { try manager.removeItem(at: staging) }
        try manager.removeItem(at: journal)
    }

    func audioURL(episodeID: String, cardID: String) -> URL {
        root.appendingPathComponent(episodeID).appendingPathComponent(cardID + ".mp3")
    }
}
