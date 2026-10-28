import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Podcast Study's bright, rounded learning system. Numeric values are documented
/// in DESIGN.md; this is our implementation, not Duolingo's published specification.
enum StudyStyle {
    static let paper = Color(hex: 0xFFFFFF)
    static let surface = Color(hex: 0xF7F7F7)
    static let ink = Color(hex: 0x3C3C3C)
    static let muted = Color(hex: 0x6F6F6F)
    static let line = Color(hex: 0xE5E5E5)
    static let accent = Color(hex: 0x0077B6)
    static let accentDeep = Color(hex: 0x005A8D)
    static let accentTint = Color(hex: 0xE4F4FC)
    static let blue = accent
    static let blueTint = accentTint
    static let yellow = Color(hex: 0xFFC800)
    static let orange = Color(hex: 0xFF9600)
    static let red = Color(hex: 0xFF4B4B)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}


/// Scale our rounded type with the system text setting instead of fixing point sizes.
extension View {
    func studyFont(_ size: CGFloat, _ weight: Font.Weight = .bold) -> some View {
        modifier(StudyScaledFont(size: size, weight: weight))
    }
}

private struct StudyScaledFont: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 16
    let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(StudyStyle.font(size, weight))
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

enum StudyButtonTone {
    case primary, secondary, outline, quiet
}

struct StudyButtonStyle: ButtonStyle {
    var tone: StudyButtonTone
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(tone: StudyButtonTone = .primary) { self.tone = tone }

    private var face: Color {
        if !isEnabled { return tone == .quiet ? .clear : StudyStyle.line }
        switch tone {
        case .primary: return StudyStyle.accent
        case .secondary: return StudyStyle.accent
        case .outline: return StudyStyle.paper
        case .quiet: return .clear
        }
    }

    private var edge: Color {
        guard isEnabled else { return StudyStyle.line }
        switch tone {
        case .primary: return StudyStyle.accentDeep
        case .secondary: return StudyStyle.accentDeep
        case .outline: return StudyStyle.line
        case .quiet: return .clear
        }
    }

    private var labelColor: Color {
        guard isEnabled else { return StudyStyle.muted }
        switch tone {
        case .primary, .secondary: return .white
        case .outline, .quiet: return StudyStyle.ink
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let depth: CGFloat = tone == .quiet ? 0 : 4
        let pressed = configuration.isPressed && isEnabled
        configuration.label
            .studyFont(16, .heavy)
            .multilineTextAlignment(.center)
            .foregroundStyle(labelColor)
            .padding(.horizontal, tone == .quiet ? 10 : 18)
            .padding(.vertical, 12)
            .frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(face))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tone == .outline ? edge : .clear, lineWidth: 2)
            }
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(edge).offset(y: pressed ? 0 : depth)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .offset(y: pressed ? depth : 0)
            .padding(.bottom, depth)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: pressed)
    }
}

struct StudyProgressBar: View {
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(value: Double) { self.value = value }

    private var fraction: Double { value.isFinite ? min(1, max(0, value)) : 0 }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(StudyStyle.line)
                Capsule().fill(StudyStyle.accent)
                    .frame(width: fraction > 0 ? max(16, geometry.size.width * fraction) : 0)
                    .overlay(alignment: .top) {
                        Capsule().fill(.white.opacity(0.32))
                            .frame(height: 4).padding(.horizontal, 8).padding(.top, 3)
                    }
                    .clipped()
            }
        }
        .frame(height: 16)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("학습 진행률")
        .accessibilityValue("\(Int(fraction * 100))퍼센트")
    }
}

/// Original plush companion. Motion stays local and requires no network service.
struct PodcastBuddy: View {
    // Loose PNG resources also work in the standalone Mac preview without an asset compiler.
    private static let artwork: Image = {
        let url = Bundle.main.url(forResource: "PodcastCompanion", withExtension: "png")!
        #if canImport(UIKit)
        return Image(uiImage: UIImage(contentsOfFile: url.path)!)
        #else
        return Image(nsImage: NSImage(contentsOf: url)!)
        #endif
    }()
    var size: CGFloat = 96
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var greeting = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { context in
            let time = reduceMotion || scenePhase != .active ? 0 : context.date.timeIntervalSinceReferenceDate
            let breath = sin(time * 1.8)
            let sway = sin(time * 0.9)
            ZStack {
                Ellipse().fill(StudyStyle.accentDeep.opacity(0.10))
                    .frame(width: size * 0.51, height: size * 0.065)
                    .scaleEffect(x: 1 - breath * 0.04, y: 1)
                    .offset(y: size * 0.43)
                Self.artwork
                    .resizable().scaledToFit().frame(width: size, height: size)
                    .scaleEffect(x: 1 - breath * 0.012, y: 1 + breath * 0.018, anchor: .bottom)
                    .rotationEffect(.degrees(greeting ? -9 : sway * 2.5), anchor: .bottom)
                    .offset(y: greeting ? -size * 0.07 : -size * (0.012 + breath * 0.012))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !reduceMotion, scenePhase == .active else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { greeting = true }
        }
        .task(id: greeting) {
            guard greeting else { return }
            do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { greeting = false }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { greeting = false } }
        .onChange(of: reduceMotion) { _, reduced in if reduced { greeting = false } }
        .accessibilityHidden(true)
    }
}
