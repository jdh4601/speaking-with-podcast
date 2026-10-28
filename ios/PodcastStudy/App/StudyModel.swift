import SwiftUI
import AVFoundation

private final class AudioCompletionDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: @MainActor (Bool) -> Void

    init(onFinish: @escaping @MainActor (Bool) -> Void) { self.onFinish = onFinish }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [onFinish] in onFinish(flag) }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [onFinish] in onFinish(false) }
    }
}

@MainActor
final class StudyModel: ObservableObject {
    @Published private(set) var episodes: [Episode] = []
    @Published private(set) var progress: [String: CardProgress] = [:]
    @Published private(set) var libraryRevision = 0
    @Published private(set) var importing = false
    @Published private(set) var audioCardID: String?
    @Published private(set) var audioStatus = "재생 대기"
    @Published private(set) var audioActive = false
    @Published var error: String?
    @Published var notice: String?
    private(set) var library: PackLibrary?
    private var player: AVAudioPlayer?
    private var playbackDelegate: AudioCompletionDelegate?
    private var excerptTask: Task<Void, Never>?
    private var playbackToken = UUID()
    private var observerTokens: [NSObjectProtocol] = []

    init() {
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("PodcastStudy", isDirectory: true)
            let storage = try PackLibrary(root: root)
            let episodes = try storage.loadEpisodes()
            let progress = try storage.loadProgress()
            self.library = storage
            self.episodes = episodes
            self.progress = progress
        } catch { self.error = "저장된 학습 기록을 열지 못했습니다: \(error.localizedDescription)" }
        observeAudioSession()
    }

    deinit {
        for token in observerTokens { NotificationCenter.default.removeObserver(token) }
        excerptTask?.cancel()
    }

    /// File imports and progress changes are mutually exclusive on the main actor.
    /// File reading, decoding and disk writes run off the main thread.
    func importPack(_ url: URL) async {
        guard let library, !importing else { return }
        importing = true
        stopAudio()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() }; importing = false }
        do {
            let root = library.root
            let summary = try await Task.detached {
                guard url.isFileURL else { throw StudyError.invalid("파일 앱에서 학습 꾸러미나 복습 기록 백업을 선택하세요.") }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= PackLibrary.maxBytes else { throw StudyError.invalid("64MB 이하의 파일을 선택하세요.") }
                let data = try Data(contentsOf: url)
                struct Header: Decodable { let format: String }
                let header = try JSONDecoder().decode(Header.self, from: data)
                let storage = try PackLibrary(root: root)
                switch header.format {
                case "podcast-study-progress":
                    let records = try storage.importProgressBackup(data)
                    return "백업을 합쳤어요. 현재 복습 기록 \(records.count)개 · 에피소드와 원음은 학습 꾸러미에서 따로 가져오세요."
                case "podcast-study-pack":
                    let existing = try storage.loadEpisodes().map(\.id)
                    let episode = try storage.importData(data)
                    let audioCount = episode.cards.filter { $0.audio != nil }.count
                    return "‘\(episode.title)’ \(existing.contains(episode.id) ? "업데이트" : "가져오기") 완료 · 표현 \(episode.cards.count)개 · 원음 \(audioCount)개"
                default:
                    throw StudyError.invalid("학습 꾸러미 또는 복습 기록 백업 파일이 아닙니다.")
                }
            }.value
            episodes = try library.loadEpisodes()
            progress = try library.loadProgress()
            notice = summary
            libraryRevision += 1
        } catch { self.error = "파일을 가져오지 못했습니다: \(error.localizedDescription)" }
    }

    func progressBackup() async -> Data? {
        guard let library, !importing else { return nil }
        importing = true
        stopAudio()
        defer { importing = false }
        do {
            let root = library.root
            return try await Task.detached {
                try PackLibrary(root: root).exportProgressBackup()
            }.value
        } catch {
            self.error = "복습 기록 백업을 준비하지 못했습니다: \(error.localizedDescription)"
            return nil
        }
    }

    func record(_ id: String) -> CardProgress { progress[id] ?? CardProgress() }

    func toggleSaved(_ id: String) {
        guard !importing else { return }
        var next = progress
        var record = record(id)
        record.saved.toggle()
        next[id] = record
        persist(next)
    }

    /// Save preference and neutral review progress commit in the same disk write.
    @discardableResult
    func recordSwipe(_ id: String, save: Bool) -> Bool {
        guard !importing else { return false }
        var next = progress
        var record = record(id)
        record.recordSwipe(save: save, now: Date())
        next[id] = record
        return persist(next)
    }

    @discardableResult
    func review(_ id: String, recalled: Bool) -> Bool {
        guard !importing else { return false }
        var next = progress
        var record = record(id)
        record.review(recalled: recalled, now: Date())
        next[id] = record
        return persist(next)
    }

    @discardableResult
    private func persist(_ value: [String: CardProgress]) -> Bool {
        guard let library else { return false }
        do { try library.saveProgress(value); progress = value; return true }
        catch { self.error = "학습 기록을 저장하지 못했습니다: \(error.localizedDescription)"; return false }
    }

    func stopAudio(message: String = "재생을 멈췄어요.") {
        playbackToken = UUID()
        excerptTask?.cancel(); excerptTask = nil
        player?.delegate = nil; player?.stop(); player = nil
        playbackDelegate = nil
        let wasActive = audioActive
        audioActive = false
        if wasActive { audioStatus = message }
        #if os(iOS)
        if wasActive { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        #endif
    }

    /// Automatic playback has inline failures so missing clips never interrupt swiping.
    func autoplay(_ item: StudyItem) {
        guard !importing else { return }
        guard item.card.audio != nil else {
            stopAudio()
            audioCardID = item.id
            audioStatus = "원음 없음"
            return
        }
        play(item, presentErrors: false)
    }

    func play(_ item: StudyItem, presentErrors: Bool = true) {
        guard !importing else { return }
        stopAudio()
        audioCardID = item.id
        guard item.card.audio != nil, let library else {
            audioStatus = "원문 음성 없음"
            error = item.card.audioUnavailableReason ?? "이 표현에는 원문 음성이 없습니다."
            return
        }
        guard let range = item.card.excerptAudioRange else {
            audioStatus = "짧은 구간 음성 준비 필요"
            if presentErrors { error = "표시된 구절의 단어별 음성 시간이 없습니다. Mac에서 학습 꾸러미를 다시 내보내 가져오세요." }
            return
        }
        let token = UUID()
        playbackToken = token
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let audio = try AVAudioPlayer(contentsOf: library.audioURL(episodeID: item.episode.id, cardID: item.id))
            guard range.start < audio.duration, range.end <= audio.duration + 0.1 else {
                throw StudyError.invalid("짧은 구절의 음성 시간이 파일과 일치하지 않습니다.")
            }
            let end = min(range.end, audio.duration)
            audio.currentTime = range.start
            let delegate = AudioCompletionDelegate { [weak self] success in
                guard let self, self.playbackToken == token else { return }
                guard success else { self.playbackFailed(presentError: presentErrors); return }
                self.stopAudio(message: "재생 완료")
            }
            playbackDelegate = delegate
            audio.delegate = delegate
            audio.prepareToPlay()
            player = audio
            guard audio.play() else { throw StudyError.invalid("음성을 재생하지 못했습니다.") }
            audioActive = true
            audioStatus = "원음 재생 중"
            excerptTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.playbackToken == token, let player = self.player else { return }
                    if player.currentTime >= end {
                        self.stopAudio(message: "재생 완료")
                        return
                    }
                    do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                }
            }
        } catch { playbackFailed(error.localizedDescription, presentError: presentErrors) }
    }

    private func playbackFailed(_ detail: String? = nil, presentError: Bool = true) {
        // Set active so failure also releases an audio session activated before play().
        audioActive = true
        stopAudio(message: "재생 실패")
        if presentError {
            error = "원문 음성을 재생하지 못했습니다." + (detail.map { " " + $0 } ?? " Mac에서 음성을 다시 준비해 가져오세요.")
        }
    }

    private func observeAudioSession() {
        #if os(iOS)
        let center = NotificationCenter.default
        observerTokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            guard began else { return }
            Task { @MainActor [weak self] in self?.stopAudio(message: "다른 오디오가 시작되어 재생을 멈췄어요.") }
        })
        observerTokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let disconnected = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            guard disconnected else { return }
            Task { @MainActor [weak self] in self?.stopAudio(message: "이어폰 연결이 끊겨 재생을 멈췄어요.") }
        })
        observerTokens.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stopAudio(message: "오디오 연결이 초기화됐어요. 다시 재생해주세요.") }
        })
        #endif
    }
}
