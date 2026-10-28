import SwiftUI

struct StudySession: Identifiable {
    let id = UUID()
    var title: String
    var items: [StudyItem]
}

private enum StudyTab: String, CaseIterable {
    case today = "학습", episodes = "팟캐스트", saved = "내 표현"
    var icon: String {
        switch self { case .today: return "house.fill"; case .episodes: return "headphones"; case .saved: return "bookmark.fill" }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: StudyModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: StudyTab = .today
    @State private var showImporter = false
    @State private var showBackupExporter = false
    @State private var backupDocument: ProgressBackupDocument?
    @State private var session: StudySession?
    @State private var queue: [StudyItem] = []
    @State private var search = ""

    private var allItems: [StudyItem] {
        model.episodes.flatMap { episode in episode.cards.map { StudyItem(episode: episode, card: $0) } }
    }
    private var savedItems: [StudyItem] { allItems.filter { model.record($0.id).saved } }
    private var reviewedToday: Int {
        allItems.filter { item in
            guard let last = model.record(item.id).lastReviewedAt else { return false }
            return Calendar.current.isDateInToday(Date(timeIntervalSince1970: last))
        }.count
    }
    private var dailyTarget: Int { min(10, allItems.count) }
    private var goalMet: Bool { dailyTarget > 0 && reviewedToday >= dailyTarget }

    var body: some View {
        VStack(spacing: 0) {
            appHeader
            Group {
                switch selectedTab {
                case .today: today
                case .episodes: episodes
                case .saved: saved
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomNavigation
        }
        .background(StudyStyle.paper).foregroundStyle(StudyStyle.ink)
        .disabled(model.importing)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.podcastStudy, .podcastProgress, .json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { Task { await model.importPack(url) } }
            case .failure(let error): if !isCancellation(error) { model.error = error.localizedDescription }
            }
        }
        .fileExporter(isPresented: $showBackupExporter, document: backupDocument, contentType: .podcastProgress, defaultFilename: "PodcastStudy-Progress") { result in
            switch result {
            case .success: model.notice = "복습 기록을 백업했어요. 원음은 학습 꾸러미로 따로 보관하세요."
            case .failure(let error): if !isCancellation(error) { model.error = "백업을 저장하지 못했습니다: \(error.localizedDescription)" }
            }
            backupDocument = nil
        }
        .modifier(StudySessionPresenter(session: $session, model: model, onDismiss: refreshQueue))
        .alert("잠깐 확인해주세요", isPresented: Binding(get: { model.error != nil && session == nil }, set: { if !$0 { model.error = nil } })) {
            Button("확인") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .overlay {
            if model.importing {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("학습 파일을 준비하고 있어요").studyFont(17)
                    }.padding(28).background(StudyStyle.paper, in: RoundedRectangle(cornerRadius: 24))
                }.accessibilityAddTraits(.isModal)
            }
        }
        .onAppear(perform: refreshQueue)
        .onChange(of: model.libraryRevision) { _, _ in refreshQueue() }
        .onChange(of: scenePhase) { _, phase in if phase == .active && session == nil { refreshQueue() } }
    }

