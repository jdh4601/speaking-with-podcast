import SwiftUI

/// One current card, one directional decision, and no recall-grading controls.
struct StudyFeed: View {
    @EnvironmentObject private var model: StudyModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: StudySession
    @State private var index = 0
    @State private var reviewedCount = 0
    @State private var savedCount = 0
    @State private var horizontalOffset: CGFloat = 0
    @GestureState private var dragging = false
    @State private var dragAxis = DragAxis.undecided
    @State private var transitioning = false
    @State private var pendingIndex: Int?
    @State private var transitionTask: Task<Void, Never>?
    @State private var isVisible = false
    @State private var autoplayedCardID: String?

    private enum DragAxis { case undecided, horizontal, vertical }
    private var currentItem: StudyItem? { session.items.indices.contains(index) ? session.items[index] : nil }
    private var complete: Bool { currentItem == nil }
    private var playbackKey: String {
        "\(currentItem?.id ?? "complete")-\(scenePhase == .active)-\(model.importing)-\(transitioning)-\(model.error != nil)-\(isVisible)"
    }

    var body: some View {
        VStack(spacing: 0) {
            if complete {
                completionView
            } else {
                header
                deck
                swipeHint
            }
        }
        .background(StudyStyle.paper).foregroundStyle(StudyStyle.ink)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .disabled(model.importing)
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            transitionTask?.cancel()
            model.stopAudio()
        }
        .task(id: playbackKey) { await autoplayCurrentCard() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                model.stopAudio()
                transitionTask?.cancel()
                finishPendingSwipe()
                resetDrag()
            }
        }
        .onChange(of: dragging) { _, active in
            if !active && !transitioning { resetDrag() }
        }
        .onChange(of: model.importing) { _, importing in
            if importing {
                model.stopAudio()
                transitionTask?.cancel()
                finishPendingSwipe()
                resetDrag()
            }
        }
        .onChange(of: model.libraryRevision) { _, _ in close() }
        .overlay {
            if model.importing {
                ProgressView("파일 준비 중…").padding(24)
                    .background(StudyStyle.paper, in: RoundedRectangle(cornerRadius: 20))
            }
        }
        .alert("확인이 필요해요", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("확인") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Button(action: close) {
                Image(systemName: "xmark").studyFont(20, .heavy)
                    .foregroundStyle(StudyStyle.muted).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("복습 닫기")
            StudyProgressBar(value: Double(reviewedCount) / Double(max(1, session.items.count)))
            Text("\(index + 1) / \(session.items.count)")
                .studyFont(13, .semibold).foregroundStyle(StudyStyle.muted).monospacedDigit()
                .accessibilityLabel("전체 \(session.items.count)개 중 \(index + 1)번째 표현")
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
    }

    private var deck: some View {
        GeometryReader { geometry in
            let width = min(560, max(1, geometry.size.width))
            ZStack {
                RoundedRectangle(cornerRadius: 26)
                    .fill(StudyStyle.surface).padding(.horizontal, 8).offset(y: 7)
                if let item = currentItem {
                    ExpressionPage(item: item, isBusy: transitioning)
                        .id(item.id)
                        .background(StudyStyle.paper, in: RoundedRectangle(cornerRadius: 26))
                        .overlay { RoundedRectangle(cornerRadius: 26).stroke(StudyStyle.line, lineWidth: 2) }
                        .overlay(alignment: horizontalOffset >= 0 ? .topLeading : .topTrailing) { intentBadge }
                        .offset(x: horizontalOffset)
                        .rotationEffect(.degrees(reduceMotion ? 0 : Double(horizontalOffset / width) * 7))
                        .simultaneousGesture(swipeGesture(width: width))
                        .accessibilityElement(children: .contain)
                        .accessibilityHint("오른쪽으로 밀면 저장하고, 왼쪽으로 밀면 그냥 넘깁니다.")
                        .accessibilityAction(named: Text("저장하고 다음 표현")) { submit(.save, width: width) }
                        .accessibilityAction(named: Text("그냥 넘기고 다음 표현")) { submit(.skip, width: width) }
                }
            }
            .frame(width: width, height: geometry.size.height)
            .frame(maxWidth: .infinity)
        }
        .coordinateSpace(name: "review-deck")
        .padding(.horizontal, 20).padding(.bottom, 10)
        .clipped()
    }

    private var intentBadge: some View {
        Text(horizontalOffset >= 0 ? "저장" : "넘기기")
            .studyFont(24, .heavy).foregroundStyle(.white)
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(horizontalOffset >= 0 ? StudyStyle.accent : StudyStyle.muted, in: RoundedRectangle(cornerRadius: 14))
            .rotationEffect(.degrees(horizontalOffset >= 0 ? -8 : 8))
            .padding(22)
            .opacity(min(1, max(0, Double(abs(horizontalOffset) - 20) / 65)))
            .allowsHitTesting(false).accessibilityHidden(true)
    }

    private var swipeHint: some View {
        HStack(spacing: 20) {
            Label("그냥 넘기기", systemImage: "arrow.left")
                .foregroundStyle(StudyStyle.muted)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Text("저장")
                Image(systemName: "arrow.right")
            }.foregroundStyle(StudyStyle.accent)
        }.studyFont(14, .semibold)
            .padding(.horizontal, 30).padding(.top, 8).padding(.bottom, 20)
            .accessibilityElement(children: .combine)
    }

    private func swipeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .named("review-deck"))
            .updating($dragging) { _, active, _ in active = true }
            .onChanged { value in
                guard !transitioning, !model.importing, model.error == nil else { return }
                if dragAxis == .undecided {
                    let x = abs(value.translation.width), y = abs(value.translation.height)
                    if x > y * 1.2 { dragAxis = .horizontal }
                    else if y > x * 1.2 { dragAxis = .vertical }
                }
                guard dragAxis == .horizontal else { return }
                horizontalOffset = value.translation.width
            }
            .onEnded { value in
                guard !transitioning else { return }
                let action = dragAxis == .horizontal ? ReviewSwipeAction.resolve(
                    horizontal: Double(value.translation.width),
                    vertical: Double(value.translation.height),
                    projectedHorizontal: Double(value.predictedEndTranslation.width),
                    cardWidth: Double(width)
                ) : nil
                dragAxis = .undecided
                if let action { submit(action, width: width) }
                else { resetDrag() }
            }
    }

    private func submit(_ action: ReviewSwipeAction, width: CGFloat) {
        guard isVisible, !transitioning, !model.importing, model.error == nil,
              scenePhase == .active, let item = currentItem else { return }
        let save: Bool
        switch action { case .save: save = true; case .skip: save = false }
        let wasSaved = model.record(item.id).saved
        guard model.recordSwipe(item.id, save: save) else { resetDrag(); return }
        transitioning = true
        reviewedCount += 1
        if save && !wasSaved { savedCount += 1 }
        model.stopAudio()
        pendingIndex = index + 1
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.18)) {
            horizontalOffset = reduceMotion ? 0 : (save ? 1 : -1) * (width + 80)
        }
        transitionTask?.cancel()
        if reduceMotion { finishPendingSwipe(); return }
        transitionTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            guard !Task.isCancelled, isVisible else { return }
            finishPendingSwipe()
        }
    }

    private func finishPendingSwipe() {
        guard let next = pendingIndex else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            index = next
            horizontalOffset = 0
            dragAxis = .undecided
            pendingIndex = nil
            transitioning = false
        }
    }

    private func resetDrag() {
        dragAxis = .undecided
        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.85)) { horizontalOffset = 0 }
    }

    private func autoplayCurrentCard() async {
        guard isVisible, scenePhase == .active, !model.importing, !transitioning,
              model.error == nil, let item = currentItem, autoplayedCardID != item.id else { return }
        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        guard !Task.isCancelled, isVisible, currentItem?.id == item.id,
              scenePhase == .active, !model.importing, !transitioning, model.error == nil else { return }
        autoplayedCardID = item.id
        model.autoplay(item)
    }

    private func close() {
        isVisible = false
        transitionTask?.cancel()
        model.stopAudio()
        dismiss()
    }

    private var completionView: some View {
        ScrollView {
            VStack(spacing: 24) {
                PodcastBuddy(size: 120).padding(.top, 36)
                Text("오늘의 표현을 둘러봤어요")
                    .studyFont(27, .heavy).multilineTextAlignment(.center)
                Text("살펴본 표현 \(reviewedCount)개 · 새로 저장 \(savedCount)개")
                    .studyFont(17, .semibold).foregroundStyle(StudyStyle.muted)
                    .multilineTextAlignment(.center)
                Text("오른쪽으로 고른 표현은 내 표현에 모아뒀어요.")
                    .studyFont(15, .medium).foregroundStyle(StudyStyle.muted)
                    .multilineTextAlignment(.center)
                Button(action: close) { Text("닫기").frame(maxWidth: .infinity) }
                    .buttonStyle(StudyButtonStyle())
            }.padding(28).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
    }
}

