import SwiftUI

final class ThemeController: ObservableObject {
    static let shared = ThemeController()
    @Published private(set) var theme: AppTheme = .rose
    func apply(_ theme: AppTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
    }
}

extension AppTheme {
    var preferredColorScheme: ColorScheme? { self == .graphite ? .dark : nil }
}

/// Semantic tokens are computed from the selected theme. Rebuilding the root
/// view after a theme change updates every existing screen without duplicating UI.
enum Style {
    private static var theme: AppTheme { ThemeController.shared.theme }
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
    static var accent: Color {
        switch theme {
        case .rose: dynamic(light: UIColor(red: 0.91, green: 0.16, blue: 0.47, alpha: 1), dark: UIColor(red: 1.00, green: 0.34, blue: 0.64, alpha: 1))
        case .graphite: Color(red: 0.32, green: 0.78, blue: 1.00)
        case .indigo: dynamic(light: Color.ui(0.31, 0.28, 0.86), dark: Color.ui(0.55, 0.53, 1.00))
        }
    }
    static var accentSoft: Color {
        switch theme {
        case .rose: dynamic(light: Color.ui(1.00, 0.89, 0.93), dark: Color.ui(0.26, 0.12, 0.20))
        case .graphite: Color(red: 0.10, green: 0.22, blue: 0.28)
        case .indigo: dynamic(light: Color.ui(0.91, 0.91, 1.00), dark: Color.ui(0.15, 0.14, 0.31))
        }
    }
    static var background: Color {
        switch theme {
        case .rose: dynamic(light: Color.ui(1.00, 0.975, 0.985), dark: Color.ui(0.09, 0.06, 0.09))
        case .graphite: Color(red: 0.035, green: 0.045, blue: 0.055)
        case .indigo: dynamic(light: Color.ui(0.975, 0.975, 1.00), dark: Color.ui(0.055, 0.055, 0.12))
        }
    }
    static var card: Color {
        switch theme {
        case .rose: dynamic(light: .white, dark: Color.ui(0.16, 0.10, 0.15))
        case .graphite: Color(red: 0.075, green: 0.09, blue: 0.105)
        case .indigo: dynamic(light: .white, dark: Color.ui(0.10, 0.09, 0.20))
        }
    }
    static var ink: Color {
        switch theme {
        case .rose: dynamic(light: Color.ui(0.19, 0.08, 0.15), dark: Color.ui(0.99, 0.92, 0.96))
        case .graphite: Color(red: 0.94, green: 0.97, blue: 0.99)
        case .indigo: dynamic(light: Color.ui(0.10, 0.09, 0.25), dark: Color.ui(0.94, 0.94, 1.00))
        }
    }
    static var muted: Color {
        switch theme {
        case .rose: dynamic(light: Color.ui(0.52, 0.43, 0.49), dark: Color.ui(0.72, 0.59, 0.67))
        case .graphite: Color(red: 0.58, green: 0.64, blue: 0.68)
        case .indigo: dynamic(light: Color.ui(0.42, 0.41, 0.57), dark: Color.ui(0.67, 0.66, 0.80))
        }
    }
    static var line: Color {
        switch theme {
        case .rose: dynamic(light: Color.ui(0.96, 0.88, 0.92), dark: Color.ui(0.29, 0.18, 0.27))
        case .graphite: Color(red: 0.16, green: 0.20, blue: 0.23)
        case .indigo: dynamic(light: Color.ui(0.88, 0.87, 0.97), dark: Color.ui(0.22, 0.21, 0.38))
        }
    }
    static var hero: Color {
        switch theme { case .rose: Color(red: 0.71, green: 0.07, blue: 0.37); case .graphite: Color(red: 0.05, green: 0.35, blue: 0.48); case .indigo: Color(red: 0.22, green: 0.17, blue: 0.68) }
    }
    static var hotPink: Color { theme == .rose ? Color(red: 1.00, green: 0.28, blue: 0.56) : accent }
    static var blush: Color { theme == .graphite ? Color(red: 0.25, green: 0.52, blue: 0.65) : Color(red: 1.00, green: 0.73, blue: 0.84) }
    static var lilac: Color { theme == .graphite ? Color(red: 0.16, green: 0.38, blue: 0.52) : Color(red: 0.75, green: 0.59, blue: 1.00) }
    static var gradient: LinearGradient { LinearGradient(
        colors: gradientColors,
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    ) }
    static var gradientColors: [Color] {
        switch theme {
        case .rose: [Color(red: 1.00, green: 0.33, blue: 0.61), Color(red: 0.80, green: 0.08, blue: 0.44)]
        case .graphite: [Color(red: 0.12, green: 0.48, blue: 0.65), Color(red: 0.05, green: 0.20, blue: 0.30)]
        case .indigo: [Color(red: 0.48, green: 0.42, blue: 1.00), Color(red: 0.21, green: 0.16, blue: 0.66)]
        }
    }
}

private extension Color {
    static func ui(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

/// Soft ambient background shared by the custom flows. It keeps the interface
/// recognisably pink without painting every control in the accent colour.
struct VibeBackground: View {
    var body: some View {
        ZStack {
            Style.background
            RadialGradient(
                colors: [Style.hotPink.opacity(0.10), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 260
            )
            RadialGradient(
                colors: [Style.lilac.opacity(0.08), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 330
            )
        }
        .ignoresSafeArea()
    }
}

struct StoreFeedback: ViewModifier {
    @EnvironmentObject var store: CabinetStore
    func body(content: Content) -> some View {
        content.alert("Не получилось", isPresented: Binding(
            get: { store.error != nil },
            set: { if !$0 { store.error = nil } }
        )) {
            Button("Понятно", role: .cancel) { store.error = nil }
        } message: {
            Text(store.error ?? "")
        }
    }
}

extension View {
    func feedback() -> some View { modifier(StoreFeedback()) }
    func cabinetBackground() -> some View { scrollContentBackground(.hidden).background(Style.background) }
    func cardSurface() -> some View {
        padding(20)
            .background(Style.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Style.line, lineWidth: 1))
    }
    func vibeCard(radius: CGFloat = 24) -> some View {
        background(Style.card.opacity(0.97), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Style.line.opacity(0.9), lineWidth: 1))
            .shadow(color: Style.hero.opacity(0.055), radius: 22, y: 10)
    }
}

struct PrimaryButton: View {
    var title: String
    var icon = "plus"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                Image(systemName: icon).font(.system(size: 15, weight: .bold))
            }
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Style.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Style.accent.opacity(0.23), radius: 18, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct VibeIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 42, height: 42)
                .foregroundStyle(Style.ink)
                .background(Style.card.opacity(0.94), in: Circle())
                .overlay(Circle().strokeBorder(Style.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct Eyebrow: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.8)
            .foregroundStyle(Style.muted)
            .lineLimit(1)
    }
}

struct ClientAvatar: View {
    var client: Client?
    var size: CGFloat = 46
    var body: some View {
        Group {
            if let bytes = client?.photos?.first, let image = UIImage(data: bytes) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text((client?.name ?? "К").split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined())
                    .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                    .foregroundStyle(Style.accent)
            }
        }
        .frame(width: size, height: size)
        .background(Style.accentSoft)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Style.accent.opacity(0.08), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

struct SectionHeading: View {
    var title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .tracking(-0.6)
            Spacer(minLength: 8)
            if let detail { Text(detail).font(.caption.weight(.medium)).foregroundStyle(Style.muted) }
        }
    }
}
