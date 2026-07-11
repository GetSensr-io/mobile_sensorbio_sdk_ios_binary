import SwiftUI

enum NoomTheme {
    static let red = Color(hex: 0xFB513B)
    static let warmSurface = Color(hex: 0xF6F4EE)
    static let ink = Color(hex: 0x1D3A44)
    static let logoBlack = Color(hex: 0x191717)
    static let card = Color(hex: 0xFFFDF8)
    static let softLine = Color(hex: 0xDED8CE)
    static let muted = Color(hex: 0x5C6668)
    static let mint = Color(hex: 0xDDEDE3)
    static let rose = Color(hex: 0xFFE1DA)
    static let gold = Color(hex: 0xF2D69A)
    static let metricGreen = Color(hex: 0x4F9B7C)
    static let metricBlue = Color(hex: 0x5B8EAD)
    static let metricPurple = Color(hex: 0x7768AE)
    static let metricAmber = Color(hex: 0xD99035)

    static let horizontalPadding: CGFloat = 20
    static let cardRadius: CGFloat = 28
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

extension Text {
    func noomSerifTitle(size: CGFloat = 34) -> some View {
        self.font(.system(size: size, weight: .regular, design: .serif))
            .tracking(-1.5)
            .foregroundStyle(NoomTheme.logoBlack)
    }

    func noomBody() -> some View {
        self.font(.system(size: 15, weight: .regular, design: .default))
            .lineSpacing(3)
            .foregroundStyle(NoomTheme.muted)
    }

    func noomLabel() -> some View {
        self.font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(NoomTheme.muted)
    }
}

struct NoomBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    NoomTheme.warmSurface.ignoresSafeArea()
                    RadialGradient(
                        colors: [NoomTheme.red.opacity(0.16), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 280
                    )
                    .ignoresSafeArea()
                }
            )
            .scrollContentBackground(.hidden)
    }
}

extension View {
    func noomBackground() -> some View { modifier(NoomBackground()) }

    func noomDetailBackButton() -> some View {
        navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NoomDetailBackButton()
                }
            }
    }
}

struct NoomDetailBackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(NoomTheme.logoBlack)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        .accessibilityHint("Returns to the previous screen")
    }
}

struct NoomPlusLockup: View {
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 2 : 3) {
            Image("NoomLogoBrandfetch")
                .resizable()
                .scaledToFit()
                .frame(width: compact ? 78 : 112, height: compact ? 18 : 25)
            Text("+")
                .font(.system(size: compact ? 23 : 31, weight: .bold, design: .rounded))
                .foregroundStyle(NoomTheme.logoBlack)
                .offset(y: compact ? -1 : -2)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Noom plus")
    }
}

struct NoomLogoPlate: View {
    var compact: Bool = false

    var body: some View {
        NoomPlusLockup(compact: compact)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 8 : 10)
            .background(Color.white, in: RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous)
                    .stroke(NoomTheme.logoBlack.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: NoomTheme.ink.opacity(0.07), radius: 12, x: 0, y: 6)
    }
}

struct NoomBareLogo: View {
    var compact: Bool = false

    var body: some View {
        NoomPlusLockup(compact: compact)
    }
}

struct NoomPill: View {
    let title: String
    var color: Color = NoomTheme.ink
    var foreground: Color = .white

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color, in: Capsule())
    }
}

struct NoomCard<Content: View>: View {
    var fill: Color = NoomTheme.card
    var padding: CGFloat = 18
    var content: Content

    init(fill: Color = NoomTheme.card, padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: NoomTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: NoomTheme.cardRadius, style: .continuous)
                    .stroke(NoomTheme.ink.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: NoomTheme.ink.opacity(0.06), radius: 20, x: 0, y: 10)
    }
}

struct NoomPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isEnabled ? NoomTheme.red : NoomTheme.softLine, in: Capsule())
            .shadow(color: NoomTheme.red.opacity(configuration.isPressed || !isEnabled ? 0.08 : 0.22), radius: 16, x: 0, y: 10)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct NoomLoadingExperience: View {
    let title: String
    let detail: String
    var systemImage: String = "sparkles"
    var accent: Color = NoomTheme.red
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    var body: some View {
        NoomCard(fill: Color.white.opacity(0.88), padding: compact ? 16 : 20) {
            VStack(alignment: .leading, spacing: compact ? 14 : 18) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle().fill(accent.opacity(0.16))
                        Image(systemName: systemImage)
                            .font(.system(size: compact ? 20 : 25, weight: .semibold))
                            .foregroundStyle(accent)
                            .scaleEffect(isBreathing && !reduceMotion ? 1.08 : 0.94)
                    }
                    .frame(width: compact ? 48 : 58, height: compact ? 48 : 58)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.system(size: compact ? 17 : 20, weight: .bold, design: .rounded))
                            .foregroundStyle(NoomTheme.logoBlack)
                        Text(detail)
                            .noomBody()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                NoomLoadingSkeleton(accent: accent, compact: compact, isBreathing: isBreathing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityValue("Loading")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}

private struct NoomLoadingSkeleton: View {
    let accent: Color
    let compact: Bool
    let isBreathing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(isBreathing ? 0.20 : 0.10))
                .frame(height: compact ? 12 : 15)
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(NoomTheme.softLine.opacity(isBreathing ? 0.62 : 0.36))
                    .frame(height: compact ? 42 : 58)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(isBreathing ? 0.15 : 0.08))
                    .frame(height: compact ? 42 : 58)
            }
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(NoomTheme.softLine.opacity(isBreathing ? 0.50 : 0.28))
                .frame(width: compact ? 160 : 220, height: 11)
        }
        .animation(.easeInOut(duration: 1.05), value: isBreathing)
    }
}

