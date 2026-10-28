import SwiftUI

enum LearningMode: String, CaseIterable {
    case discover = "발견", listen = "듣기", recall = "말하기"

    var symbol: String {
        switch self {
        case .discover: return "sparkles"
        case .listen: return "waveform"
        case .recall: return "bubble.left.fill"
        }
    }
}

struct StudyFeed: View {
    @EnvironmentObject private var model: StudyModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: StudySession
    @State private var index = 0
    @State private var mode: LearningMode = .discover
    @State private var graded = Set<String>()
    @State private var finished = false

    private var completion: Double {
        session.items.isEmpty ? 0 : Double(graded.count) / Double(session.items.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            if finished || session.items.isEmpty {
                completionView
            } else {
                lessonHeader
                modeTabs
                pager
                cardNavigation
            }
        }
        .background(StudyStyle.paper).foregroundStyle(StudyStyle.ink)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .onChange(of: index) { _, _ in model.stopAudio() }
        .onChange(of: mode) { _, _ in model.stopAudio() }
        .onDisappear { model.stopAudio() }
        .onChange(of: model.libraryRevision) { _, _ in dismiss() }
        .disabled(model.importing)
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

    private var lessonHeader: some View {
        HStack(spacing: 16) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").studyFont(20, .heavy)
                    .foregroundStyle(StudyStyle.muted).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("학습 닫기")
            VStack(alignment: .leading, spacing: 6) {
                StudyProgressBar(value: completion)
                Text("복습 기록 \(graded.count) / \(session.items.count)")
                    .studyFont(11, .bold).foregroundStyle(StudyStyle.muted)
            }
            Image(systemName: "headphones").studyFont(24, .heavy)
                .foregroundStyle(StudyStyle.blue).accessibilityHidden(true)
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
    }

    private var modeTabs: some View {
        HStack(spacing: 8) {
            ForEach(LearningMode.allCases, id: \.self) { value in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { mode = value }
                } label: {
                    Label(value.rawValue, systemImage: value.symbol)
                        .studyFont(14, .bold).frame(maxWidth: .infinity).frame(minHeight: 44)
                        .foregroundStyle(mode == value ? Color.white : StudyStyle.muted)
                        .background(mode == value ? StudyStyle.accent : StudyStyle.paper, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(mode == value ? StudyStyle.accentDeep : StudyStyle.line, lineWidth: 2))
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(value.rawValue) 모드")
                    .accessibilityAddTraits(mode == value ? .isSelected : [])
            }
        }.padding(.horizontal, 24).padding(.bottom, 12)
    }

    private var pager: some View {
        TabView(selection: $index) {
            ForEach(Array(session.items.enumerated()), id: \.element.id) { offset, item in
                ExpressionPage(item: item, mode: mode, isActive: index == offset, graded: graded.contains(item.id)) { recalled in
                    guard !graded.contains(item.id), index == offset, model.review(item.id, recalled: recalled) else { return }
                    graded.insert(item.id)
                    if index < session.items.count - 1 { move(1) }
                    else { model.stopAudio(); finished = true }
                }.tag(offset).accessibilityHidden(index != offset).allowsHitTesting(index == offset)
            }
        }.tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var cardNavigation: some View {
        HStack(spacing: 12) {
            Button { move(-1) } label: {
                Image(systemName: "arrow.left").studyFont(17, .heavy).frame(width: 44, height: 44)
            }.buttonStyle(.plain).disabled(index == 0).accessibilityLabel("이전 표현")
            Text("\(index + 1) / \(session.items.count)")
                .studyFont(13, .bold).foregroundStyle(StudyStyle.muted).monospacedDigit()
                .accessibilityLabel("전체 \(session.items.count)개 중 \(index + 1)번째 표현")
            Button { move(1) } label: {
                Image(systemName: "arrow.right").studyFont(17, .heavy).frame(width: 44, height: 44)
            }.buttonStyle(.plain).disabled(index >= session.items.count - 1).accessibilityLabel("다음 표현")
            Spacer(minLength: 0)
            Button("마치기") { model.stopAudio(); finished = true }
                .studyFont(13, .bold).foregroundStyle(StudyStyle.muted)
                .frame(minWidth: 44, minHeight: 44).buttonStyle(.plain)
                .accessibilityLabel("이번 학습 마치기")
        }.padding(.horizontal, 24).padding(.vertical, 2)
            .overlay(alignment: .top) { Rectangle().fill(StudyStyle.line).frame(height: 1) }
    }

    private var completionView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)
                ZStack(alignment: .topTrailing) {
                    PodcastBuddy(size: 128)
                    Image(systemName: "star.fill").studyFont(30, .heavy)
                        .foregroundStyle(StudyStyle.yellow).rotationEffect(.degrees(14)).offset(x: 15, y: -10)
                }.accessibilityHidden(true)
                Text(graded.isEmpty ? "좋은 표현을 만났네요!" : "오늘도 한 걸음 더!")
                    .studyFont(28, .heavy).multilineTextAlignment(.center)
                Text("\(session.items.count)개 표현 중 \(graded.count)개 복습 기록")
                    .studyFont(17, .bold).foregroundStyle(StudyStyle.muted)
                    .multilineTextAlignment(.center)
                VStack(spacing: 10) {
                    Label("직접 평가한 표현만 기록했어요", systemImage: "checkmark.circle.fill")
                        .studyFont(15, .bold).foregroundStyle(StudyStyle.accentDeep)
                    Text("다시 연습할 표현은 다음 복습에서 만나요.")
                        .studyFont(14, .medium).foregroundStyle(StudyStyle.muted)
                        .multilineTextAlignment(.center)
                }.padding(20).frame(maxWidth: .infinity)
                    .background(StudyStyle.accentTint, in: RoundedRectangle(cornerRadius: 20))
                Button { dismiss() } label: {
                    Text("학습 마치기").frame(maxWidth: .infinity)
                }.buttonStyle(StudyButtonStyle())
                Spacer(minLength: 24)
            }.frame(maxWidth: 520).padding(28).frame(maxWidth: .infinity)
        }
    }

    private func move(_ delta: Int) {
        let next = max(0, min(session.items.count - 1, index + delta))
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { index = next }
    }
}

