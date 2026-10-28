import SwiftUI

struct StudySession: Identifiable {
    let id = UUID()
    var title: String
    var items: [StudyItem]
}

struct ContentView: View {
    @EnvironmentObject private var model: StudyModel
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize = 38
    @State private var showImporter = false
    @State private var showBackupExporter = false
    @State private var backupDocument: ProgressBackupDocument?
    @State private var session: StudySession?
    @State private var queue: [StudyItem] = []

    var body: some View {
        TabView {
            NavigationStack { today }
                .tabItem { Label("오늘", systemImage: "play.circle") }
            NavigationStack { episodes }
                .tabItem { Label("에피소드", systemImage: "waveform") }
            NavigationStack { saved }
                .tabItem { Label("내 표현", systemImage: "bookmark") }
        }
        .disabled(model.importing)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.podcastStudy, .podcastProgress, .json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { Task { await model.importPack(url) } }
            case .failure(let error): if !isCancellation(error) { model.error = error.localizedDescription }
            }
        }
        .fileExporter(isPresented: $showBackupExporter, document: backupDocument, contentType: .podcastProgress, defaultFilename: "PodcastStudy-Progress") { result in
            switch result {
            case .success: model.notice = "복습 기록 백업을 저장했어요. 에피소드와 원음은 포함되지 않습니다."
            case .failure(let error): if !isCancellation(error) { model.error = "백업을 저장하지 못했습니다: \(error.localizedDescription)" }
            }
            backupDocument = nil
        }
        .sheet(item: $session, onDismiss: refreshQueue) { value in
            NavigationStack { StudyFeed(session: value) }.environmentObject(model)
        }
        .alert("확인이 필요해요", isPresented: Binding(get: { model.error != nil && session == nil }, set: { if !$0 { model.error = nil } })) {
            Button("확인") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .overlay {
            if model.importing {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView("파일 준비 중…").padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                }.accessibilityAddTraits(.isModal)
            }
        }
        .onAppear(perform: refreshQueue)
        .onChange(of: model.libraryRevision) { _, _ in refreshQueue() }
        .onChange(of: scenePhase) { _, phase in if phase == .active && session == nil { refreshQueue() } }
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

    private var fileMenu: some View {
        Menu {
            Button { showImporter = true } label: { Label("꾸러미·백업 가져오기", systemImage: "square.and.arrow.down") }
            Button(action: prepareBackup) { Label("복습 기록 백업 저장", systemImage: "square.and.arrow.up") }
                .disabled(model.progress.isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
        }.accessibilityLabel("학습 파일과 백업 관리")
            .disabled(model.importing || model.library == nil)
    }

    private var today: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack { Image(systemName: "waveform"); Text("PODCAST STUDY").tracking(3) }
                    .font(.caption.weight(.semibold)).foregroundStyle(StudyStyle.accent)
                Text("듣던 영어를,\n내가 쓰는 영어로.")
                    .font(.system(size: headingSize, weight: .bold, design: .serif)).tracking(-1.5)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(StudyStyle.accent).frame(width: 48, height: 4).accessibilityHidden(true)
                if model.episodes.isEmpty {
                    Text("Mac에서 준비한 에피소드를 가져오세요.")
                        .font(.title3.weight(.medium))
                    Text("원문 음성과 표현을 아이폰에 저장해, 어디서든 복습할 수 있어요.")
                        .foregroundStyle(.secondary)
                    importButton
                } else {
                    Text(queue.isEmpty ? "지금 복습할 표현을 모두 마쳤어요." : "오늘의 표현 \(queue.count)개")
                        .font(.title2.weight(.semibold))
                    Text("좌우로 넘겨 듣고, 뜻을 보고 영어로 말해보세요.")
                        .foregroundStyle(.secondary)
                    if !queue.isEmpty {
                        Button { session = StudySession(title: "오늘의 학습", items: queue) } label: {
                            HStack { Text("학습 시작"); Spacer(); Image(systemName: "arrow.right") }.frame(maxWidth: .infinity).padding(.vertical, 10)
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                    }
                    Button("복습 목록 새로고침", action: refreshQueue).font(.subheadline).frame(minHeight: 44)
                    Divider()
                    Label("\(model.episodes.count)개 에피소드 · \(model.episodes.reduce(0) { $0 + $1.cards.count })개 표현", systemImage: "tray")
                        .foregroundStyle(.secondary).font(.subheadline)
                }
                if let notice = model.notice {
                    Text(notice).font(.footnote).foregroundStyle(StudyStyle.accent)
                        .accessibilityLabel("파일 처리 결과: \(notice)")
                }
            }.frame(maxWidth: 560, alignment: .leading).padding(28)
        }
        .background(StudyStyle.paper).foregroundStyle(StudyStyle.ink)
        .navigationTitle("오늘").toolbar { fileMenu }
    }

    private var importButton: some View {
        Button { showImporter = true } label: {
            Label("꾸러미·백업 가져오기", systemImage: "square.and.arrow.down").padding(.vertical, 8)
        }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.importing || model.library == nil)
    }

    private var episodes: some View {
        List {
            Section { importButton.listRowBackground(Color.clear) }
            if model.episodes.isEmpty {
                Section { Text("가져온 에피소드가 여기에 쌓여요.").foregroundStyle(.secondary) }
            }
            ForEach(model.episodes) { episode in
                Button {
                    session = StudySession(title: episode.title, items: episode.cards.map { StudyItem(episode: episode, card: $0) })
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(episode.title).font(.headline).foregroundStyle(StudyStyle.ink)
                        Text("표현 \(episode.cards.count)개 · 원음 \(episode.cards.filter { $0.audio != nil }.count)개")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 10)
                }
            }
            Section {
                Button(action: prepareBackup) { Label("복습 기록 백업 저장", systemImage: "square.and.arrow.up") }
                    .disabled(model.progress.isEmpty || model.library == nil)
            } header: {
                Text("기록 백업")
            } footer: {
                Text("북마크와 복습 일정만 저장합니다. 에피소드·원음은 학습 꾸러미를 따로 보관하세요. 백업을 가져오면 기존 최신 복습 기록을 유지하고 저장한 표현을 합칩니다.")
            }
        }.scrollContentBackground(.hidden).background(StudyStyle.paper).navigationTitle("에피소드").toolbar { fileMenu }
    }

    private var saved: some View {
        let items = model.episodes.flatMap { episode in episode.cards.filter { model.record($0.id).saved }.map { StudyItem(episode: episode, card: $0) } }
        return List {
            if !items.isEmpty {
                Button("저장한 표현 모두 연습") { session = StudySession(title: "내 표현", items: items) }
            } else {
                Text("다시 쓰고 싶은 표현을 저장해보세요.").foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                Button { session = StudySession(title: "내 표현", items: [item]) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.card.expression).font(.headline).foregroundStyle(StudyStyle.ink)
                        Text(item.card.meaning).foregroundStyle(.secondary)
                        Text(item.episode.title).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
            }
        }.scrollContentBackground(.hidden).background(StudyStyle.paper).navigationTitle("내 표현").toolbar { fileMenu }
    }
}
