import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LockedWidgetBundle: WidgetBundle {
    var body: some Widget {
        LockedLiveActivity()
    }
}

struct LockedLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LockedActivityAttributes.self) { context in
            LockScreenCard(context: context)
                .activityBackgroundTint(Color(hex: Hex.groundDeep, alpha: 0.92))
                .activitySystemActionForegroundColor(Ink.gold)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.onBreak ? "lock.open" : "lock")
                            .font(.system(size: 13, weight: .medium))
                        Text(context.state.onBreak ? "On break" : "Locked")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Ink.gold)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context, size: 17)
                        .foregroundStyle(Ink.paper)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(context.attributes.goal)
                            .font(.system(size: 17, design: .serif))
                            .foregroundStyle(Ink.paper)
                            .lineLimit(1)

                        ProgressView(timerInterval: context.state.range, countsDown: true) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .progressViewStyle(.linear)
                        .tint(Ink.gold)

                        Text(subline(context))
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.paper(0.5))
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                // Nothing: the pill is sized by its content, and the timer alone
                // is the shortest it can be. The glyph lives on in the minimal
                // presentation, where a countdown wouldn't fit.
                EmptyView()
            } compactTrailing: {
                emptyingRing(context)
            } minimal: {
                emptyingRing(context)
            }
            .keylineTint(Ink.gold)
        }
    }

    /// The least intrusive thing that still says "you are locked": a ring that
    /// drains. No digits, so the pill stays as narrow as iOS allows.
    private func emptyingRing(_ context: ActivityViewContext<LockedActivityAttributes>) -> some View {
        ProgressView(timerInterval: context.state.range, countsDown: true) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.circular)
        .tint(Ink.gold)
    }

    private func countdown(_ context: ActivityViewContext<LockedActivityAttributes>, size: CGFloat) -> some View {
        Text(
            timerInterval: context.state.range,
            pauseTime: nil,
            countsDown: true,
            showsHours: false
        )
        .font(.system(size: size, weight: .regular, design: .serif))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func subline(_ context: ActivityViewContext<LockedActivityAttributes>) -> String {
        if let until = context.state.breakUntil, until > Date() {
            return "Phone until \(Fmt.time(until)) — then it seals again"
        }
        let apps = context.attributes.blockedCount
        return "\(context.attributes.watcherLine) · \(apps) app\(apps == 1 ? "" : "s") sealed"
    }
}

// MARK: - Lock Screen

struct LockScreenCard: View {
    let context: ActivityViewContext<LockedActivityAttributes>

    private var onBreak: Bool { context.state.onBreak }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Ink.gold)
                        .frame(width: 5, height: 5)
                    Text(onBreak ? "ON BREAK" : "LOCKED")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.6)
                }
                .foregroundStyle(Ink.gold)

                Spacer()

                Text(
                    timerInterval: context.state.range,
                    pauseTime: nil,
                    countsDown: true,
                    showsHours: true
                )
                .font(.system(size: 26, weight: .regular, design: .serif))
                .monospacedDigit()
                .foregroundStyle(onBreak ? Ink.paper(0.5) : Ink.paper)
            }
            .padding(.bottom, 8)

            Text(context.attributes.goal)
                .font(.system(size: 21, design: .serif))
                .foregroundStyle(Ink.paper)
                .lineLimit(1)
                .padding(.bottom, 10)

            ProgressView(timerInterval: context.state.range, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(Ink.gold)
            .padding(.bottom, 9)

            HStack(spacing: 6) {
                Image(systemName: onBreak ? "hourglass" : "eye")
                    .font(.system(size: 10))
                Text(footer)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
            }
            .foregroundStyle(Ink.paper(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var footer: String {
        if let until = context.state.breakUntil, until > Date() {
            return "Phone until \(Fmt.time(until)). The clock keeps running."
        }
        if context.state.requestsSent >= 3 {
            return "You've asked three times. They've stopped reading."
        }
        let apps = context.attributes.blockedCount
        return "\(context.attributes.watcherLine) · \(apps) app\(apps == 1 ? "" : "s") sealed"
    }
}