/// Reading is a vertical scroll. The enclosing deck only acts on horizontal intent.
private struct ExpressionPage: View {
    @EnvironmentObject private var model: StudyModel
    @Environment(\.scenePhase) private var scenePhase
    let item: StudyItem
    let isBusy: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var expressionSize = 34

    private var audioStatus: String {
        guard model.audioCardID == item.id else { return "카드가 나오면 원음이 재생돼요" }
        return model.audioActive ? "원음 재생 중" : model.audioStatus
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 9) {
                    Image(systemName: "headphones").foregroundStyle(StudyStyle.accent)
                    Text(item.episode.title).foregroundStyle(StudyStyle.muted)
                }.studyFont(13, .medium)
                VStack(alignment: .leading, spacing: 14) {
                    Text(item.card.expression).font(StudyStyle.font(expressionSize, .heavy))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.card.meaning).studyFont(21, .semibold)
                        .foregroundStyle(StudyStyle.muted).fixedSize(horizontal: false, vertical: true)
                }
                audioLine
                sourceText
                if !item.card.tip.isEmpty {
                    Text(item.card.tip).studyFont(14, .medium).foregroundStyle(StudyStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !item.card.example.isEmpty {
                    Divider()
                    readingSection("새로 만든 연습 예문", text: item.card.example, translation: item.card.exampleTranslation)
                }
            }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
        }.scrollIndicators(.hidden)
    }

    private var audioLine: some View {
        VStack(alignment: .leading, spacing: 8) {
            if item.card.audio != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { audioIndicator; replay }
                    VStack(alignment: .leading, spacing: 4) { audioIndicator; replay }
                }
            } else {
                Label("원음 없음 · 글로 복습해요", systemImage: "speaker.slash")
                    .studyFont(13, .semibold).foregroundStyle(StudyStyle.muted)
                if let reason = item.card.audioUnavailableReason, !reason.isEmpty {
                    Text(reason).studyFont(12, .medium).foregroundStyle(StudyStyle.muted)
                }
            }
        }
    }

    private var audioIndicator: some View {
        Label(audioStatus, systemImage: model.audioActive && model.audioCardID == item.id ? "waveform" : "speaker.wave.2")
            .studyFont(12, .medium).foregroundStyle(StudyStyle.muted)
            .accessibilityLabel("음성 상태: \(audioStatus)")
    }

    private var replay: some View {
        Button { model.play(item) } label: {
            Label("다시 듣기", systemImage: "arrow.counterclockwise")
                .studyFont(14, .semibold).foregroundStyle(StudyStyle.accent)
                .frame(minHeight: 44)
        }.buttonStyle(.plain).accessibilityLabel("원음 다시 듣기")
            .disabled(isBusy || model.importing || scenePhase != .active)
    }

    private var sourceText: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            readingSection("실제 원문", text: item.card.sourceSentence.isEmpty ? item.card.quote : item.card.sourceSentence,
                           translation: item.card.sourceSentenceTranslation)
        }
    }

    private func readingSection(_ title: String, text: String, translation: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).studyFont(12, .semibold).foregroundStyle(StudyStyle.muted)
            Text(text).studyFont(18, .medium).fixedSize(horizontal: false, vertical: true)
            if !translation.isEmpty {
                Text(translation).studyFont(15, .medium).foregroundStyle(StudyStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
