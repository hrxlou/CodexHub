import AppKit
import SwiftUI

enum HubPanel {
    case usage
    case costDetails
    case settings
}

enum HubImages {
    static let appIcon = image(named: "CodexHubIconLight", fallbackSymbol: "chart.bar.fill")
    static let appIconLight = image(named: "CodexHubIconLight", fallbackSymbol: "chart.bar.fill")
    static let appIconDark = image(named: "CodexHubIconDark", fallbackSymbol: "chart.bar.fill")
    static let menuIcon = image(named: "CodexHubMenuIcon", fallbackSymbol: "chart.bar.fill")

    static func appIcon(for colorScheme: ColorScheme) -> NSImage {
        colorScheme == .dark ? appIconDark : appIconLight
    }

    private static func image(named name: String, fallbackSymbol: String) -> NSImage {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: nil) ?? NSImage()
    }
}

struct HubButtonStyle: ButtonStyle {
    enum Tone {
        case neutral
        case primary
        case danger
    }

    var tone: Tone = .neutral
    var compact = false
    var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 12, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 6 : 8)
            .background(background(configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return .primary
        case .primary: return .white
        case .danger: return .red
        }
    }

    private var stroke: Color {
        switch tone {
        case .neutral: return Color.primary.opacity(0.12)
        case .primary: return Color.green.opacity(0.22)
        case .danger: return Color.red.opacity(0.20)
        }
    }

    private func background(_ pressed: Bool) -> Color {
        switch tone {
        case .neutral:
            return Color.primary.opacity(pressed ? 0.14 : (hovering ? 0.10 : 0.07))
        case .primary:
            return Color.green.opacity(pressed ? 0.80 : (hovering ? 0.92 : 1))
        case .danger:
            return Color.red.opacity(pressed ? 0.16 : (hovering ? 0.12 : 0.08))
        }
    }
}

struct HubActionButton: View {
    let title: String
    let systemImage: String
    var tone: HubButtonStyle.Tone = .neutral
    var compact = true
    var iconOnly = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            if iconOnly {
                Label(title, systemImage: systemImage)
                    .labelStyle(.iconOnly)
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .buttonStyle(HubButtonStyle(tone: tone, compact: compact, hovering: hovering))
        .onHover { hovering = $0 }
        .help(title)
    }
}

struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            guard !isRefreshing else { return }
            action()
        } label: {
            HStack(spacing: 7) {
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.52)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
                Text(L.refresh)
            }
            .frame(width: AppLanguage.current == .korean ? 94 : 82)
        }
        .buttonStyle(HubButtonStyle(compact: true, hovering: hovering))
        .onHover { hovering = $0 }
        .disabled(isRefreshing)
        .help(isRefreshing ? L.refreshing : L.refresh)
    }
}

struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 14
    var tint: Color = .clear
    var stroke: Color = Color.primary.opacity(0.10)
    var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.thinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(stroke, lineWidth: hovering ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(hovering ? 0.13 : 0.09), radius: hovering ? 9 : 6, x: 0, y: 3)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 14, tint: Color = .clear, stroke: Color = Color.primary.opacity(0.10), hovering: Bool = false) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, tint: tint, stroke: stroke, hovering: hovering))
    }
}
