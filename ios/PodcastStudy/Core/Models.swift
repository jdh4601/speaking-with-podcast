import Foundation

public enum StudyError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

struct StudyPack: Codable {
    var format: String
    var version: Int
    var exportedAt: Double
    var episode: Episode

    func validate(requireAudioData: Bool = true) throws {
        guard format == "podcast-study-pack", version == 1 else {
            throw StudyError.invalid("지원하지 않는 학습 꾸러미 버전입니다.")
        }
        guard exportedAt.isFinite, episode.createdAt.isFinite,
              UUID(uuidString: episode.id) != nil, !episode.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...100).contains(episode.cards.count) else {
            throw StudyError.invalid("에피소드 정보가 올바르지 않습니다.")
        }
        if !episode.sourceURL.isEmpty {
            guard let url = URL(string: episode.sourceURL), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil else {
                throw StudyError.invalid("원본 링크가 올바르지 않습니다.")
            }
        }
        var ids = Set<String>()
        for card in episode.cards {
            guard UUID(uuidString: card.id) != nil, ids.insert(card.id.lowercased()).inserted,
                  !card.expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !card.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !card.quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw StudyError.invalid("표현이 누락되었거나 중복된 꾸러미입니다.")
            }
            if let audio = card.audio {
                guard audio.kind == "original-podcast-sentence", audio.duration.isFinite,
                      audio.duration > 0, audio.duration <= 151, audio.start.isFinite, audio.start >= 0,
                      !card.sourceSentence.isEmpty else {
                    throw StudyError.invalid("원문 음성 정보가 올바르지 않습니다.")
                }
                if requireAudioData {
                    guard let encoded = audio.base64, let data = Data(base64Encoded: encoded),
                          !data.isEmpty, data.count <= 8 * 1024 * 1024 else {
                        throw StudyError.invalid("원문 음성 파일이 손상되었거나 너무 큽니다.")
                    }
                }
            }
        }
    }
}

struct Episode: Codable, Identifiable {
    var id: String
    var title: String
    var sourceURL: String
    var createdAt: Double
    var cards: [StudyCard]
}

struct StudyCard: Codable, Identifiable {
    var id: String
    var expression: String
    var meaning: String
    var quote: String
    var sourceSentence: String
    var sourceSentenceTranslation: String
    var example: String
    var exampleTranslation: String
    var tip: String
    var audio: OriginalAudio?
    var audioUnavailableReason: String?
}

struct OriginalAudio: Codable {
    var base64: String?
    var duration: Double
    var start: Double
    var kind: String
}

struct CardProgress: Codable {
    var saved = false
    var successes = 0
    var reviews = 0
    var lastReviewedAt: Double?
    var nextReviewAt: Double?

    mutating func review(recalled: Bool, now: Date) {
        reviews += 1
        successes = recalled ? min(successes + 1, 6) : 0
        let days = [0, 1, 3, 7, 14, 30, 60]
        nextReviewAt = now.addingTimeInterval(recalled ? Double(days[successes]) * 86400 : 600).timeIntervalSince1970
        lastReviewedAt = now.timeIntervalSince1970
    }
}

struct StudyItem: Identifiable {
    var episode: Episode
    var card: StudyCard
    var id: String { card.id }
}

enum StudyQueue {
    static func today(episodes: [Episode], progress: [String: CardProgress], now: Date = Date()) -> [StudyItem] {
        let all = episodes.flatMap { episode in episode.cards.map { StudyItem(episode: episode, card: $0) } }
        let due = all.filter {
            let record = progress[$0.id] ?? CardProgress()
            return record.reviews > 0 && (record.nextReviewAt ?? 0) <= now.timeIntervalSince1970
        }.sorted {
            let a = progress[$0.id]?.nextReviewAt ?? 0, b = progress[$1.id]?.nextReviewAt ?? 0
            return a == b ? $0.id < $1.id : a < b
        }
        let fresh = all.filter { (progress[$0.id]?.reviews ?? 0) == 0 }
        let dueCount = min(due.count, max(7, 10 - fresh.count))
        return Array(due.prefix(dueCount)) + Array(fresh.prefix(10 - dueCount))
    }
}

/// Progress-only backup: audio and episode content stay in their original study packs.
struct ProgressBackup: Codable {
    var format = "podcast-study-progress"
    var version = 1
    var exportedAt: Double
    var progress: [String: CardProgress]
}

/// Names are derived from transactionID rather than supplied paths.
struct ImportTransaction: Codable {
    var version = 1
    var transactionID: String
    var episodeID: String
    var hadOriginal: Bool
}
