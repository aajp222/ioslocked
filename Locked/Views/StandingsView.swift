import SwiftUI

struct StandingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This week")
                        .font(.display(34))
                        .foregroundStyle(Ink.paper)
                    Text("Hours locked · resets Sunday midnight")
                        .font(.ui(12))
                        .foregroundStyle(Ink.paper(0.42))
                }
                .padding(.bottom, 8)

                board
                if !state.data.history.isEmpty { historyCard }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 118)
        }
    }

    private var board: some View {
        VStack(spacing: 0) {
            let rows = state.standings
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 14) {
                    Text("\(row.rank)")
                        .font(.display(20))
                        .foregroundStyle(row.rank == 1 || row.isMe ? Ink.gold : Ink.paper(0.45))
                        .frame(width: 22, alignment: .leading)
                        .monospacedDigit()
                    Text(row.name)
                        .font(.ui(15))
                        .foregroundStyle(row.isMe ? Ink.paper : Ink.paper(0.85))
                    Spacer()
                    Text(Fmt.standings(row.seconds))
                        .font(.display(20))
                        .foregroundStyle(row.isMe ? Ink.goldType : Ink.paper(row.seconds == 0 ? 0.5 : 0.9))
                        .monospacedDigit()
                }
                .padding(.horizontal, row.isMe ? 12 : 0)
                .padding(.vertical, 15)
                .background {
                    if row.isMe {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Ink.gold(0.1))
                    }
                }
                .overlay(alignment: .bottom) {
                    if index < rows.count - 1 {
                        Rectangle().fill(Ink.paper(0.09)).frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .glass(26, fill: 0.11, border: 0.14)
    }

    // The "Everyone on Locked" card was here: a global rank out of 214,900
    // people, both numbers invented. The pod board above it is real — the
    // server derives those hours from session records — and putting a fiction
    // directly beneath it taught you to read both the same way.

    private var historyCard: some View {
        Panel(radius: 26, padding: 20, fill: 0.09) {
            Kicker(text: "Your sessions", color: Ink.paper(0.42))
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                let sessions = Array(state.data.history.prefix(8))
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    HStack(spacing: 12) {
                        Image(systemName: session.outcome == .completed ? "checkmark.circle" : "xmark.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(session.outcome == .completed ? Ink.gold : Ink.paper(0.35))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.goal)
                                .font(.ui(13.5))
                                .foregroundStyle(Ink.paper(0.85))
                                .lineLimit(1)
                            Text(session.startedAt.formatted(.dateTime.month().day().hour().minute()))
                                .font(.ui(11))
                                .foregroundStyle(Ink.paper(0.35))
                        }
                        Spacer(minLength: 4)
                        Text(session.outcome == .completed
                             ? Fmt.span(session.plannedSeconds)
                             : "quit at \(Fmt.span(session.elapsed(at: session.endsAt)))")
                            .font(.ui(12))
                            .foregroundStyle(session.outcome == .completed ? Ink.goldType : Ink.paper(0.4))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 10)

                    if index < sessions.count - 1 {
                        Rectangle().fill(Ink.paper(0.08)).frame(height: 1)
                    }
                }
            }
        }
    }
}