struct NoomEmptyStateCard: View {
    var title: String
    var message: String
    var systemImage: String = "sparkles"

    var body: some View {
        NoomCard(fill: NoomTheme.card) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(NoomTheme.red)
                    .frame(width: 36, height: 36)
                    .background(NoomTheme.rose, in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NoomTheme.logoBlack)
                    Text(message)
                        .noomBody()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct NoomDashboardMetricTile: View {
    let label: String
    let value: String
    let unit: String?
    let caption: String
    let systemImage: String
    var accent: Color = NoomTheme.red
    var minHeight: CGFloat = 148
    var prominent: Bool = false

    init(
        label: String,
        value: String,
        unit: String? = nil,
        caption: String,
        systemImage: String = "chart.xyaxis.line",
        accent: Color = NoomTheme.red,
        minHeight: CGFloat = 148,
        prominent: Bool = false
    ) {
        self.label = label
        self.value = value
        self.unit = unit
        self.caption = caption
        self.systemImage = systemImage
        self.accent = accent
        self.minHeight = minHeight
        self.prominent = prominent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(label)
                    .font(.system(size: prominent ? 15 : 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(NoomTheme.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                    .frame(maxWidth: .infinity, minHeight: prominent ? 28 : 34, alignment: .topLeading)
                Image(systemName: systemImage)
                    .font(.system(size: prominent ? 17 : 15, weight: .semibold))
                    .foregroundStyle(NoomTheme.logoBlack)
                    .frame(width: prominent ? 38 : 34, height: prominent ? 38 : 34)
                    .background(accent.opacity(0.56), in: Circle())
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: prominent ? 42 : 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .tracking(-0.8)
                    .foregroundStyle(NoomTheme.logoBlack)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: prominent ? 16 : 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(NoomTheme.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 7) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                Text(caption)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(NoomTheme.ink.opacity(0.78))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NoomTheme.muted.opacity(0.72))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.94), accent.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(NoomTheme.ink.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: NoomTheme.ink.opacity(0.055), radius: 12, x: 0, y: 7)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct NoomMetricTile: View {
    let label: String
    let value: String
    let caption: String
    var minHeight: CGFloat = 112

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).noomLabel()
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .default))
                .tracking(-1)
                .foregroundStyle(NoomTheme.logoBlack)
            Text(caption).noomLabel()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(NoomTheme.ink.opacity(0.08), lineWidth: 1)
        }
    }
}

struct NoomSignalRow: View {
    let label: String
    let value: String
    var progress: Double
    var tint: Color = NoomTheme.ink

    var body: some View {
        GridRow {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .default))
                .foregroundStyle(NoomTheme.logoBlack)
            ProgressView(value: min(max(progress, 0), 1))
                .tint(tint)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(NoomTheme.muted)
        }
    }
}

struct NoomScreen<Content: View>: View {
    var spacing: CGFloat
    var bottomPadding: CGFloat
    var content: Content

    init(spacing: CGFloat = 14, bottomPadding: CGFloat = 96, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.bottomPadding = bottomPadding
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .padding(.horizontal, NoomTheme.horizontalPadding)
            .padding(.top, 18)
            .padding(.bottom, bottomPadding)
        }
        .safeAreaPadding(.bottom, 56)
        .noomBackground()
    }
}

struct NoomTopBar<Trailing: View>: View {
    let label: String
    var trailing: Trailing

    init(label: String, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label).noomLabel()
                NoomLogoPlate(compact: true)
            }
            Spacer()
            trailing
        }
    }
}

struct NoomBandIllustration: View {
    var body: some View {
        ZStack {
            Circle().stroke(NoomTheme.ink.opacity(0.14), lineWidth: 1).frame(width: 108, height: 108)
            Circle().stroke(NoomTheme.ink.opacity(0.12), lineWidth: 1).frame(width: 168, height: 168)
            Circle().stroke(NoomTheme.ink.opacity(0.10), lineWidth: 1).frame(width: 228, height: 228)
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(NoomTheme.ink)
                .frame(width: 86, height: 120)
                .shadow(color: NoomTheme.ink.opacity(0.25), radius: 22, x: 0, y: 16)
                .overlay(alignment: .top) {
                    Circle()
                        .fill(NoomTheme.red)
                        .frame(width: 20, height: 20)
                        .padding(.top, 22)
                        .shadow(color: NoomTheme.red.opacity(0.35), radius: 10)
                }
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .background(
            LinearGradient(colors: [NoomTheme.ink.opacity(0.06), NoomTheme.red.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 34, style: .continuous)
        )
    }
}
