import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var state: AppState
    @Binding var showStart: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                header
                nowCard
                statRow
                podCard
                if !state.pendingIncoming.isEmpty { requestNudge }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 118)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Kicker(text: state.now.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                       color: Ink.paper(0.4))
                Text(state.greeting)
                    .font(.display(31))
                    .foregroundStyle(Ink.paper)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "flame")
                        .font(.system(size: 11, weight: .medium))
                    Text("\(state.me.streak)")
                        .font(.ui(11))
                        .monospacedDigit()
                }
                .foregroundStyle(Ink.gold)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule().strokeBorder(Ink.gold(0.4), lineWidth: 1)
                }

                Button {
                    Haptics.tap()
                    state.showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.paper(0.5))
                        .frame(width: 30, height: 30)
                        .background { Circle().strokeBorder(Ink.paper(0.14), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 8)
    }

    // MARK: Right now

    private var nowCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Kicker(text: "Right now")
                Spacer()
                HStack(spacing: 6) {
                    LiveDot(color: Ink.live)
                    Text("Phone unlocked")
                        .font(.ui(11.5))
                        .foregroundStyle(Ink.paper(0.5))
                }
            }
            .padding(.bottom, 20)

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    BigFigure(seconds: state.todayTotal, size: 72)
                    Text("locked today · goal \(Fmt.span(state.me.dailyGoalSeconds))")
                        .font(.ui(12.5))
                        .foregroundStyle(Ink.paper(0.5))
                }
                Spacer(minLength: 0)
                Ring(progress: state.dayProgress, size: 76, lineWidth: 5) {
                    Text("\(Int((state.dayProgress * 100).rounded()))%")
                        .font(.display(19))
                        .foregroundStyle(Ink.paper)
                        .monospacedDigit()
                }
            }
            .padding(.bottom, 22)

            GoldButton(title: "Lock my phone", icon: "lock", radius: 19, vertical: 15) {
                showStart = true
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .glass(30, fill: 0.13, border: 0.16, shadow: 0.45)
    }

    // MARK: Stats

    private var statRow: some View {
        HStack(spacing: 12) {
            statCard(kicker: "Earned", value: "\(state.me.bankedMinutes)", unit: "min", note: "of scroll, banked")
            statCard(
                kicker: "Pod rank",
                value: "\(state.myPodRank)",
                unit: Fmt.ordinal(state.myPodRank),
                note: rankNote
            )
        }
    }

    private var rankNote: String {
        switch state.myPodRank {
        case 1: return "of \(state.podSize). for now"
        case state.podSize: return "of \(state.podSize). dead last"
        default: return "of \(state.podSize). embarrassing"
        }
    }

    private func statCard(kicker: String, value: String, unit: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Kicker(text: kicker, color: Ink.paper(0.4))
                .padding(.bottom, 9)
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(value).font(.display(38)).foregroundStyle(Ink.paper).monospacedDigit()
                Text(unit).font(.display(17)).foregroundStyle(Ink.paper(0.45))
            }
            Text(note)
                .font(.ui(11.5))
                .foregroundStyle(Ink.paper(0.42))
                .padding(.top, 7)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(24, fill: 0.1, border: 0.13)
    }

    // MARK: The pod

    private var podCard: some View {
        Panel(radius: 26, padding: 20) {
            HStack {
                Kicker(text: "The pod")
                Spacer()
                Button {
                    Haptics.tap()
                    state.route = .pod
                } label: {
                    Text("See all")
                        .font(.ui(11.5))
                        .foregroundStyle(Ink.gold)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 16)

            VStack(spacing: 0) {
                let members = state.pod
                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                    HStack(spacing: 13) {
                        Avatar(initials: member.initials, active: member.status.isLocked)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name)
                                .font(.ui(14))
                                .foregroundStyle(member.status.isLocked ? Ink.paper : Ink.paper(0.75))
                            Text(member.statusLine)
                                .font(.ui(11.5))
                                .foregroundStyle(Ink.paper(0.45))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(member.statusTrailing)
                            .font(.ui(member.status.isLocked ? 12 : 11))
                            .foregroundStyle(member.status.isLocked ? Ink.gold : Ink.paper(0.35))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 11)

                    if index < members.count - 1 {
                        Rectangle().fill(Ink.paper(0.09)).frame(height: 1)
                    }
                }

                if members.isEmpty {
                    Button {
                        Haptics.tap()
                        state.showSettings = true
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(state.isConnected
                                 ? "Nobody else in here yet."
                                 : "No pod yet.")
                                .font(.display(19))
                                .foregroundStyle(Ink.paper)
                            Text(state.isConnected
                                 ? "Give someone your invite code — the app does nothing alone."
                                 : "Sign in and make a pod, or turn on dev mode to look around.")
                                .font(.ui(12.5))
                                .foregroundStyle(Ink.paper(0.45))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var requestNudge: some View {
        Button {
            Haptics.tap()
            state.incoming = state.pendingIncoming.first
        } label: {
            HStack(spacing: 11) {
                LiveDot()
                Text("\(state.pendingIncoming.count) unlock request waiting on you")
                    .font(.ui(12.5))
                    .foregroundStyle(Ink.paper(0.72))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.gold)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .goldGlass(22, fill: 0.1, border: 0.3)
        }
        .pressable()
    }
}
