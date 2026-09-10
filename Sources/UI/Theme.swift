import SwiftUI

/// Shared visual language, kept in step with Minimal: neutral grays,
/// light-blue accent, vibrancy-friendly translucency, restrained corners.
enum Theme {
    static let accent = Color(red: 0.42, green: 0.67, blue: 0.98)
    static let surfaceStroke = Color.white.opacity(0.12)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let failure = Color(red: 0.92, green: 0.44, blue: 0.40)

    static let cornerRadius: CGFloat = 12
}

/// NSVisualEffectView-backed background for overlay surfaces.
struct VibrantBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    /// Rounds the blur region itself. SwiftUI clipShape can't do this: the
    /// behind-window blur is composited by the window server, which ignores
    /// SwiftUI clipping — square blur corners poke out unless the effect
    /// view is masked directly.
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.state = .active
        view.blendingMode = .behindWindow
        view.maskImage = Self.roundedMask(radius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.maskImage = Self.roundedMask(radius: cornerRadius)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage? {
        guard radius > 0 else { return nil }
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

extension View {
    /// Standard overlay card chrome: blur, hairline stroke, rounded corners.
    /// Deliberately no drop shadow — it clips at panel-window bounds and
    /// reads as a gray slab with hard edges.
    func overlayCard(cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        // Solid tint over the blur so content stays readable against busy
        // backgrounds.
        background(Color(nsColor: .windowBackgroundColor).opacity(0.45))
            .background(VibrantBackground(cornerRadius: cornerRadius))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
            )
    }
}

/// Small key-cap hint, e.g. "fn" followed by "release to insert".
struct KeyHint: View {
    let symbol: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(symbol)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
