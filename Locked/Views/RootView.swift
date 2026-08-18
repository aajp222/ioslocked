import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var shield: ShieldManager
    @Environment(\.scenePhase) private var phase
    @State private var showStart = false

    var body: some View {
        ZStack {
            LockedBackground()
            content
            if let completed = state.completed {
                CompletionOverlay(session: completed)
            }
        }
        .fullScreenCover(isPresented: $showStart) {
            StartSessionView()
        }
        .fullScreenCover(item: $state.incoming) { request in
            IncomingRequestView(request: request)
        }
        .sheet(isPresented: $state.showSettings) {
            SettingsView()
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .active {
                // Screen Time access is almost always granted in Settings, with
                // this app in the background — so coming back is the one moment
                // it is worth asking iOS again. Without this the app keeps the
                // answer it had at launch and stays in honour-system mode until
                // it is force-quit and reopened, long after you fixed it.
                shield.refreshAuthorization()
                state.refresh()
            } else {
                state.saveNow()
            }
        }
        .onAppear {
            if state.data.hasOnboarded { state.askForNotificationsIfNeeded() }
        }
        .animation(.easeInOut(duration: 0.25), value: state.route)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.session?.id)
    }

    /// The premise needs a pod. Signed out with no pod and no dev mode means
    /// setup never finished — including for anyone upgrading from the build that
    /// shipped a cast of invented friends.
    private var needsSetup: Bool {
        !state.data.hasOnboarded || !(state.isConnected || state.data.devMode)
    }

    @ViewBuilder private var content: some View {
        if needsSetup {
            OnboardingView()
        } else if state.session != nil {
            LockedView()
        } else {
            ZStack(alignment: .bottom) {
                Group {
                    switch state.route {
                    case .today: TodayView(showStart: $showStart)
                    case .pod: FeedView()
                    case .standings: StandingsView()
                    }
                }
                TabBar(route: $state.route, badge: state.pendingIncoming.count)
                    .padding(.bottom, 6)
            }
        }
    }
}

/// Shown the moment a session runs out — the only unambiguously good screen.
struct CompletionOverlay: View {
    @EnvironmentObject private var state: AppState
    let session: Session

    var body: some View {
        ZStack {
            Scrim(opacity: 0.66)

            VStack(spacing: 0) {
                Image(systemName: "lock.open")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Ink.gold)
                    .frame(width: 58, height: 58)
                    .glass(20, fill: 0.14, border: 0.18)
                    .padding(.bottom, 22)

                Text("Time served.")
                    .font(.display(40))
                    .foregroundStyle(Ink.paper)
                    .padding(.bottom, 10)

                Text("\(Fmt.span(session.plannedSeconds)) on \(session.goal). The phone is yours.")
                    .font(.ui(13.5))
                    .foregroundStyle(Ink.paper(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.bottom, 22)

                HStack(spacing: 10) {
                    stat("Streak", "\(state.me.streak)")
                    stat("Banked", "\(state.me.bankedMinutes)m")
                    stat("Today", Fmt.span(state.todayTotal))
                }
                .padding(.bottom, 22)

                GoldButton(title: "Good.") {
                    state.completed = nil
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
        }
        .transition(.opacity)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.display(24))
                .foregroundStyle(Ink.paper)
                .monospacedDigit()
            Kicker(text: label, color: Ink.paper(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glass(18, fill: 0.1, border: 0.13)
    }
}
