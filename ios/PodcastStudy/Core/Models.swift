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

    /// Completing a swipe records exposure, never a recalled/known answer.
    /// Skipping leaves an existing bookmark intact. Later legacy review dates survive.
    mutating func recordSwipe(save: Bool, now: Date) {
        if save { saved = true }
        reviews += 1
        lastReviewedAt = now.timeIntervalSince1970
        nextReviewAt = max(nextReviewAt ?? 0, now.addingTimeInterval(86400).timeIntervalSince1970)
    }

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

/// Deliberate horizontal gestures only; vertical reading and short drags do nothing.
enum ReviewSwipeAction: Equatable {
    case save, skip

    static func resolve(horizontal: Double, vertical: Double,
                        projectedHorizontal: Double, cardWidth: Double) -> ReviewSwipeAction? {
        guard horizontal.isFinite, vertical.isFinite, projectedHorizontal.isFinite,
              cardWidth.isFinite, cardWidth > 0, abs(horizontal) >= 48,
              abs(horizontal) > abs(vertical) * 1.2 else { return nil }
        let threshold = min(120, max(80, cardWidth * 0.25))
        let alignedProjection = (horizontal > 0) == (projectedHorizontal > 0)
        let distance = alignedProjection ? max(abs(horizontal), abs(projectedHorizontal)) : abs(horizontal)
        guard distance >= threshold else { return nil }
        return horizontal > 0 ? .save : .skip
    }
}

/// A short verbatim excerpt that keeps the target expression in view.
enum ExpressionContext {
    static func matches(in text: String, expression: String) -> [Range<String.Index>] {
        let words = expression.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }
        let pattern = words.map {
            NSRegularExpression.escapedPattern(for: String($0).replacingOccurrences(of: "’", with: "'"))
                .replacingOccurrences(of: "'", with: "['’]")
        }.joined(separator: "\\s+")
        guard let regex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])" + pattern + "(?![\\p{L}\\p{N}])", options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text) }
    }

    static func excerpt(source: String, quote: String, expression: String) -> String {
        let source = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let quote = quote.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let text = !matches(in: source, expression: expression).isEmpty ? source
            : (!matches(in: quote, expression: expression).isEmpty ? quote : (source.isEmpty ? quote : source))
        let words = text.split(separator: " ")
        guard !words.isEmpty else { return "" }
        let match = matches(in: text, expression: expression).first
        let first = match.flatMap { range in words.firstIndex { $0.endIndex > range.lowerBound } } ?? 0
        let last = match.flatMap { range in words.lastIndex { $0.startIndex < range.upperBound } } ?? 0
        var start = max(0, first - 3)
        var end = min(words.count, max(last + 1, start + 15))
        // Trim surrounding context, never the expression itself. Large text can still scroll.
        while words[start..<end].joined(separator: " ").count > 96 {
            if end > last + 1 && (end - last > first - start || start == first) { end -= 1 }
            else if start < first { start += 1 }
            else { break }
        }
        return (start > 0 ? "… " : "") + words[start..<end].joined(separator: " ") + (end < words.count ? "\u{00A0}…" : "")
    }
}