struct ExpressionPage: View {
    @EnvironmentObject private var model: StudyModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let item: StudyItem
    let mode: LearningMode
    let isActive: Bool
    let graded: Bool
    let onReview: (Bool) -> Void
    @State private var revealed = false
    @State private var showContext = false
    @State private var slow = false
    @ScaledMetric(relativeTo: .largeTitle) private var expressionSize = 30
    @ScaledMetric(relativeTo: .title) private var meaningSize = 26
    private var answerVisible: Bool { mode == .discover || revealed }
    private var playing: Bool { model.audioActive && model.audioCardID == item.id }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    sourceHeader
                    taskHeading
                    promptContent
                    if mode != .recall || answerVisible { audioControls }
                    if answerVisible { sourceDetails }
                }.frame(maxWidth: 560, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
            }
            answerFooter
        }
        .disabled(!isActive || model.importing)
        .onChange(of: mode) { _, _ in revealed = false }
        .onChange(of: isActive) { _, active in if !active { revealed = false } }
        .sheet(isPresented: $showContext) { contextSheet }
    }

    private var sourceHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "waveform").studyFont(18, .heavy)
                .foregroundStyle(StudyStyle.blue).frame(width: 40, height: 40)
                .background(StudyStyle.blueTint, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("팟캐스트 속 표현").studyFont(11, .heavy).foregroundStyle(StudyStyle.muted)
                Text(item.episode.title).studyFont(12, .medium)
                    .foregroundStyle(StudyStyle.muted).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button { model.toggleSaved(item.id) } label: {
                Image(systemName: model.record(item.id).saved ? "bookmark.fill" : "bookmark")
                    .studyFont(20, .bold).frame(width: 44, height: 44)
                    .foregroundStyle(model.record(item.id).saved ? StudyStyle.orange : StudyStyle.muted)
            }.buttonStyle(.plain).accessibilityLabel(model.record(item.id).saved ? "표현 저장 취소" : "표현 저장")
        }
    }

    private var taskHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(taskTitle).studyFont(23, .heavy).fixedSize(horizontal: false, vertical: true)
            Text(taskSubtitle).studyFont(14, .medium).foregroundStyle(StudyStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }

    private var taskTitle: String {
        if answerVisible { return mode == .discover ? "오늘의 표현을 만나보세요" : "이렇게 말할 수 있어요!" }
        if mode == .listen && item.card.audio == nil { return "이 표현은 글로 익혀봐요" }
        return mode == .listen ? "어떤 말이 들리나요?" : "영어로 말해볼까요?"
    }

    private var taskSubtitle: String {
        if answerVisible { return "원어민의 말투까지 함께 익혀보세요." }
        if mode == .listen && item.card.audio == nil { return "원음이 아직 없어요. 답을 확인하고 뜻을 익혀보세요." }
        return mode == .listen ? "자막 없이 원음을 듣고 뜻을 떠올려보세요." : "아래 뜻을 보고 소리 내어 말해보세요."
    }

    @ViewBuilder private var promptContent: some View {
        if mode == .listen && !revealed {
            VStack(spacing: 10) {
                Image(systemName: "waveform").font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(StudyStyle.blue).padding(22)
                    .background(StudyStyle.blueTint, in: RoundedRectangle(cornerRadius: 28))
                Text("듣고, 떠올리고, 확인!").studyFont(15, .bold).foregroundStyle(StudyStyle.muted)
            }.frame(maxWidth: .infinity).padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if answerVisible {
                    Text(item.card.expression).font(StudyStyle.font(expressionSize, .heavy))
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Text(item.card.meaning).studyFont(18, .semibold).foregroundStyle(StudyStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(item.card.meaning).font(StudyStyle.font(meaningSize, .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .studyFont(26, .bold).foregroundStyle(StudyStyle.blue)
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(answerVisible ? StudyStyle.accentTint.opacity(0.5) : StudyStyle.paper, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(answerVisible ? StudyStyle.accent.opacity(0.45) : StudyStyle.line, lineWidth: 2))
        }
    }

    private var audioControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if item.card.audio != nil {
                Button { model.play(item, slow: slow) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: playing ? "waveform" : "play.fill").studyFont(22, .heavy)
                        Text(playing ? "처음부터 듣기" : "원음 듣기").studyFont(17, .heavy)
                        Spacer()
                        Image(systemName: "speaker.wave.2.fill").studyFont(20, .bold)
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(StudyButtonStyle(tone: .secondary))
                audioOptions
                Text(model.audioCardID == item.id ? model.audioStatus : "이 에피소드의 실제 발화예요.")
                    .studyFont(12, .medium).foregroundStyle(StudyStyle.muted)
                    .accessibilityLabel("음성 상태: \(model.audioCardID == item.id ? model.audioStatus : "원음 준비됨")")
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "speaker.slash.fill").foregroundStyle(StudyStyle.orange)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("이 표현은 글로 연습해요").studyFont(14, .bold)
                        Text(item.card.audioUnavailableReason ?? "Mac에서 원음을 포함해 다시 가져올 수 있어요.")
                            .studyFont(12, .medium).foregroundStyle(StudyStyle.muted)
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(StudyStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var audioOptions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { repeatButton; speedButton; stopButton }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) { repeatButton; HStack(spacing: 8) { speedButton; stopButton } }
        }
    }

    private var repeatButton: some View {
        Button("3번 반복") { model.play(item, times: 3, slow: slow) }
            .studyFont(13, .bold).buttonStyle(StudyButtonStyle(tone: .outline))
            .accessibilityLabel("원문 음성 3번 반복 듣기")
    }

    private var speedButton: some View {
        Button(slow ? "0.8×" : "1×") { slow.toggle(); model.stopAudio() }
            .studyFont(13, .bold).buttonStyle(StudyButtonStyle(tone: .outline))
            .accessibilityLabel("재생 속도 변경").accessibilityValue(slow ? "0.8배속" : "1배속")
    }

    private var stopButton: some View {
        Button { model.stopAudio() } label: {
            Image(systemName: "stop.fill").studyFont(13, .bold)
        }.buttonStyle(StudyButtonStyle(tone: .outline)).disabled(!playing)
            .accessibilityLabel("재생 멈추기")
    }

    private var sourceDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !item.card.tip.isEmpty {
                Label {
                    Text(item.card.tip).studyFont(13, .medium).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lightbulb.fill").foregroundStyle(StudyStyle.orange)
                }.foregroundStyle(StudyStyle.muted)
            }
            Button { showContext = true } label: {
                HStack {
                    Text("원문과 연습 예문 보기").studyFont(14, .bold)
                    Spacer()
                    Image(systemName: "chevron.right").studyFont(13, .bold)
                }.frame(maxWidth: .infinity)
            }.buttonStyle(StudyButtonStyle(tone: .outline))
        }
    }

    private var answerFooter: some View {
        VStack(spacing: 10) {
            if graded {
                Label("이번 학습에서 기록했어요", systemImage: "checkmark.circle.fill")
                    .studyFont(14, .bold).foregroundStyle(StudyStyle.accentDeep)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
            } else if answerVisible {
                Text("답을 보기 전에 떠올렸나요?").studyFont(12, .bold).foregroundStyle(StudyStyle.muted)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { retryButton; recalledButton }
                    VStack(spacing: 10) { recalledButton; retryButton }
                }
            } else {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { revealed = true }
                } label: {
                    Text("답 확인").frame(maxWidth: .infinity)
                }.buttonStyle(StudyButtonStyle())
            }
        }.frame(maxWidth: 560).padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 18)
            .frame(maxWidth: .infinity).background(StudyStyle.paper)
            .overlay(alignment: .top) { Rectangle().fill(StudyStyle.line).frame(height: 2) }
    }

    private var retryButton: some View {
        Button { onReview(false) } label: { Text("다시 연습").frame(maxWidth: .infinity) }
            .buttonStyle(StudyButtonStyle(tone: .outline))
            .accessibilityHint("10분 뒤 다시 복습하도록 기록합니다.")
    }

    private var recalledButton: some View {
        Button { onReview(true) } label: { Text("떠올렸어요").frame(maxWidth: .infinity) }
            .buttonStyle(StudyButtonStyle())
            .accessibilityHint("성공한 복습으로 기록하고 다음 표현으로 이동합니다.")
    }

    private var contextSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    contextSection("실제 발화 문장", text: item.card.sourceSentence.isEmpty ? item.card.quote : item.card.sourceSentence,
                                   translation: item.card.sourceSentenceTranslation)
                    contextSection("원문 인용", text: item.card.quote, translation: "")
                    if !item.card.example.isEmpty {
                        contextSection("새로 만든 연습 예문", text: item.card.example, translation: item.card.exampleTranslation)
                    }
                    if let url = URL(string: item.episode.sourceURL), url.scheme == "https" {
                        Link(destination: url) {
                            Label("원본 에피소드 열기", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
                        }.buttonStyle(StudyButtonStyle(tone: .outline))
                    }
                }.padding(24).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
            }.background(StudyStyle.paper).navigationTitle("표현의 맥락")
                .toolbar { Button("닫기") { showContext = false } }
        }
    }

    private func contextSection(_ title: String, text: String, translation: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).studyFont(13, .heavy).foregroundStyle(StudyStyle.ink)
            Text(text).studyFont(18, .semibold).textSelection(.enabled)
            if !translation.isEmpty {
                Text(translation).studyFont(15, .medium).foregroundStyle(StudyStyle.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
