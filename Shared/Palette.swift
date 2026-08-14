import SwiftUI

// Shared by the app, the Live Activity, the shield screen and the monitor —
// so the lock screen card and the block screen are the same object as the app.

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum Hex {
    static let paper: UInt32 = 0xF6F1E9
    static let gold: UInt32 = 0xE1AD66
    static let goldType: UInt32 = 0xF0D3A5
    static let ground: UInt32 = 0x110F0E
    static let groundDeep: UInt32 = 0x0D0B0A
}

enum Ink {
    /// Paper white — all primary type.
    static let paper = Color(hex: Hex.paper)
    /// Gold, the only accent. Equivalent to --color-accent-400.
    static let gold = Color(hex: Hex.gold)
    /// Lighter gold used for type on gold-tinted fills.
    static let goldType = Color(hex: Hex.goldType)
    /// Deep gold for pressed states.
    static let goldDeep = Color(hex: 0xC28D41)
    static let live = Color(hex: 0x7FBF7F)

    static func paper(_ o: Double) -> Color { paper.opacity(o) }
    static func gold(_ o: Double) -> Color { gold.opacity(o) }
}

enum Fmt {
    /// mm:ss, or h:mm:ss past an hour — the locked-screen clock.
    static func clock(_ seconds: Int) -> String {
        let t = max(0, seconds)
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        func p(_ n: Int) -> String { String(format: "%02d", n) }
        return h > 0 ? "\(h):\(p(m)):\(p(s))" : "\(p(m)):\(p(s))"
    }

    /// "2h 40m" / "24m" / "52s" — the human-readable duration used in lists.
    static func span(_ seconds: Int) -> String {
        let t = max(0, seconds)
        let h = t / 3600, m = (t % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m == 0 { return "\(t)s" }
        return "\(m)m"
    }

    /// "14h 05m" — the standings column, always both units.
    static func standings(_ seconds: Int) -> String {
        let t = max(0, seconds)
        return "\(t / 3600)h \(String(format: "%02d", (t % 3600) / 60))m"
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    /// "8 hours ago" / "3 days ago" — for a timestamp whose exact value doesn't
    /// matter, only its distance. Rounds toward the coarser unit on purpose: if
    /// you need to know it was 8 hours rather than 7, the sentence containing
    /// this was the wrong sentence.
    static func ago(_ date: Date, from now: Date = Date()) -> String {
        let style = RelativeDateTimeFormatter()
        style.unitsStyle = .full
        return style.localizedString(for: date, relativeTo: now)
    }

    static func ordinal(_ n: Int) -> String {
        switch n % 100 {
        case 11, 12, 13: return "th"
        default:
            switch n % 10 {
            case 1: return "st"
            case 2: return "nd"
            case 3: return "rd"
            default: return "th"
            }
        }
    }

    /// "Maya, Priya and Dev" / "Maya and 3 others"
    static func names(_ names: [String], max: Int = 3) -> String {
        guard !names.isEmpty else { return "Nobody" }
        if names.count == 1 { return names[0] }
        if names.count > max {
            return "\(names[0]) and \(names.count - 1) others"
        }
        return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
    }
}
