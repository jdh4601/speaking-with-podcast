import SwiftUI

enum LearningMode: String, CaseIterable { case discover = "발견", listen = "듣기", recall = "말하기" }

struct StudyFeed: View {
    @EnvironmentObject private var model: StudyModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: StudySession
    @State private var index = 0
    @State private var mode: LearningMode = .discover
    @State private var graded = Set<String>()
    @State private var finished = false

    var body: some View {
        VStack(spacing: 0) {
            if finished || session.items.isEmpty {
                Spacer()
                Image(systemName: "checkmark.circle").font(.system(size: 56)).foregroundStyle(StudyStyle.accent)
                Text("이번 학습을 마쳤어요").font(.title2.bold()).padding(.top, 20)
                Text("\(session.items.count)개 표현 중 \(graded.count)개 복습 기록")
                    .foregroundStyle(.secondary).padding(12)
                Button("닫기") { dismiss() }.buttonStyle(.borderedProminent)
                Spacer()
            } else {
                Picker("학습 방법", selection: $mode) {
                    ForEach(LearningMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal, 24).padding(.vertical, 12)
                pager
                HStack(spacing: 24) {
                    Button { move(-1) } label: { Image(systemName: "arrow.left").frame(width: 44, height: 44) }.disabled(index == 0).accessibilityLabel("이전 표현")
                    Spacer()
                    Text("\(index + 1) / \(session.items.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .accessibilityLabel("전체 \(session.items.count)개 중 \(index + 1)번째 표현")
                    Spacer()
                    Button { move(1) } label: { Image(systemName: "arrow.right").frame(width: 44, height: 44) }.disabled(index >= session.items.count - 1).accessibilityLabel("다음 표현")
                }.padding(.horizontal, 24)
                Button("학습 마치기") { model.stopAudio(); finished = true }
                    .font(.footnote).padding(.bottom, 14)
            }
        }.background(StudyStyle.paper).foregroundStyle(StudyStyle.ink)
        .navigationTitle(session.title).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        .onChange(of: index) { _, _ in model.stopAudio() }
        .onChange(of: mode) { _, _ in model.stopAudio() }
        .onDisappear { model.stopAudio() }
        .onChange(of: model.libraryRevision) { _, _ in dismiss() }
        .disabled(model.importing)
        .overlay { if model.importing { ProgressView("파일 준비 중…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .alert("확인이 필요해요", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("확인") { model.error = nil }
        } message: { Text(model.error ?? "") }
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
    @ScaledMetric(relativeTo: .largeTitle) private var expressionSize = 36
    @ScaledMetric(relativeTo: .title) private var meaningSize = 32
    private var answerVisible: Bool { mode == .discover || revealed }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("원문에서 배우기", systemImage: "waveform").font(.caption.weight(.semibold)).foregroundStyle(StudyStyle.accent)
                        Text(item.episode.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Button { model.toggleSaved(item.id) } label: {
                        Image(systemName: model.record(item.id).saved ? "bookmark.fill" : "bookmark").frame(width: 44, height: 44)
                    }.accessibilityLabel(model.record(item.id).saved ? "표현 저장 취소" : "표현 저장")
                }
                if mode == .listen && !revealed {
                    Text("어떤 말이 들리나요?").font(.largeTitle.bold())
                    Text("원음을 듣고 의미를 떠올려보세요.").foregroundStyle(.secondary)
                } else if mode == .recall && !revealed {
                    Text(item.card.meaning).font(.system(size: meaningSize, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text("영어로 소리 내어 말해보세요.").foregroundStyle(.secondary)
                } else {
                    Text(item.card.expression).font(.system(size: expressionSize, weight: .semibold, design: .serif)).tracking(-0.7).fixedSize(horizontal: false, vertical: true)
                    Text(item.card.meaning).font(.title3).foregroundStyle(.secondary)
                }
                if mode != .recall || answerVisible { audioControls }
                if !answerVisible {
                    Button("답 확인") {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { revealed = true }
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("실제 원문").font(.caption.weight(.semibold)).foregroundStyle(StudyStyle.accent)
                        Text(item.card.sourceSentence.isEmpty ? item.card.quote : item.card.sourceSentence).font(.title3).textSelection(.enabled)
                        Text(item.card.sourceSentenceTranslation.isEmpty ? "원문 전체 해석이 없는 표현입니다." : item.card.sourceSentenceTranslation)
                            .font(.subheadline).foregroundStyle(.secondary)
                        if !item.card.tip.isEmpty { Text(item.card.tip).font(.subheadline).padding(.top, 8) }
                    }
                    Button { showContext = true } label: { Label("인용·연습 예문 보기", systemImage: "text.alignleft") }.font(.subheadline)
                    Divider()
                    Text(graded ? "이번 학습에서 기록한 표현이에요." : "답을 보기 전에 떠올렸나요?").font(.caption).foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack { retryButton; recalledButton }.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 12) { retryButton; recalledButton }
                    }.controlSize(.large).disabled(graded)
                }
            }.frame(maxWidth: 560, alignment: .leading).padding(24)
        }
        .disabled(!isActive || model.importing)
        .onChange(of: mode) { _, _ in revealed = false }
        .onChange(of: isActive) { _, active in if !active { revealed = false } }
        .sheet(isPresented: $showContext) {
            NavigationStack {
                List {
                    Section("원문 인용") { Text(item.card.quote) }
                    if !item.card.example.isEmpty {
                        Section("새로 만든 연습 예문") {
                            Text(item.card.example)
                            if !item.card.exampleTranslation.isEmpty { Text(item.card.exampleTranslation).foregroundStyle(.secondary) }
                        }
                    }
                    if let url = URL(string: item.episode.sourceURL), url.scheme == "https" {
                        Section { Link("원본 에피소드 열기", destination: url) }
                    }
                }.navigationTitle("표현의 맥락").toolbar { Button("닫기") { showContext = false } }
            }
        }
    }

    private var retryButton: some View {
        Button("다시 연습") { onReview(false) }.buttonStyle(.bordered)
            .accessibilityHint("10분 뒤 다시 복습하도록 기록합니다.")
    }

    private var recalledButton: some View {
        Button("떠올렸어요") { onReview(true) }.buttonStyle(.borderedProminent)
            .accessibilityHint("성공한 복습으로 기록하고 다음 표현으로 이동합니다.")
    }

    private var playButton: some View {
        Button { model.play(item, slow: slow) } label: {
            Label(model.audioActive && model.audioCardID == item.id ? "처음부터 재생" : "원음 듣기", systemImage: "play.fill")
        }.buttonStyle(.borderedProminent)
    }

    private var repeatButton: some View {
        Button("3번 반복") { model.play(item, times: 3, slow: slow) }.buttonStyle(.bordered)
            .accessibilityLabel("원문 음성 3번 반복 듣기")
    }

    private var speedButton: some View {
        Button(slow ? "0.8×" : "1×") { slow.toggle(); model.stopAudio() }.buttonStyle(.bordered)
            .accessibilityLabel("재생 속도 변경").accessibilityValue(slow ? "0.8배속" : "1배속")
    }

    private var audioControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if item.card.audio != nil {
                ViewThatFits(in: .horizontal) {
                    HStack { playButton; repeatButton; speedButton }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 12) { playButton; repeatButton; speedButton }
                }.controlSize(.regular)
                Text(model.audioCardID == item.id ? model.audioStatus : "원음 준비됨")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("음성 상태: \(model.audioCardID == item.id ? model.audioStatus : "원음 준비됨")")
                Button("재생 멈추기") { model.stopAudio() }.font(.caption).frame(minHeight: 44)
                    .disabled(!model.audioActive || model.audioCardID != item.id)
            } else {
                Label("원문 음성 없음", systemImage: "speaker.slash").font(.subheadline)
                Text(item.card.audioUnavailableReason ?? "Mac에서 음성을 포함해 다시 내보내세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
