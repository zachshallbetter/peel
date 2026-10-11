import SwiftUI
import AppKit

/// Peel visual tokens — light system chrome, orange accent (Snack Studio).
/// Intentionally restrained: no fog orbs, no ultra-thin glass stacks.
enum GoldenGate {
    static let accent = Color.orange
    static let accentDeep = Color(red: 1.0, green: 0.45, blue: 0.12)
    static let corner: CGFloat = 12
    static let cornerSmall: CGFloat = 10

    static var pageBackground: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: GoldenGate.corner, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: GoldenGate.corner, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }
    }
}

struct GlassPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(GoldenGate.accent.opacity(configuration.isPressed ? 0.85 : 1))
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GlassIconButton: View {
    let systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(Color.primary.opacity(0.06))
                }
        }
        .buttonStyle(.plain)
    }
}