    private var appHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform").font(.system(size: 24, weight: .heavy)).foregroundStyle(StudyStyle.accentDeep)
                .accessibilityHidden(true)
            Text("podcast study").studyFont(25, .heavy).tracking(-1)
                .foregroundStyle(StudyStyle.accentDeep)
            Spacer(minLength: 8)
            fileMenu
        }.padding(.horizontal, 24).padding(.vertical, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(StudyStyle.line).frame(height: 2) }
    }

    private var fileMenu: some View {
        Menu {
            Button { showImporter = true } label: { Label("학습 꾸러미 가져오기", systemImage: "square.and.arrow.down") }
            Button(action: prepareBackup) { Label("복습 기록 백업 저장", systemImage: "square.and.arrow.up") }
                .disabled(model.progress.isEmpty)
            Button { showImporter = true } label: { Label("복습 기록 백업 복원", systemImage: "arrow.counterclockwise") }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 21, weight: .bold))
                .foregroundStyle(StudyStyle.muted).frame(width: 44, height: 44)
                .background(StudyStyle.surface, in: RoundedRectangle(cornerRadius: 14))
        }
            .accessibilityLabel("학습 파일과 백업 관리")
            .disabled(model.importing || model.library == nil)
    }

    private var bottomNavigation: some View {
        HStack(spacing: 10) {
            ForEach(StudyTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.icon).font(.system(size: 25, weight: .bold))
                        Text(tab.rawValue).studyFont(12).foregroundStyle(selectedTab == tab ? Color.white : StudyStyle.muted)
                    }.foregroundStyle(selectedTab == tab ? Color.white : StudyStyle.muted)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(selectedTab == tab ? StudyStyle.accent : .clear, in: RoundedRectangle(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).stroke(selectedTab == tab ? StudyStyle.accentDeep : .clear, lineWidth: 2) }
                }.buttonStyle(.plain).accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 12)
            .background(StudyStyle.paper)
            .overlay(alignment: .top) { Rectangle().fill(StudyStyle.line).frame(height: 2) }
    }

    private var today: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if model.episodes.isEmpty { emptyHome }
                else {
                    todayStats
                    todayLesson
                    dailyGoal
                }
                if let notice = model.notice { noticeView(notice) }
            }.frame(maxWidth: 560, alignment: .leading).padding(24)
                .frame(maxWidth: .infinity)
        }.scrollIndicators(.hidden)
    }

    private var emptyHome: some View {
        VStack(spacing: 24) {
            PodcastBuddy(size: 144).padding(.top, 24).accessibilityHidden(true)
            Text("좋아하는 팟캐스트가\n나만의 영어 수업으로")
                .studyFont(29, .heavy).multilineTextAlignment(.center)
            Text("Mac에서 고른 표현과 원음을 가져와요.\n원음을 듣고, 마음에 드는 표현을 저장하세요.")
                .studyFont(17, .medium).foregroundStyle(StudyStyle.muted)
                .multilineTextAlignment(.center).lineSpacing(5)
            Button { showImporter = true } label: {
                Label("첫 에피소드 가져오기", systemImage: "plus").frame(maxWidth: .infinity)
            }.buttonStyle(StudyButtonStyle()).disabled(model.library == nil)
            Label("한 번 가져오면 오프라인에서도", systemImage: "checkmark.circle.fill")
                .studyFont(14, .semibold).foregroundStyle(StudyStyle.muted)
        }.frame(maxWidth: .infinity).padding(.bottom, 24)
    }

    private var todayStats: some View {
        HStack {
            stat(value: reviewedToday, label: "오늘 복습", icon: "bolt.fill", color: StudyStyle.orange)
            Spacer()
            stat(value: savedItems.count, label: "저장한 표현", icon: "bookmark.fill", color: StudyStyle.blue)
            Spacer()
            stat(value: model.episodes.count, label: "에피소드", icon: "headphones", color: StudyStyle.accentDeep)
        }
    }

    private func stat(value: Int, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(color)
                Text("\(value)").foregroundStyle(StudyStyle.ink)
            }.studyFont(23, .heavy)
            Text(label).studyFont(12, .semibold).foregroundStyle(StudyStyle.muted)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(label) \(value)개")
    }

    private var todayLesson: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("오늘의 연습").studyFont(13, .heavy).foregroundStyle(StudyStyle.ink)
                    Text(goalMet ? "멋져요!\n목표를 달성했어요" : "오늘도\n한 문장부터!")
                        .studyFont(29, .heavy).fixedSize(horizontal: false, vertical: true)
                    Text(queue.isEmpty ? "지금 복습할 표현을 모두 마쳤어요." : "표현 \(queue.count)개 · 스와이프 복습")
                        .studyFont(15, .semibold).foregroundStyle(StudyStyle.muted)
                }
                Spacer(minLength: 0)
                PodcastBuddy(size: 104).accessibilityHidden(true)
            }
            Button {
                refreshQueue()
                guard !queue.isEmpty else { return }
                session = StudySession(title: "오늘의 연습", items: queue)
            } label: {
                HStack {
                    Spacer()
                    Text(queue.isEmpty ? "지금은 모두 마쳤어요" : goalMet ? "조금 더 연습하기" : "연습 시작")
                    Image(systemName: queue.isEmpty ? "checkmark" : "arrow.right")
                    Spacer()
                }
            }.buttonStyle(StudyButtonStyle()).disabled(queue.isEmpty)
        }.padding(22)
            .background(StudyStyle.accentTint.opacity(0.55), in: RoundedRectangle(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).stroke(StudyStyle.accent.opacity(0.35), lineWidth: 2) }
    }

    private var dailyGoal: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("하루 한 걸음").studyFont(20, .heavy)
                Spacer()
                Text("\(min(reviewedToday, dailyTarget)) / \(dailyTarget)개")
                    .studyFont(15).foregroundStyle(StudyStyle.ink)
            }
            StudyProgressBar(value: Double(reviewedToday) / Double(max(1, dailyTarget)))
            Text(goalMet ? "오늘 연습한 표현을 일상에서 써보세요." : "오른쪽은 저장, 왼쪽은 그냥 넘기기.")
                .studyFont(14, .medium).foregroundStyle(StudyStyle.muted)
        }
    }

    private var episodes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeading("내 팟캐스트", subtitle: "좋아하는 이야기로 영어를 익혀요")
                Button { showImporter = true } label: {
                    Label("에피소드 가져오기", systemImage: "plus").frame(maxWidth: .infinity)
                }.buttonStyle(StudyButtonStyle(tone: .secondary)).disabled(model.library == nil)
                if model.episodes.isEmpty {
                    emptyState(icon: "headphones", title: "아직 첫 에피소드를 기다려요", detail: "Mac에서 만든 .podstudy 파일을 가져오세요.")
                }
                ForEach(model.episodes) { episode in episodeRow(episode) }
                backupHint
                if let notice = model.notice { noticeView(notice) }
            }.frame(maxWidth: 560, alignment: .leading).padding(24).frame(maxWidth: .infinity)
        }.scrollIndicators(.hidden)
    }

    private func episodeRow(_ episode: Episode) -> some View {
        let practiced = episode.cards.filter { model.record($0.id).reviews > 0 }.count
        return Button {
            session = StudySession(title: episode.title, items: episode.cards.map { StudyItem(episode: episode, card: $0) })
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "waveform").font(.system(size: 28, weight: .bold)).foregroundStyle(StudyStyle.blue)
                        .frame(width: 60, height: 64).background(StudyStyle.blueTint, in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(episode.title).studyFont(19).multilineTextAlignment(.leading)
                        Text("표현 \(episode.cards.count)개 · 원음 \(episode.cards.filter { $0.audio != nil }.count)개")
                            .studyFont(13, .semibold).foregroundStyle(StudyStyle.muted)
                    }
                }
                StudyProgressBar(value: Double(practiced) / Double(max(1, episode.cards.count)))
                HStack {
                    Text("연습한 표현 \(practiced)/\(episode.cards.count)").studyFont(13).foregroundStyle(StudyStyle.muted)
                    Spacer()
                    Label("연습하기", systemImage: "arrow.right").studyFont(14).foregroundStyle(StudyStyle.ink)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(StudyStyle.paper, in: RoundedRectangle(cornerRadius: 22))
                .overlay { RoundedRectangle(cornerRadius: 22).stroke(StudyStyle.line, lineWidth: 2) }
                .padding(.bottom, 3).background(StudyStyle.line, in: RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(.plain).foregroundStyle(StudyStyle.ink)
    }

    private var saved: some View {
        let visible = savedItems.filter { search.isEmpty || $0.card.expression.localizedCaseInsensitiveContains(search) || $0.card.meaning.localizedCaseInsensitiveContains(search) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sectionHeading("내 표현", subtitle: "다시 쓰고 싶은 영어가 모이는 곳")
                if savedItems.isEmpty {
                    emptyState(icon: "bookmark.fill", title: "마음에 드는 표현을 모아봐요", detail: "학습 중 북마크를 누르면 여기에 저장돼요.")
                    Button { selectedTab = .today } label: { Text("표현 만나러 가기").frame(maxWidth: .infinity) }.buttonStyle(StudyButtonStyle())
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(StudyStyle.muted)
                        TextField("표현이나 뜻 검색", text: $search).studyFont(16, .medium).textFieldStyle(.plain)
                    }.padding(16).background(StudyStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                    Button { session = StudySession(title: "내 표현 연습", items: visible) } label: {
                        Text("\(visible.count)개 표현 연습하기").frame(maxWidth: .infinity)
                    }.buttonStyle(StudyButtonStyle()).disabled(visible.isEmpty)
                    if visible.isEmpty { Text("찾는 표현이 없어요. 다른 말로 검색해보세요.").studyFont(16, .medium).foregroundStyle(StudyStyle.muted) }
                    ForEach(visible) { item in savedRow(item) }
                }
            }.frame(maxWidth: 560, alignment: .leading).padding(24).frame(maxWidth: .infinity)
        }.scrollIndicators(.hidden)
    }

    private func savedRow(_ item: StudyItem) -> some View {
        Button { session = StudySession(title: "내 표현 연습", items: [item]) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(item.card.expression).studyFont(23)
                    Spacer()
                    Image(systemName: "bookmark.fill").foregroundStyle(StudyStyle.blue)
                }
                Text(item.card.meaning).studyFont(16, .medium).foregroundStyle(StudyStyle.muted)
                Text(item.episode.title).studyFont(12, .semibold).foregroundStyle(StudyStyle.muted).lineLimit(2)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(StudyStyle.paper, in: RoundedRectangle(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(StudyStyle.line, lineWidth: 2) }
        }.buttonStyle(.plain).foregroundStyle(StudyStyle.ink)
            .contextMenu {
                Button("저장 해제", systemImage: "bookmark.slash") { model.toggleSaved(item.id) }
            }
            .accessibilityAction(named: "저장 해제") { model.toggleSaved(item.id) }
    }

    private var backupHint: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("학습 기록도 소중하니까", systemImage: "externaldrive").studyFont(16)
            Text("상단 메뉴에서 복습 기록을 백업할 수 있어요. 원음은 학습 꾸러미도 함께 보관해주세요.")
                .studyFont(14, .medium).foregroundStyle(StudyStyle.muted).lineSpacing(3)
        }.padding(18).background(StudyStyle.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private func sectionHeading(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).studyFont(29, .heavy)
            Text(subtitle).studyFont(16, .medium).foregroundStyle(StudyStyle.muted)
        }
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 44, weight: .bold)).foregroundStyle(StudyStyle.blue)
                .padding(24).background(StudyStyle.blueTint, in: RoundedRectangle(cornerRadius: 28))
            Text(title).studyFont(21).multilineTextAlignment(.center)
            Text(detail).studyFont(15, .medium).foregroundStyle(StudyStyle.muted).multilineTextAlignment(.center)
        }.padding(.vertical, 28).frame(maxWidth: .infinity)
    }

    private func noticeView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(StudyStyle.accentDeep)
            Text(text).studyFont(13, .medium).foregroundStyle(StudyStyle.muted).textSelection(.enabled)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(StudyStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
    }

    private func refreshQueue() { queue = StudyQueue.today(episodes: model.episodes, progress: model.progress) }
    private func isCancellation(_ error: Error) -> Bool {
        let value = error as NSError
        return value.domain == NSCocoaErrorDomain && value.code == NSUserCancelledError
    }
    private func prepareBackup() {
        Task {
            if let data = await model.progressBackup() {
                backupDocument = ProgressBackupDocument(data: data)
                showBackupExporter = true
            }
        }
    }
}

/// Lessons use the whole iPhone screen; the desktop preview keeps a normal sheet.
private struct StudySessionPresenter: ViewModifier {
    @Binding var session: StudySession?
    let model: StudyModel
    let onDismiss: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(item: $session, onDismiss: onDismiss) { value in
            NavigationStack { StudyFeed(session: value) }.environmentObject(model)
        }
        #else
        content.sheet(item: $session, onDismiss: onDismiss) { value in
            NavigationStack { StudyFeed(session: value) }.environmentObject(model)
        }
        #endif
    }
}
