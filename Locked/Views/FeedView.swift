import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.data.podName)
                        .font(.display(34))
                        .foregroundStyle(Ink.paper)
                    Text("\(state.podSize) members · \(Fmt.span(state.podWeekSeconds)) locked this week")
                        .font(.ui(12))
                        .foregroundStyle(Ink.paper(0.42))
                }
                .padding(.bottom, 8)

                ForEach(state.pendingIncoming) { request in
                    requestCard(request)
                }

                ForEach(state.data.feed) { event in
                    card(event)
                }

                if state.data.feed.isEmpty && state.pendingIncoming.isEmpty {
                    Panel(radius: 26, padding: 22) {
                        Text(state.isConnected ? "Nothing yet." : "No pod yet.")
                            .font(.display(24))
                            .foregroundStyle(Ink.paper)
                            .padding(.bottom, 8)
                        Text(state.isConnected
                             ? "Lock something, or wait for someone else to. Every session, every fold and every verdict lands here."
                             : "Sign in and make a pod in Settings — or turn on dev mode if you just want to see how it reads.")
                            .font(.ui(13))
                            .foregroundStyle(Ink.paper(0.45))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ForEach(idleMembers) { member in
                    nudgeRow(member)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 118)
        }
    }

    private var idleMembers: [PodMember] {
        state.pod.filter { member in
            if case .idle = member.status { return true }
            return false
        }
    }

    // MARK: Cards

    private func card(_ event: FeedEvent) -> some View {
        let failure = event.isFailure
        let live = isLive(event)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Avatar(initials: event.isMe ? state.me.initials : event.authorInitials,
                       active: live, size: 34)
                Text(event.isMe ? "You" : event.authorName)
                    .font(.ui(14))
                    .foregroundStyle(live ? Ink.paper : Ink.paper(0.8))
                Spacer()
                if live {
                    HStack(spacing: 5) {
                        LiveDot(size: 5)
                        Text("live").font(.ui(11)).foregroundStyle(Ink.gold)
                    }
                } else {
                    Text(Fmt.time(event.date))
                        .font(.ui(11))
                        .foregroundStyle(Ink.paper(0.35))
                        .monospacedDigit()
                }
            }
            .padding(.bottom, 14)

            Text(event.headline)
                .font(.display(22))
                .foregroundStyle(Ink.paper)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if let subline = event.subline {
                Text(subline)
                    .font(.ui(12))
                    .foregroundStyle(Ink.paper(0.45))
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if failure || event.shame > 0 || event.comment != nil {
                HStack(spacing: 8) {
                    Button {
                        state.shame(event)
                    } label: {
                        Text("shame · \(event.shame)")
                            .font(.ui(11))
                            .monospacedDigit()
                            .foregroundStyle(Ink.paper(0.6))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background { Capsule().strokeBorder(Ink.paper(0.18), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)

                    if let comment = event.comment, let author = event.commentAuthor {
                        Text("“\(comment)” — \(author)")
                            .font(.ui(11))
                            .foregroundStyle(Ink.paper(0.6))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background { Capsule().strokeBorder(Ink.paper(0.18), lineWidth: 1) }
                    }
                }
                .padding(.top, 14)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FeedCardSkin(failure: failure && event.isMe))
    }

    private func isLive(_ event: FeedEvent) -> Bool {
        if case .locked(_, let seconds) = event.kind {
            // My own card is only live while I'm actually still locked — folding
            // or finishing kills it, whatever the clock said at the time.
            if event.isMe { return state.session != nil }
            return event.date.addingTimeInterval(Double(seconds)) > state.now
        }
        return false
    }

    private func requestCard(_ request: UnlockRequest) -> some View {
        Button {
            Haptics.tap()
            state.incoming = request
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 11) {
                    Avatar(initials: request.requesterInitials, active: true, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(request.requesterName) wants out")
                            .font(.display(17, .semibold))
                            .foregroundStyle(Ink.paper)
                        Text("dies in \(request.secondsLeft)s")
                            .font(.ui(11))
                            .foregroundStyle(Ink.gold)
                            .monospacedDigit()
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ink.gold)
                }
                .padding(.bottom, 12)

                Text("“\(request.reason)”")
                    .font(.display(20))
                    .foregroundStyle(Ink.goldType)
                    .multilineTextAlignment(.leading)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .goldGlass(26, fill: 0.14, border: 0.42)
        }
        .pressable()
    }

    private func nudgeRow(_ member: PodMember) -> some View {
        HStack(spacing: 11) {
            Avatar(initials: member.initials, size: 30)
            Text("\(member.name) hasn't locked once today.")
                .font(.ui(12.5))
                .foregroundStyle(Ink.paper(0.45))
            Spacer(minLength: 4)
            Button {
                state.nudge(member)
            } label: {
                Text("Nudge")
                    .font(.ui(12.5))
                    .foregroundStyle(Ink.gold)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Ink.paper(0.16))
        }
    }
}

/// Failures of mine get the gold-bordered treatment; everything else is glass.
struct FeedCardSkin: ViewModifier {
    var failure: Bool

    func body(content: Content) -> some View {
        if failure {
            content.goldGlass(26, fill: 0.16, border: 0.4)
        } else {
            content.glass(26, fill: 0.1, border: 0.13)
        }
    }
}
