import SwiftUI

// The palette, `Ink` and `Fmt` now live in Shared/Palette.swift — the Live
// Activity and the shield screen need the same tokens, so they're compiled into
// every target. This file keeps what only the app uses: type, backgrounds, glass.

// MARK: - Type
//
// The prototype sets Cormorant Garamond over Lora. Shipping those means adding
// the .ttf files to the bundle (see README). Until then we use New York — the
// system serif — for headings and figures, and SF for small interface labels.

extension Font {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Kicker

/// The 10px letterspaced uppercase label used all over the prototype.
struct Kicker: View {
    let text: String
    var color: Color = Ink.paper(0.45)

    var body: some View {
        Text(text.uppercased())
            .font(.ui(10, .medium))
            .tracking(1.8)
            .foregroundStyle(color)
    }
}

// MARK: - Background

struct LockedBackground: View {
    /// The locked screen sits on a deeper, tighter ground than the rest of the app.
    var deep: Bool = false

    var body: some View {
        GeometryReader { geo in
            let s = geo.size
            let d = max(s.width, s.height)
            ZStack {
                Color(hex: deep ? 0x0D0B0A : 0x110F0E)
                if deep {
                    glow(0x4A3116, UnitPoint(x: 0.5, y: 0.02), d * 0.78, s)
                    glow(0x241A11, UnitPoint(x: 0.5, y: 1.0), d * 0.62, s)
                } else {
                    glow(0x3D2A15, UnitPoint(x: 0.18, y: 0.04), d * 0.72, s)
                    glow(0x262C38, UnitPoint(x: 0.92, y: 0.26), d * 0.55, s)
                    glow(0x2C1F13, UnitPoint(x: 0.5, y: 1.1), d * 0.7, s)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func glow(_ hex: UInt32, _ center: UnitPoint, _ radius: CGFloat, _ size: CGSize) -> some View {
        RadialGradient(
            gradient: Gradient(colors: [Color(hex: hex), Color(hex: hex, alpha: 0)]),
            center: center,
            startRadius: 0,
            endRadius: radius
        )
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Glass

/// The frosted panel the whole prototype is built from: a translucent material,
/// a top-lit white gradient, a hairline border and an inner highlight.
struct GlassPanel: ViewModifier {
    var radius: CGFloat = 26
    var fill: Double = 0.11
    var border: Double = 0.14
    var shadow: Double = 0

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        LinearGradient(
                            colors: [.white.opacity(fill), .white.opacity(fill * 0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [.white.opacity(0.28), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 1.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(.white.opacity(border), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(shadow), radius: shadow > 0 ? 22 : 0, y: shadow > 0 ? 14 : 0)
            }
    }
}

/// A gold-tinted variant of the same panel, for primary actions and warnings.
struct GoldPanel: ViewModifier {
    var radius: CGFloat = 19
    var fill: Double = 0.24
    var border: Double = 0.5

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        LinearGradient(
                            colors: [Ink.gold.opacity(fill), Ink.gold.opacity(fill * 0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Ink.gold.opacity(border), lineWidth: 1)
                    }
            }
    }
}

extension View {
    func glass(_ radius: CGFloat = 26, fill: Double = 0.11, border: Double = 0.14, shadow: Double = 0) -> some View {
        modifier(GlassPanel(radius: radius, fill: fill, border: border, shadow: shadow))
    }

    func goldGlass(_ radius: CGFloat = 19, fill: Double = 0.24, border: Double = 0.5) -> some View {
        modifier(GoldPanel(radius: radius, fill: fill, border: border))
    }

    /// Presses feel like glass: a small scale plus a brightness lift.
    func pressable() -> some View {
        buttonStyle(GlassPressStyle())
    }
}

struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
