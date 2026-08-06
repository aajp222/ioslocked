import SwiftUI

/// Someone in the pod wants out and you are the judge. This is the screen the
/// prototype called "Friend's phone" — except now it's your phone, and the
/// verdict actually goes back to them.
struct IncomingRequestView: View {
    @EnvironmentObject private var state: AppState
    let request: UnlockRequest

    private var expired: Bool { request.secondsLeft == 0 && state.incomingVerdict == nil }

    var body: some View {
        ZStack {
            LockedBackground()

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    if !expired && state.incomingVerdict == nil { LiveDot(size: 5) }
                    Text(headerText)
                        .font(.ui(10, .medium))
                        .tracking(1.8)
                        .textCase(.uppercase)
                        .monospacedDigit()
                }
                .foregroundStyle(Ink.paper(0.4))
                .padding(.bottom, 26)

                if let verdict = state.incomingVerdict {
                    result(title: verdictTitle(verdict), body: verdictBody(verdict))
                } else if expired {
                    result(title: "You ignored it.",
                           body: "The request died on its own. \(request.requesterName) stays locked, and now knows nobody answered.")
                } else {
                    pending
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.incomingVerdict)
    }

    private var headerText: String {
        if state.incomingVerdict != nil || expired { return "Unlock request" }
        return "Unlock request · dies in \(request.secondsLeft)s"
    }

    // MARK: Pending

    private var pending: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Avatar(initials: request.requesterInitials, active: true, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(request.requesterName) wants out")
                            .font(.display(18, .semibold))
                            .foregroundStyle(Ink.paper)
                        Text("\(Fmt.span(request.remainingAtRequest)) still on the clock")
                            .font(.ui(11.5))
                            .foregroundStyle(Ink.paper(0.45))
                    }
                }
                .padding(.bottom, 20)

                Text("“\(request.reason)”")
                    .font(.display(26))
                    .foregroundStyle(Ink.goldType)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Rectangle().fill(Ink.paper(0.12)).frame(height: 1) }
                    .overlay(alignment: .bottom) { Rectangle().fill(Ink.paper(0.12)).frame(height: 1) }
                    .padding(.bottom, 16)

                Text("Goal · \(request.goal)")
                    .font(.ui(12))
                    .foregroundStyle(Ink.paper(0.5))

                HStack(spacing: 18) {
                    Text("Streak \(request.streak)")
                    Text(request.cavesThisWeek == 0
                         ? "Never caved this week"
                         : "Caved \(request.cavesThisWeek)× this week")
                }
                .font(.ui(12))
                .foregroundStyle(Ink.paper(0.5))
                .monospacedDigit()
                .padding(.top, 12)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(30, fill: 0.14, border: 0.17, shadow: 0.45)

            HStack(spacing: 10) {
                Button {
                    Haptics.seal()
                    state.answer(request, approve: false)
                } label: {
                    Text("Absolutely not")
                        .font(.display(15.5, .semibold))
                        .foregroundStyle(Ink.goldType)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .goldGlass(20, fill: 0.26, border: 0.5)
                }
                .pressable()

                Button {
                    Haptics.success()
                    state.answer(request, approve: true)
                } label: {
                    Text("Give 5 min")
                        .font(.display(15.5, .semibold))
                        .foregroundStyle(Ink.paper(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .glass(20, fill: 0.07, border: 0.16)
                }
                .pressable()
            }
            .padding(.top, 14)

            Text("Ignore it and the request dies in \(Int(request.lifetime)) seconds. \(request.requesterName) stays locked.")
                .font(.ui(11.5))
                .foregroundStyle(Ink.paper(0.35))
                .lineSpacing(2)
                .padding(.horizontal, 4)
                .padding(.top, 16)

            Button {
                Haptics.tap()
                state.dismissIncoming()
            } label: {
                Text("Not now")
                    .font(.ui(13))
                    .foregroundStyle(Ink.paper(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Result

    private func result(title: String, body: String) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.display(30))
                .foregroundStyle(Ink.paper)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            Text(body)
                .font(.ui(13.5))
                .foregroundStyle(Ink.paper(0.55))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.bottom, 20)

            Button {
                Haptics.tap()
                state.dismissIncoming()
            } label: {
                Text("Done")
                    .font(.display(14, .semibold))
                    .foregroundStyle(Ink.paper)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .glass(16, fill: 0.09, border: 0.17)
            }
            .pressable()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .glass(30, fill: 0.13, border: 0.16)
    }

    private func verdictTitle(_ verdict: Verdict) -> String {
        switch verdict {
        case .approved: return "You let \(request.requesterName) out."
        case .denied: return "Denied."
        case .expired: return "It expired."
        }
    }

    private func verdictBody(_ verdict: Verdict) -> String {
        switch verdict {
        case .approved(_, let minutes):
            return "\(minutes) minutes of phone. The pod feed now says you were the soft one."
        case .denied:
            return "\(request.requesterName) stays locked for \(Fmt.span(request.remainingAtRequest)) more. This is what friendship is."
        case .expired:
            return "Nobody answered in time."
        }
    }
}
