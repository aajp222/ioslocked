import SwiftUI

// MARK: - Avatar

struct Avatar: View {
    let initials: String
    var active: Bool = false
    var size: CGFloat = 36

    var body: some View {
        Text(initials)
            .font(.display(size * 0.39))
            .foregroundStyle(active ? Ink.gold : Ink.paper(0.5))
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(Color(hex: 0x171310).opacity(0.6))
                    .overlay {
                        Circle().strokeBorder(active ? Ink.gold(0.85) : Ink.paper(0.18), lineWidth: 1)
                    }
            }
            .overlay {
                if active {
                    Circle()
                        .strokeBorder(Ink.gold(0.12), lineWidth: 3)
                        .padding(-3)
                }
            }
    }
}

// MARK: - Live dot

struct LiveDot: View {
    var color: Color = Ink.gold
    var size: CGFloat = 6
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(on ? 0.9 : 0.45)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

// MARK: - Progress ring

struct Ring<Content: View>: View {
    var progress: Double
    var size: CGFloat
    var lineWidth: CGFloat = 5
    var track: Double = 0.12
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Ink.paper(track), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(Ink.gold, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(lineWidth / 2)
                .animation(.linear(duration: 0.9), value: progress)
            content()
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Buttons

struct GoldButton: View {
    let title: String
    var icon: String? = nil
    var radius: CGFloat = 19
    var vertical: CGFloat = 16
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 14, weight: .medium))
                }
                Text(title).font(.display(16.5, .semibold))
            }
            .foregroundStyle(Ink.goldType)
            .frame(maxWidth: .infinity)
            .padding(.vertical, vertical)
            .goldGlass(radius, fill: 0.26, border: 0.52)
        }
        .pressable()
    }
}

struct GlassButton: View {
    let title: String
    var icon: String? = nil
    var radius: CGFloat = 19
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 14, weight: .medium))
                }
                Text(title).font(.display(15.5, .semibold))
            }
            .foregroundStyle(Ink.paper)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .glass(radius, fill: 0.12, border: 0.16)
        }
        .pressable()
    }
}

struct QuietButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(.ui(13))
                .foregroundStyle(Ink.paper(0.4))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
    }
}

/// The rounded pill used for goals, durations and app names.
struct Chip: View {
    let label: String
    var selected: Bool = false
    var struck: Bool = false
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon, selected {
                    Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                }
                Text(label)
                    .font(.ui(12.5))
                    .strikethrough(struck, color: Ink.paper(0.35))
            }
            .foregroundStyle(selected ? Ink.goldType : Ink.paper(struck ? 0.4 : 0.72))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(selected ? Ink.gold(0.16) : Color.white.opacity(0.05))
                    .overlay {
                        Capsule().strokeBorder(selected ? Ink.gold(0.42) : Ink.paper(0.14), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

/// A wide tappable row with a radio dot — pod picking and stakes.
struct ChoiceRow: View {
    let title: String
    let note: String
    var selected: Bool
    var leading: AnyView? = nil
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            action()
        } label: {
            HStack(alignment: .center, spacing: 13) {
                if let leading {
                    leading
                } else {
                    ZStack {
                        Circle()
                            .strokeBorder(selected ? Ink.gold : Ink.paper(0.25), lineWidth: 1)
                            .frame(width: 18, height: 18)
                        if selected {
                            Circle().fill(Ink.gold).frame(width: 8, height: 8)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.display(16, .semibold))
                        .foregroundStyle(Ink.paper)
                    Text(note)
                        .font(.ui(12.5))
                        .foregroundStyle(Ink.paper(0.5))
                        .lineSpacing(1.5)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if leading != nil {
                    ZStack {
                        if selected {
                            Circle().fill(Ink.gold(0.9)).frame(width: 24, height: 24)
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(hex: 0x171310))
                        } else {
                            Circle().strokeBorder(Ink.paper(0.25), lineWidth: 1).frame(width: 24, height: 24)
                        }
                    }
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .glass(17, fill: 0.1, border: 0.13)
        }
        .pressable()
    }
}

// MARK: - Section card

struct Panel<Content: View>: View {
    var radius: CGFloat = 26
    var padding: CGFloat = 20
    var fill: Double = 0.1
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(radius, fill: fill, border: 0.13)
    }
}

// MARK: - Tab bar

struct TabBar: View {
    @Binding var route: Route
    var badge: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            item(.today, "lock", "Today")
            item(.pod, "person.2", "Pod", badge: badge)
            item(.standings, "trophy", "Standings")
        }
        .padding(6)
        .glass(26, fill: 0.14, border: 0.16, shadow: 0.4)
        .padding(.horizontal, 20)
    }

    private func item(_ target: Route, _ icon: String, _ label: String, badge: Int = 0) -> some View {
        let active = route == target
        return Button {
            Haptics.select()
            route = target
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .regular))
                        .frame(height: 18)
                    if badge > 0 {
                        Circle()
                            .fill(Ink.gold)
                            .frame(width: 7, height: 7)
                            .offset(x: 6, y: -2)
                    }
                }
                Text(label).font(.ui(10))
            }
            .foregroundStyle(active ? Ink.paper : Ink.paper(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.white.opacity(0.14))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheet chrome

/// The bottom sheet the prototype uses for every decision moment.
struct BottomSheet<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Ink.paper(0.25))
                .frame(width: 38, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 18)
            content()
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 34, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 34, style: .continuous
            )
            .fill(.ultraThinMaterial)
            .overlay {
                LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 34, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 34, style: .continuous
            ))
            .overlay(alignment: .top) {
                Rectangle().fill(.white.opacity(0.2)).frame(height: 1)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .transition(.move(edge: .bottom))
    }
}

/// Dim + blur behind a sheet or takeover. The material has to be the *fill* of a
/// shape for SwiftUI to sample what's behind it — a tinted `Color` alone doesn't
/// blur anything.
struct Scrim: View {
    var opacity: Double = 0.6
    var onTap: (() -> Void)? = nil

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Color(hex: 0x080706, alpha: opacity))
            .ignoresSafeArea()
            .onTapGesture { onTap?() }
            .transition(.opacity)
    }
}

// MARK: - Big numeral

/// The oversized serif figure with small unit suffixes ("2h 40m", "18min").
struct BigFigure: View {
    let seconds: Int
    var size: CGFloat = 76
    var unitSize: CGFloat { size * 0.45 }

    var body: some View {
        let h = max(0, seconds) / 3600
        let m = (max(0, seconds) % 3600) / 60
        return HStack(alignment: .lastTextBaseline, spacing: 0) {
            if h > 0 {
                Text("\(h)").font(.display(size))
                Text("h ").font(.display(unitSize)).foregroundStyle(Ink.paper(0.45))
            }
            Text("\(m)").font(.display(size))
            Text("m").font(.display(unitSize)).foregroundStyle(Ink.paper(0.45))
        }
        .foregroundStyle(Ink.paper)
        .monospacedDigit()
    }
}
