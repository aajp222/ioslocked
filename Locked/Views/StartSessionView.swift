import SwiftUI

struct StartSessionView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var shield: ShieldManager
    @Environment(\.dismiss) private var dismiss

    @State private var goal = ""
    @State private var minutes = 90
    @FocusState private var goalFocused: Bool

    /// Orbit's shortlist, read once when the screen opens. Empty whenever Orbit
    /// isn't installed, hasn't run, or its plan has gone stale.
    @State private var orbitTasks: [OrbitBridge.FocusCandidate] = []

    /// Which of them this session is against, if any. Cleared the moment the
    /// goal stops matching, so a receipt can never credit time to a task whose
    /// name you edited away.
    @State private var pickedTaskID: UUID?

    var body: some View {
        ZStack(alignment: .bottom) {
            LockedBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    backButton

                    Text("What are you\nactually doing?")
                        .font(.display(39))
                        .foregroundStyle(Ink.paper)
                        .lineSpacing(-1)
                        .padding(.bottom, 12)

                    goalPanel
                    durationPanel
                    appsPanel
                    stakePanel
                    consequence
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }

            VStack(spacing: 0) {
                GoldButton(title: "Lock it", radius: 20, vertical: 17) {
                    Haptics.seal()
                    state.startSession(
                        goal: goal,
                        minutes: minutes,
                        stake: state.data.stake,
                        orbitTaskID: pickedTaskID
                    )
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 26)
        }
        .onAppear {
            goal = state.data.lastGoal
            minutes = state.data.lastMinutes
            // Read once, on open. Re-reading while the sheet is up would let
            // the chips change under a finger already moving toward one.
            orbitTasks = OrbitLink.suggestions()
        }
        .onTapGesture { goalFocused = false }
    }

    private var backButton: some View {
        Button {
            Haptics.tap()
            dismiss()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                Text("Today").font(.ui(13))
            }
            .foregroundStyle(Ink.paper(0.5))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
    }

    // MARK: Goal

    private var goalPanel: some View {
        Panel(radius: 24, padding: 18, fill: 0.11) {
            Kicker(text: orbitTasks.isEmpty ? "The goal · your pod sees this"
                                           : "The goal · from Orbit · your pod sees this",
                   color: Ink.paper(0.42))
                .padding(.bottom, 10)

            ZStack(alignment: .leading) {
                if goal.isEmpty {
                    Text("Say it out loud")
                        .font(.display(23))
                        .foregroundStyle(Ink.paper(0.28))
                }
                TextField("", text: $goal, axis: .vertical)
                    .font(.display(23))
                    .foregroundStyle(Ink.paper)
                    .tint(Ink.gold)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($goalFocused)
                    .onSubmit { goalFocused = false }
                    // Typing over a picked task detaches it. The pod sees
                    // whatever ends up here either way; what must not happen is
                    // Orbit being told you spent ninety minutes on a task you
                    // renamed to something else before sealing.
                    .onChange(of: goal) { _, text in
                        if let id = pickedTaskID,
                           orbitTasks.first(where: { $0.id == id })?.title != text {
                            pickedTaskID = nil
                        }
                    }
            }
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Ink.gold(0.4)).frame(height: 1)
            }
            .padding(.bottom, 14)

            if orbitTasks.isEmpty {
                FlowChips(items: Copy.goalChips, id: \.self) { chip in
                    Chip(label: chip, selected: goal == chip) {
                        goal = chip
                        goalFocused = false
                    }
                }
            } else {
                // Orbit's four, in its order. Tapping one takes its estimate as
                // well as its name: the point of the bridge is that you stop
                // re-deciding how long the thing takes at the exact moment you
                // are looking for a reason not to start.
                FlowChips(items: orbitTasks, id: \.id) { task in
                    Chip(label: task.title, selected: pickedTaskID == task.id) {
                        goal = task.title
                        minutes = task.minutes
                        pickedTaskID = task.id
                        goalFocused = false
                    }
                }
            }
        }
    }

    // MARK: Duration

    private var durationPanel: some View {
        Panel(radius: 24, padding: 18, fill: 0.11) {
            Kicker(text: "How long", color: Ink.paper(0.42))
                .padding(.bottom, 14)

            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text("\(minutes)")
                    .font(.display(62))
                    .foregroundStyle(Ink.paper)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(minutes == 1 ? "minute" : "minutes")
                    .font(.ui(17))
                    .foregroundStyle(Ink.paper(0.45))
                Spacer()
                Text("ends \(Fmt.time(state.now.addingTimeInterval(Double(minutes) * 60)))")
                    .font(.ui(11.5))
                    .foregroundStyle(Ink.paper(0.4))
            }
            .padding(.bottom, 14)

            HStack(spacing: 7) {
                ForEach(Copy.durations, id: \.self) { value in
                    Button {
                        Haptics.select()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { minutes = value }
                    } label: {
                        Text("\(value)m")
                            .font(.display(14, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(minutes == value ? Ink.goldType : Ink.paper(0.65))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(minutes == value ? Ink.gold(0.22) : Color.white.opacity(0.05))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                                            .strokeBorder(minutes == value ? Ink.gold(0.5) : Ink.paper(0.14), lineWidth: 1)
                                    }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 12)

            Slider(
                value: Binding(
                    get: { Double(minutes) },
                    set: { minutes = max(1, Int(($0 / 5).rounded()) * 5) }
                ),
                in: 1...240,
                step: 5
            )
            .tint(Ink.gold)
        }
    }

    // MARK: Apps

    private var appsPanel: some View {
        Panel(radius: 24, padding: 18, fill: 0.11) {
            Kicker(text: "Sealed off", color: Ink.paper(0.42))
                .padding(.bottom, 14)

            // One control, not two. A row of six invented app names used to sit
            // above this, and the picker's own footnote had to explain that the
            // chips were decorative — which is a sentence no screen should have
            // to contain. The picker reports its own count.
            RealAppPicker()
                .padding(.bottom, 14)

            Text("Calls, maps and your bank still work. You are locked out, not stranded.")
                .font(.ui(11.5))
                .foregroundStyle(Ink.paper(0.38))
                .lineSpacing(2)
        }
    }

    // MARK: Stakes

    private var stakePanel: some View {
        Panel(radius: 24, padding: 18, fill: 0.11) {
            Kicker(text: "If you fold", color: Ink.paper(0.42))
                .padding(.bottom, 12)

            FlowChips(items: Stake.allCases, id: \.id) { stake in
                Chip(label: stake.title, selected: state.data.stake == stake) {
                    state.data.stake = stake
                    state.save()
                }
            }
        }
    }

    private var consequence: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Ink.gold)
            Group {
                Text("Break it early and the pod gets: ")
                    .foregroundStyle(Ink.paper(0.72))
                + Text("“\(state.me.firstName) couldn't last \(minutes) minutes.”")
                    .foregroundStyle(Ink.goldType)
            }
            .font(.ui(12.5))
            .lineSpacing(3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .goldGlass(22, fill: 0.07, border: 0.28)
    }
}

// MARK: - Wrapping chip row

/// A simple flow layout so chips wrap like the prototype's flex-wrap rows.
struct FlowChips<Item, ID: Hashable, Content: View>: View {
    let items: [Item]
    let id: KeyPath<Item, ID>
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(items, id: id) { item in
                content(item)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
