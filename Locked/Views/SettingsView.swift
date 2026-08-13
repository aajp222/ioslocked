import AuthenticationServices
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var shield: ShieldManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var podName = ""
    @State private var confirmReset = false
    @State private var confirmDelete = false
    @State private var notificationsOn = false

    // Pod server
    @State private var serverURL = OnboardingView.defaultServer
    @State private var newPodName = ""
    @State private var joinCode = ""
    @State private var busy = false
    @State private var connectError: String?

    private let goalOptions = [2, 3, 4, 6, 8]

    var body: some View {
        ZStack {
            LockedBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Settings")
                            .font(.display(34))
                            .foregroundStyle(Ink.paper)
                        Spacer()
                        Button {
                            Haptics.tap()
                            commit()
                            dismiss()
                        } label: {
                            Text("Done")
                                .font(.ui(14, .medium))
                                .foregroundStyle(Ink.gold)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 6)

                    youPanel
                    serverPanel
                    goalPanel
                    stakesPanel
                    podPanel
                    blockingPanel
                    orbitPanel
                    notificationsPanel
                    devPanel
                    dangerPanel

                    Text(state.isConnected
                         ? "Locked · signed in as \(state.remote?.name ?? state.me.name). Hours and streaks are counted on the server from your session records, not claimed by this app."
                         : "Locked · not signed in. Sessions, stakes and streaks work on this device; a pod needs an account and a server. See README.md.")
                        .font(.ui(11))
                        .foregroundStyle(Ink.paper(0.3))
                        .lineSpacing(3)
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            name = state.me.name
            podName = state.data.podName
            Task { notificationsOn = await Notifier.settingsAllow() }
        }
        .onDisappear { commit() }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != state.me.name {
            state.data.me.name = trimmed
            state.data.me.initials = AppState.initials(for: trimmed)
        }
        let pod = podName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pod.isEmpty { state.data.podName = pod }
        state.saveNow()
    }

    // MARK: Panels

    private var youPanel: some View {
        Panel(radius: 24, padding: 18) {
            Kicker(text: "You")
                .padding(.bottom, 12)

            field("Name", text: $name)
                .padding(.bottom, 10)
            field("Pod name", text: $podName)
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.ui(12.5))
                .foregroundStyle(Ink.paper(0.45))
                .frame(width: 78, alignment: .leading)
            TextField("", text: text)
                .font(.ui(14.5))
                .foregroundStyle(Ink.paper)
                .tint(Ink.gold)
                .textInputAutocapitalization(.words)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Ink.paper(0.12), lineWidth: 1)
                }
        }
    }

    // MARK: The pod server

    private var serverPanel: some View {
        Panel(radius: 24, padding: 18) {
            HStack(alignment: .firstTextBaseline) {
                Kicker(text: "The pod server")
                Spacer()
                Text(serverStatus)
                    .font(.ui(11.5))
                    .foregroundStyle(state.isConnected && state.syncError == nil ? Ink.gold : Ink.paper(0.4))
            }
            .padding(.bottom, 12)

            if let config = state.remote, config.isInPod {
                connectedBody(config)
            } else if let config = state.remote {
                pairingBody(config)
            } else {
                signInBody
            }

            if let connectError {
                Text(connectError)
                    .font(.ui(11.5))
                    .foregroundStyle(Ink.goldType)
                    .lineSpacing(2)
                    .padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var serverStatus: String {
        if state.syncError != nil { return "Offline" }
        if state.isConnected { return "Live" }
        if state.remote != nil { return "No pod yet" }
        return "Simulated pod"
    }

    /// Step one: an account the server can recognise again.
    private var signInBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Right now your pod is simulated on this device. Sign in and it becomes real people — your account follows your Apple ID, so reinstalling doesn't lose your pod.")
                .font(.ui(12))
                .foregroundStyle(Ink.paper(0.45))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            field("Server", text: $serverURL)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                Task { await handleApple(result) }
            }
            .signInWithAppleButtonStyle(.whiteOutline)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .disabled(busy)
            .opacity(busy ? 0.5 : 1)

            Text(busy
                 ? "Signing in…"
                 : "Server must be running: server/run.sh — then use this Mac's IP instead of localhost on a real phone. Until you sign in, everything keeps working against the simulated pod.")
                .font(.ui(11))
                .foregroundStyle(Ink.paper(0.32))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Step two: make a pod or join one.
    private func pairingBody(_ config: ServerConfig) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Signed in to \(config.baseURL) as \(config.name). Now make a pod or join one.")
                .font(.ui(12))
                .foregroundStyle(Ink.paper(0.45))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            field("Pod name", text: $newPodName)
            Button { Task { await createPod(config) } } label: {
                actionLabel(busy ? "Working…" : "Create the pod")
            }
            .pressable()
            .disabled(busy)

            Rectangle().fill(Ink.paper(0.1)).frame(height: 1).padding(.vertical, 4)

            field("Invite code", text: $joinCode)
            Button { Task { await joinPod(config) } } label: {
                actionLabel(busy ? "Working…" : "Join with that code", gold: false)
            }
            .pressable()
            .disabled(busy || joinCode.trimmingCharacters(in: .whitespaces).count < 4)

            Button { state.disconnect() } label: {
                Text("Forget this server")
                    .font(.ui(12))
                    .foregroundStyle(Ink.paper(0.4))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    /// Connected: show the code to hand out, and how fresh the data is.
    private func connectedBody(_ config: ServerConfig) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: "Invite code", color: Ink.paper(0.4))
                HStack {
                    Text(config.inviteCode ?? "——————")
                        .font(.display(30))
                        .tracking(4)
                        .foregroundStyle(Ink.goldType)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = config.inviteCode
                        Haptics.success()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundStyle(Ink.gold)
                    }
                    .buttonStyle(.plain)
                }
                Text("Anyone who enters this joins \(config.podName ?? "your pod") and starts seeing your sessions.")
                    .font(.ui(11.5))
                    .foregroundStyle(Ink.paper(0.4))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .goldGlass(18, fill: 0.1, border: 0.3)

            HStack(spacing: 8) {
                Text(config.baseURL)
                    .font(.ui(11.5))
                    .foregroundStyle(Ink.paper(0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let error = state.syncError {
                    Text(error)
                        .font(.ui(11))
                        .foregroundStyle(Ink.goldType)
                        .lineLimit(1)
                } else if let last = state.lastSync {
                    Text("synced \(Fmt.span(max(1, Int(state.now.timeIntervalSince(last)))) ) ago")
                        .font(.ui(11))
                        .foregroundStyle(Ink.paper(0.35))
                        .monospacedDigit()
                }
            }

            HStack(spacing: 10) {
                Button { Task { await state.sync(force: true) } } label: {
                    actionLabel("Sync now", gold: false)
                }
                .pressable()

                Button { Task { await state.leavePodForReal() } } label: {
                    actionLabel("Leave pod", gold: false)
                }
                .pressable()
            }
        }
    }

    private func actionLabel(_ text: String, gold: Bool = true) -> some View {
        Text(text)
            .font(.display(14.5, .semibold))
            .foregroundStyle(gold ? Ink.goldType : Ink.paper)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .modifier(ActionSkin(gold: gold))
    }

    // MARK: Server actions

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        busy = true
        connectError = nil
        defer { busy = false }

        switch result {
        case .failure(let error):
            // Cancelling isn't an error worth shouting about.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            connectError = error.localizedDescription
            return

        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                connectError = "Apple didn't return a usable sign-in token."
                return
            }

            // Only present the very first time this Apple ID authorises the app.
            let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")

            do {
                let config = try await Backend.signInWithApple(
                    baseURL: serverURL,
                    identityToken: identityToken,
                    fullName: fullName.isEmpty ? nil : fullName,
                    tzOffsetMinutes: TimeZone.current.secondsFromGMT() / 60
                )
                if config.isInPod {
                    // Already in a pod on another device — go straight in.
                    state.connect(config)
                } else {
                    state.remote = config
                    name = config.name
                    newPodName = state.data.podName
                }
            } catch {
                connectError = error.localizedDescription
            }
        }
    }

    private func createPod(_ config: ServerConfig) async {
        busy = true
        connectError = nil
        do {
            let name = newPodName.trimmingCharacters(in: .whitespacesAndNewlines)
            let updated = try await Backend.createPod(config, name: name.isEmpty ? "The pod" : name)
            state.connect(updated)
        } catch {
            connectError = error.localizedDescription
        }
        busy = false
    }

    private func joinPod(_ config: ServerConfig) async {
        busy = true
        connectError = nil
        do {
            let updated = try await Backend.joinPod(config, code: joinCode)
            state.connect(updated)
            joinCode = ""
        } catch {
            connectError = error.localizedDescription
        }
        busy = false
    }

    private var goalPanel: some View {
        Panel(radius: 24, padding: 18) {
            Kicker(text: "Daily goal")
                .padding(.bottom, 12)

            HStack(spacing: 7) {
                ForEach(goalOptions, id: \.self) { hours in
                    Chip(label: "\(hours)h", selected: state.me.dailyGoalSeconds == hours * 3600) {
                        state.data.me.dailyGoalSeconds = hours * 3600
                        state.save()
                    }
                }
            }
        }
    }

    private var stakesPanel: some View {
        Panel(radius: 24, padding: 18) {
            Kicker(text: "If you fold")
                .padding(.bottom, 12)

            VStack(spacing: 8) {
                ForEach(Stake.allCases) { stake in
                    ChoiceRow(title: stake.title, note: stake.note, selected: state.data.stake == stake) {
                        state.data.stake = stake
                        state.save()
                    }
                }
            }
        }
    }

    private var podPanel: some View {
        Panel(radius: 24, padding: 18) {
            HStack(alignment: .firstTextBaseline) {
                Kicker(text: "The pod")
                Spacer()
                Text("\(state.pod.count) in")
                    .font(.ui(11.5))
                    .foregroundStyle(Ink.paper(0.4))
            }
            .padding(.bottom, 12)

            if state.isConnected {
                VStack(spacing: 8) {
                    ForEach(state.pod) { member in
                        remoteMemberRow(member)
                    }
                    if state.pod.isEmpty {
                        Text("Nobody else yet. Give someone the invite code above.")
                            .font(.ui(12.5))
                            .foregroundStyle(Ink.paper(0.45))
                            .padding(.vertical, 6)
                    }
                }
            } else if state.data.devMode {
                VStack(spacing: 8) {
                    ForEach(state.pod) { member in
                        remoteMemberRow(member)
                    }
                }
            } else {
                Text("Nobody. Sign in above and make a pod, and whoever enters your invite code shows up here.")
                    .font(.ui(12.5))
                    .foregroundStyle(Ink.paper(0.45))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            }

            Text(state.isConnected
                 ? "The real members of \(state.data.podName). They come and go as people enter your invite code."
                 : state.data.devMode
                   ? "Actors, because dev mode is on. Turn it off below to get back to reality."
                   : "A pod is other people's phones talking to the same server as yours.")
                .font(.ui(11))
                .foregroundStyle(Ink.paper(0.32))
                .lineSpacing(2)
                .padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A real pod member. Only the owner sees Remove.
    private func remoteMemberRow(_ member: PodMember) -> some View {
        HStack(spacing: 12) {
            Avatar(initials: member.initials, active: member.status.isLocked, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.ui(14))
                    .foregroundStyle(Ink.paper)
                Text(member.statusLine)
                    .font(.ui(11.5))
                    .foregroundStyle(Ink.paper(0.45))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if state.iOwnPod {
                Button {
                    Haptics.tap()
                    Task { await state.kick(member) }
                } label: {
                    Text("Remove")
                        .font(.ui(12))
                        .foregroundStyle(Ink.paper(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .glass(17, fill: 0.1, border: 0.13)
    }

    private var blockingPanel: some View {
        Panel(radius: 24, padding: 18) {
            HStack(alignment: .firstTextBaseline) {
                Kicker(text: "Real blocking")
                Spacer()
                Text(shield.state.label)
                    .font(.ui(11.5))
                    .foregroundStyle(shield.state.isReal ? Ink.gold : Ink.paper(0.4))
            }
            .padding(.bottom, 14)

            RealAppPicker()
        }
    }

    /// Read-only, and deliberately so. There is nothing to configure — the
    /// bridge is on when both apps are installed and off otherwise. It exists
    /// because the failure is silent by nature: no goal chips look exactly like
    /// no tasks in Orbit, and "my tasks aren't showing up" deserves an answer
    /// that isn't a shrug.
    private var orbitPanel: some View {
        Panel(radius: 24, padding: 18) {
            HStack(alignment: .firstTextBaseline) {
                Kicker(text: "Orbit")
                Spacer()
                Text(orbitStatus)
                    .font(.ui(11.5))
                    .foregroundStyle(OrbitLink.isAvailable ? Ink.gold : Ink.paper(0.4))
            }
            .padding(.bottom, 10)

            Text(orbitNote)
                .font(.ui(11.5))
                .foregroundStyle(Ink.paper(0.38))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var orbitStatus: String {
        guard OrbitLink.isAvailable else { return "Not connected" }
        let count = OrbitLink.suggestions().count
        return count == 0 ? "Nothing waiting" : "\(count) task\(count == 1 ? "" : "s")"
    }

    private var orbitNote: String {
        guard OrbitLink.isAvailable else {
            return "Install Orbit on this phone and its top tasks become your goal options. Nothing leaves the device."
        }
        return OrbitLink.suggestions().isEmpty
            ? "Orbit is connected but has nothing due. Open it to refresh, or type a goal yourself."
            : "Orbit's top tasks appear as goals when you start a session. Time served goes back to it; nothing else does."
    }

    private var notificationsPanel: some View {
        Panel(radius: 24, padding: 18) {
            HStack(alignment: .firstTextBaseline) {
                Kicker(text: "Notifications")
                Spacer()
                Text(notificationsOn ? "On" : "Off")
                    .font(.ui(11.5))
                    .foregroundStyle(notificationsOn ? Ink.gold : Ink.paper(0.4))
            }
            .padding(.bottom, 12)

            Text("Locked uses them for session end, pod verdicts and incoming requests.")
                .font(.ui(12))
                .foregroundStyle(Ink.paper(0.45))
                .lineSpacing(2)
                .padding(.bottom, 12)

            Rectangle().fill(Ink.paper(0.1)).frame(height: 1)
                .padding(.vertical, 12)

            HStack(alignment: .firstTextBaseline) {
                Kicker(text: "Lock Screen timer")
                Spacer()
                Text(state.data.liveActivityEnabled ? state.live.status : "Off")
                    .font(.ui(11.5))
                    .foregroundStyle(state.data.liveActivityEnabled && state.live.isRunning ? Ink.gold : Ink.paper(0.4))
                    .multilineTextAlignment(.trailing)
            }
            .padding(.bottom, 10)

            Text("A card on the Lock Screen and a ring in the Dynamic Island while you're locked. The island can't be made smaller than the sensor housing, so turn this off if you'd rather have it back.")
                .font(.ui(11.5))
                .foregroundStyle(Ink.paper(0.4))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)

            Button {
                Haptics.tap()
                state.setLiveActivity(!state.data.liveActivityEnabled)
            } label: {
                Text(state.data.liveActivityEnabled ? "Turn the Lock Screen timer off" : "Turn the Lock Screen timer on")
                    .font(.display(14, .semibold))
                    .foregroundStyle(state.data.liveActivityEnabled ? Ink.paper : Ink.goldType)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .modifier(ActionSkin(gold: !state.data.liveActivityEnabled))
            }
            .pressable()
            .padding(.bottom, 12)

            Button {
                Haptics.tap()
                if notificationsOn {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } else {
                    Task {
                        _ = await Notifier.requestAuthorization()
                        notificationsOn = await Notifier.settingsAllow()
                        if !notificationsOn, let url = URL(string: UIApplication.openSettingsURLString) {
                            _ = await UIApplication.shared.open(url)
                        }
                    }
                }
            } label: {
                Text(notificationsOn ? "Open iOS notification settings" : "Turn notifications on")
                    .font(.display(14.5, .semibold))
                    .foregroundStyle(Ink.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .glass(16, fill: 0.09, border: 0.16)
            }
            .pressable()
        }
    }

    private var devPanel: some View {
        Panel(radius: 24, padding: 18) {
            HStack(alignment: .firstTextBaseline) {
                Kicker(text: "Dev mode")
                Spacer()
                Text(state.data.devMode ? "On" : "Off")
                    .font(.ui(11.5))
                    .foregroundStyle(state.data.devMode ? Ink.gold : Ink.paper(0.4))
            }
            .padding(.bottom, 12)

            Text(state.isConnected
                 ? "Not available while you're in a real pod — invented activity has no business in a real feed. Leave the pod first."
                 : "Fills the pod with four actors who lock in, fold, and answer your unlock requests on a timer. For demos and testing; nothing leaves this device.")
                .font(.ui(12))
                .foregroundStyle(Ink.paper(0.45))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            Button {
                Haptics.tap()
                let turningOff = state.data.devMode
                state.setDevMode(!state.data.devMode)
                // Turning it off with no real pod means setup is unfinished, and
                // the app is about to show onboarding behind this sheet.
                if turningOff && !state.isConnected { dismiss() }
            } label: {
                Text(state.data.devMode ? "Turn dev mode off" : "Turn dev mode on")
                    .font(.display(14.5, .semibold))
                    .foregroundStyle(state.data.devMode ? Ink.paper : Ink.goldType)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .modifier(ActionSkin(gold: !state.data.devMode))
            }
            .pressable()
            .disabled(state.isConnected)
            .opacity(state.isConnected ? 0.45 : 1)

            if state.data.devMode {
                Button {
                    Haptics.tap()
                    dismiss()
                    Task { await state.pullIncoming(force: true) }
                } label: {
                    Text("Send me an unlock request")
                        .font(.ui(13.5))
                        .foregroundStyle(Ink.paper(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .glass(16, fill: 0.07, border: 0.14)
                }
                .pressable()
                .padding(.top, 8)
            }
        }
    }

    private var dangerPanel: some View {
        Panel(radius: 24, padding: 18) {
            Kicker(text: "Start over")
                .padding(.bottom, 12)

            Button {
                Haptics.tap()
                confirmReset = true
            } label: {
                Text("Erase all sessions, streaks and history")
                    .font(.ui(13.5))
                    .foregroundStyle(Ink.paper(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Ink.paper(0.16), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .confirmationDialog("Erase everything?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Erase", role: .destructive) {
                    state.resetEverything()
                    dismiss()
                }
                Button("Keep it", role: .cancel) {}
            }

            if state.isConnected {
                Text("Deleting your account removes your sessions, your feed and your pod membership from the server too. It can't be undone.")
                    .font(.ui(11))
                    .foregroundStyle(Ink.paper(0.32))
                    .lineSpacing(2)
                    .padding(.top, 12)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Haptics.tap()
                    confirmDelete = true
                } label: {
                    Text("Delete my account")
                        .font(.display(14, .semibold))
                        .foregroundStyle(Ink.goldType)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .goldGlass(16, fill: 0.14, border: 0.4)
                }
                .pressable()
                .padding(.top, 8)
                .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete everything", role: .destructive) {
                        Task {
                            await state.deleteAccountEverywhere()
                            dismiss()
                        }
                    }
                    Button("Keep my account", role: .cancel) {}
                }
            }
        }
    }
}

/// Gold for the affirmative action, glass for the rest.
struct ActionSkin: ViewModifier {
    var gold: Bool

    func body(content: Content) -> some View {
        if gold {
            content.goldGlass(16, fill: 0.16, border: 0.4)
        } else {
            content.glass(16, fill: 0.09, border: 0.16)
        }
    }
}

extension AppState {
    /// "Sam Okafor" -> "SO", "Sam" -> "SM".
    /// Nonisolated so the networking layer can call it off the main actor.
    nonisolated static func initials(for name: String) -> String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return (parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.replacingOccurrences(of: " ", with: "").prefix(2)).uppercased()
    }
}
