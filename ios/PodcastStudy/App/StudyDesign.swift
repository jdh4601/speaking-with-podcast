import SwiftUI

/// Podcast Study's bright, rounded learning system. Numeric values are documented
/// in DESIGN.md; this is our implementation, not Duolingo's published specification.
enum StudyStyle {
    static let paper = Color(hex: 0xFFFFFF)
    static let surface = Color(hex: 0xF7F7F7)
    static let ink = Color(hex: 0x3C3C3C)
    static let muted = Color(hex: 0x6F6F6F)
    static let line = Color(hex: 0xE5E5E5)
    static let accent = Color(hex: 0x58CC02)
    static let accentDeep = Color(hex: 0x58A700)
    static let greenTint = Color(hex: 0xD7FFB8)
    static let blue = Color(hex: 0x1CB0F6)
    static let blueTint = Color(hex: 0xDDF4FF)
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
        case .secondary: return StudyStyle.blueTint
        case .outline: return StudyStyle.paper
        case .quiet: return .clear
        }
    }

    private var edge: Color {
        guard isEnabled else { return StudyStyle.line }
        switch tone {
        case .primary: return StudyStyle.accentDeep
        case .secondary: return StudyStyle.blue
        case .outline: return StudyStyle.line
        case .quiet: return .clear
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let depth: CGFloat = tone == .quiet ? 0 : 4
        let pressed = configuration.isPressed && isEnabled
        configuration.label
            .studyFont(16, .heavy)
            .multilineTextAlignment(.center)
            .foregroundStyle(isEnabled ? StudyStyle.ink : StudyStyle.muted)
            .padding(.horizontal, tone == .quiet ? 10 : 18)
            .padding(.vertical, 12)
            .frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(face))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tone == .outline || tone == .secondary ? edge : .clear, lineWidth: 2)
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

/// Original headphone companion: an audio player wearing a listening headset.
/// Deliberately uses a rounded screen, waveform and headphones rather than an owl.
struct PodcastBuddy: View {
    var size: CGFloat

    init(size: CGFloat = 96) { self.size = size }

    var body: some View {
        ZStack {
            Ellipse().fill(StudyStyle.line.opacity(0.65))
                .frame(width: size * 0.70, height: size * 0.10).offset(y: size * 0.44)
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(StudyStyle.accentDeep)
                .frame(width: size * 0.66, height: size * 0.67).offset(y: size * 0.07)
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(StudyStyle.accent)
                .frame(width: size * 0.66, height: size * 0.67)
            HeadphoneArch()
                .stroke(StudyStyle.ink, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                .frame(width: size * 0.84, height: size * 0.64).offset(y: -size * 0.075)
            HStack(spacing: size * 0.63) {
                RoundedRectangle(cornerRadius: size * 0.07).fill(StudyStyle.ink)
                RoundedRectangle(cornerRadius: size * 0.07).fill(StudyStyle.ink)
            }.frame(width: size * 0.87, height: size * 0.28).offset(y: size * 0.02)
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .fill(StudyStyle.paper)
                .frame(width: size * 0.44, height: size * 0.37).offset(y: -size * 0.035)
            HStack(spacing: size * 0.12) {
                Capsule().fill(StudyStyle.ink).frame(width: size * 0.045, height: size * 0.08)
                Capsule().fill(StudyStyle.ink).frame(width: size * 0.045, height: size * 0.08)
            }.offset(y: -size * 0.09)
            Smile()
                .stroke(StudyStyle.ink, style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                .frame(width: size * 0.13, height: size * 0.055).offset(y: size * 0.015)
            HStack(alignment: .center, spacing: size * 0.025) {
                ForEach(Array([0.06, 0.11, 0.075, 0.14, 0.06].enumerated()), id: \.offset) { _, height in
                    Capsule().fill(StudyStyle.ink.opacity(0.65))
                        .frame(width: size * 0.025, height: size * height)
                }
            }.offset(y: size * 0.255)
            Circle().fill(StudyStyle.yellow).frame(width: size * 0.11, height: size * 0.11)
                .overlay(Circle().strokeBorder(StudyStyle.paper, lineWidth: size * 0.025))
                .offset(x: size * 0.34, y: -size * 0.29)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct HeadphoneArch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                      control1: CGPoint(x: rect.minX, y: rect.minY - rect.height * 0.2),
                      control2: CGPoint(x: rect.maxX, y: rect.minY - rect.height * 0.2))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

private struct Smile: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                         control: CGPoint(x: rect.midX, y: rect.maxY * 1.7))
        return path
    }
}
