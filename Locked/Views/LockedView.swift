import SwiftUI

struct LockedView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var shield: ShieldManager

    @State private var reason = Copy.reasons[2]
    @State private var custom = ""
    @FocusState private var customFocused: Bool

    private var session: Session? { state.session }

    var body: some View {
        ZStack {
            LockedBackground(deep: true)

            if let session {
                VStack(spacing: 0) {
                    badge
                        .padding(.top, 12)

                    ring(session)
                        .padding(.top, 30)
                        .padding(.bottom, 26)

                    Text(session.goal)
                        .font(.display(26))
                        .foregroundStyle(Ink.paper)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 8)

                    Text(metaLine(session))
                        .font(.ui(12.5))
                        .foregroundStyle(Ink.paper(0.45))
                        .padding(.bottom, 22)

                    watchers

                    Spacer(minLength: 20)

                    if !shield.state.isReal {
                        Text("Honour system: iOS isn't enforcing the block on this build.")
                            .font(.ui(11))
                            .foregroundStyle(Ink.paper(0.3))
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 12)
                    }

                    GlassButton(title: begTitle(session)) {
                        state.compose()
                    }
                    .opacity(session.requestsSent >= 3 ? 0.45 : 1)
                    .disabled(session.requestsSent >= 3 || state.onBreak)
                    .padding(.bottom, 12)

                    QuietButton(title: "End early and take the L") {
                        state.showCaveSheet = true
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            overlays
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.85), value: state.outgoing)
        .animation(.spring(response: 0.34, dampingFraction: 0.85), value: state.showCaveSheet)
    }

    // MARK: Pieces

    private var badge: some View {
        HStack(spacing: 7) {
            LiveDot(size: 5)
            Text(state.onBreak ? "\(Fmt.clock(state.breakRemaining)) of phone" : "Locked")
                .font(.ui(10.5, .medium))
                .tracking(1.6)
                .textCase(.uppercase)
                .monospacedDigit()
        }
        .foregroundStyle(Ink.gold)
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(Ink.gold(0.08))
                .overlay { Capsule().strokeBorder(Ink.gold(0.35), lineWidth: 1) }
        }
    }

    private func ring(_ session: Session) -> some View {
        let fraction = session.plannedSeconds > 0
            ? Double(state.remaining) / Double(session.plannedSeconds)
            : 0
        return Ring(progress: fraction, size: 252, lineWidth: 2, track: 0.09) {
            VStack(spacing: 10) {
                Text(Fmt.clock(state.remaining))
                    .font(.display(64))
                    .foregroundStyle(Ink.paper)
                    .monospacedDigit()
                Kicker(text: "remaining", color: Ink.paper(0.38))
            }
        }
        .opacity(state.onBreak ? 0.45 : 1)
    }

    private func metaLine(_ session: Session) -> String {
        let apps = "\(session.blocked.count) app\(session.blocked.count == 1 ? "" : "s") sealed"
        let watchers = state.pod.count
        return "\(apps) · \(watchers) \(watchers == 1 ? "person" : "people") watching"
    }

    private var watchers: some View {
        HStack(spacing: -8) {
            ForEach(state.pod) { member in
                Avatar(initials: member.initials, active: true, size: 32)
            }
        }
    }

    private func begTitle(_ session: Session) -> String {
        switch session.requestsSent {
        case 0: return "Beg the pod for 5 minutes"
        case 1: return "Beg again"
        case 2: return "Beg a third time. Really?"
        default: return "They've stopped reading"
        }
    }

    // MARK: Overlays

    @ViewBuilder private var overlays: some View {
        switch state.outgoing {
        case .composing:
            ZStack(alignment: .bottom) {
                Scrim(opacity: 0.55) { state.cancelCompose() }
                composeSheet
            }
        case .pending(let reason):
            pendingOverlay(reason)
        case .verdict(let verdict):
            ZStack(alignment: .bottom) {
                Scrim(opacity: 0.62)
                verdictSheet(verdict)
            }
        case .none:
            if state.showCaveSheet {
                ZStack(alignment: .bottom) {
                    Scrim(opacity: 0.62) { state.showCaveSheet = false }
                    caveSheet
                }
            }
        }
    }

    private var composeSheet: some View {
        BottomSheet {
            VStack(alignment: .leading, spacing: 0) {
                Text("Why do you need it?")
                    .font(.display(29))
                    .foregroundStyle(Ink.paper)
                    .padding(.bottom, 6)

                Text("All \(state.pod.count) of them read this. Choose wisely.")
                    .font(.ui(12.5))
                    .foregroundStyle(Ink.paper(0.5))
                    .padding(.bottom, 18)

                VStack(spacing: 8) {
                    ForEach(Copy.reasons, id: \.self) { option in
                        Button {
                            Haptics.select()
                            reason = option
                            custom = ""
                            customFocused = false
                        } label: {
                            Text(option)
                                .font(.ui(13.5))
                                .foregroundStyle(reason == option && custom.isEmpty ? Ink.goldType : Ink.paper(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 13)
                                .background {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(reason == option && custom.isEmpty ? Ink.gold(0.2) : Color.white.opacity(0.05))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .strokeBorder(reason == option && custom.isEmpty ? Ink.gold(0.5) : Ink.paper(0.13), lineWidth: 1)
                                        }
                                }
                        }
                        .buttonStyle(.plain)
                    }

                    ZStack(alignment: .leading) {
                        if custom.isEmpty {
                            Text("Or type your excuse")
                                .font(.ui(13.5))
                                .foregroundStyle(Ink.paper(0.35))
                        }
                        TextField("", text: $custom)
                            .font(.ui(13.5))
                            .foregroundStyle(Ink.paper)
                            .tint(Ink.gold)
                            .focused($customFocused)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 13)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(custom.isEmpty ? 0.03 : 0.08))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(custom.isEmpty ? Ink.paper(0.1) : Ink.gold(0.45), lineWidth: 1)
                            }
                    }
                }
                .padding(.bottom, 18)

                GoldButton(title: "Send it") {
                    let text = custom.trimmingCharacters(in: .whitespacesAndNewlines)
                    customFocused = false
                    state.sendRequest(reason: text.isEmpty ? reason : text)
                }

                QuietButton(title: "Never mind") {
                    customFocused = false
                    state.cancelCompose()
                }
            }
        }
    }

    private func pendingOverlay(_ reason: String) -> some View {
        ZStack {
            Scrim(opacity: 0.62)
            VStack(spacing: 0) {
                PulsingDots()
                    .padding(.bottom, 26)

                Text("Asking the pod")
                    .font(.display(32))
                    .foregroundStyle(Ink.paper)
                    .padding(.bottom, 10)

                Text("\(podNames) \(state.pod.count == 1 ? "is" : "are") being notified. Any one of them can unlock you.")
                    .font(.ui(13.5))
                    .foregroundStyle(Ink.paper(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 260)

                Text("“\(reason)”")
                    .font(.ui(12.5))
                    .foregroundStyle(Ink.paper(0.6))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.white.opacity(0.05))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Ink.paper(0.13), lineWidth: 1)
                            }
                    }
                    .padding(.top, 22)
            }
            .padding(40)
        }
    }

    private var podNames: String {
        let names = state.pod.map(\.name)
        guard names.count > 1 else { return names.first ?? "Nobody" }
        return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
    }

    private func verdictSheet(_ verdict: Verdict) -> some View {
        BottomSheet {
            VStack(spacing: 0) {
                Text(verdictTitle(verdict))
                    .font(.display(34))
                    .foregroundStyle(Ink.paper)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)

                Text(verdictBody(verdict))
                    .font(.ui(13.5))
                    .foregroundStyle(Ink.paper(0.58))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.bottom, 20)

                GlassButton(title: verdict.isApproval ? "Use it wisely" : "Back to work") {
                    state.dismissVerdict()
                }
            }
        }
    }

    private func verdictTitle(_ verdict: Verdict) -> String {
        switch verdict {
        case .approved(let by, let minutes): return "\(by) gave you \(minutes) minutes."
        case .denied(let by, _): return "\(by) said no."
        case .expired: return "Nobody answered."
        }
    }

    private func verdictBody(_ verdict: Verdict) -> String {
        switch verdict {
        case .approved(let by, let minutes):
            return "\(minutes) minutes, then it seals again. \(by) is watching the timer."
        case .denied(_, let quip):
            return "Their exact words: “\(quip)” The clock keeps running."
        case .expired:
            return "The request died after 60 seconds of silence. You stay locked."
        }
    }

    private var caveSheet: some View {
        BottomSheet {
            VStack(alignment: .leading, spacing: 0) {
                Text("Quitting, then.")
                    .font(.display(30))
                    .foregroundStyle(Ink.paper)
                    .padding(.bottom, 8)

                Text(caveWarning)
                    .font(.ui(13.5))
                    .foregroundStyle(Ink.paper(0.55))
                    .lineSpacing(4)
                    .padding(.bottom, 18)

                VStack(alignment: .leading, spacing: 7) {
                    Kicker(text: "They will see", color: Ink.paper(0.4))
                    Text("“\(state.me.firstName) folded with \(Fmt.clock(state.remaining)) left on the clock.”")
                        .font(.display(19))
                        .foregroundStyle(Ink.goldType)
                        .lineSpacing(2)
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .goldGlass(18, fill: 0.09, border: 0.3)
                .padding(.bottom, 18)

                GoldButton(title: "Fold anyway", radius: 19, vertical: 15) {
                    state.cave()
                }
                QuietButton(title: "Stay locked") {
                    state.showCaveSheet = false
                }
            }
        }
    }

    private var caveWarning: String {
        var lines = ["This goes to the pod feed immediately, with the time on it."]
        switch state.data.stake {
        case .post: lines.append("That was the deal you picked.")
        case .streak: lines.append("Your streak of \(state.me.streak) ends here.")
        case .money: lines.append("Five dollars to the pot, and everyone sees why.")
        }
        return lines.joined(separator: " ")
    }
}

struct PulsingDots: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Ink.gold)
                    .frame(width: 9, height: 9)
                    .scaleEffect(phase ? 1 : 0.86)
                    .opacity(phase ? 1 : 0.35)
                    .animation(
                        .easeInOut(duration: 0.65)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.18),
                        value: phase
                    )
            }
        }
        .onAppear { phase = true }
    }
}
