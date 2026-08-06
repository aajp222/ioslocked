import AuthenticationServices
import SwiftUI

/// The front door. Four steps, and three of them do real work: an account tied
/// to your Apple ID, a pod that exists on a server, and the stake you're taking.
///
/// The old version let you pick from four invented friends and dropped you into
/// an app where nothing you did left the device. Nothing here is pretend.
struct OnboardingView: View {
    @EnvironmentObject private var state: AppState

    @State private var step = 0
    @State private var serverURL = OnboardingView.defaultServer
    @State private var podName = ""
    @State private var joinCode = ""
    @State private var busy = false
    @State private var problem: String?

    /// The deployed pod server. Prefilled so anyone you invite only has to sign
    /// in — typing a URL is the fastest way to lose a friend at step two.
    /// Editable, for pointing at a local server during development.
    static let production = "https://locked-pod-aaryan.fly.dev"

    static var defaultServer: String { production }

    var body: some View {
        ZStack {
            LockedBackground()

            VStack(alignment: .leading, spacing: 0) {
                switch step {
                case 0: intro
                case 1: account
                case 2: pod
                default: stakes
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 32)
            .padding(.bottom, 24)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
        .onAppear {
            // Signed in already (reinstall, or they came back) — skip ahead.
            if let config = state.remote {
                serverURL = config.baseURL
                step = config.isInPod ? 3 : 2
            }
        }
    }

    // MARK: One — why

    private var intro: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            Image(systemName: "lock")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Ink.gold)
                .frame(width: 66, height: 66)
                .glass(22, fill: 0.16, border: 0.18, shadow: 0.45)
                .padding(.bottom, 30)

            Text("Your phone\nis not yours\nright now.")
                .font(.display(50))
                .foregroundStyle(Ink.paper)
                .lineSpacing(-2)
                .padding(.bottom, 16)

            Text("You pick the work. Locked holds the phone. Real people decide whether you get it back early — and they find out when you fold.")
                .font(.ui(15))
                .foregroundStyle(Ink.paper(0.6))
                .lineSpacing(5)
                .frame(maxWidth: 300, alignment: .leading)

            Spacer()

            GoldButton(title: "Start") { step = 1 }
            stepLabel("Step one of four")
        }
        .transition(.opacity)
    }

    // MARK: Two — an account

    private var account: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Step two", "Who are you?",
                   "Your account lives on your pod's server and follows your Apple ID. Delete the app, get a new phone — the pod remembers you.")

            field("Server", text: $serverURL, placeholder: serverPlaceholder)
                .padding(.bottom, 6)

            Text(serverHint)
                .font(.ui(11))
                .foregroundStyle(Ink.paper(0.35))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                Task { await signIn(result) }
            }
            .signInWithAppleButtonStyle(.whiteOutline)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .disabled(busy || serverURL.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(busy || serverURL.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)

            problemText

            Spacer()

            // No server to hand, or just looking around: dev mode fills the pod
            // with actors so the app is explorable without lying about it.
            Button {
                state.setDevMode(true)
                state.finishOnboarding()
                state.askForNotificationsIfNeeded()
            } label: {
                Text("No server yet — show me the app in dev mode")
                    .font(.ui(12.5))
                    .foregroundStyle(Ink.paper(0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .glass(14, fill: 0.06, border: 0.12)
            }
            .pressable()
            .padding(.bottom, 10)

            Button("Back") { step = 0 }
                .font(.ui(13))
                .foregroundStyle(Ink.paper(0.4))
                .frame(maxWidth: .infinity)
            stepLabel(busy ? "Signing in…" : "Step two of four")
        }
        .transition(.opacity)
    }

    private var serverPlaceholder: String { Self.production }

    private var serverHint: String {
        if serverURL.trimmingCharacters(in: .whitespaces) == Self.production {
            return "The pod server, already running. Leave it as it is unless you're pointing at your own."
        }
        return "A pod server you can reach. On a phone, localhost means the phone itself — use a machine's address or a public URL."
    }

    // MARK: Three — a pod

    private var pod: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Step three", "Find your people",
                   "A pod is three to six people who will absolutely not be nice about it. Make one and hand out the code, or use somebody else's.")

            field("Pod name", text: $podName, placeholder: "Fifth Floor")
                .padding(.bottom, 10)

            Button { Task { await createPod() } } label: {
                actionLabel(busy ? "Working…" : "Create the pod")
            }
            .pressable()
            .disabled(busy)

            HStack(spacing: 12) {
                line
                Text("or")
                    .font(.ui(11.5))
                    .foregroundStyle(Ink.paper(0.35))
                line
            }
            .padding(.vertical, 16)

            field("Invite code", text: $joinCode, placeholder: "ABC123", uppercase: true)
                .padding(.bottom, 10)

            Button { Task { await joinPod() } } label: {
                actionLabel(busy ? "Working…" : "Join with that code", gold: false)
            }
            .pressable()
            .disabled(busy || joinCode.trimmingCharacters(in: .whitespaces).count < 4)

            problemText

            Spacer()

            stepLabel("Step three of four")
        }
        .transition(.opacity)
    }

    private var line: some View {
        Rectangle().fill(Ink.paper(0.12)).frame(height: 1)
    }

    // MARK: Four — the stake

    private var stakes: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Step four", "What it costs you",
                   "Pick the punishment for breaking a session early. Your pod sees it either way.")

            VStack(spacing: 10) {
                ForEach(Stake.allCases) { stake in
                    ChoiceRow(title: stake.title, note: stake.note, selected: state.data.stake == stake) {
                        state.data.stake = stake
                        state.save()
                    }
                }
            }

            Spacer()

            if let config = state.remote, let code = config.inviteCode {
                VStack(alignment: .leading, spacing: 6) {
                    Kicker(text: "Your invite code", color: Ink.paper(0.4))
                    Text(code)
                        .font(.display(28))
                        .tracking(4)
                        .foregroundStyle(Ink.goldType)
                    Text("Send this to the people who should see your sessions.")
                        .font(.ui(11.5))
                        .foregroundStyle(Ink.paper(0.4))
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .goldGlass(18, fill: 0.1, border: 0.3)
                .padding(.bottom, 14)
            }

            Text("Locked will ask for notifications next. Without them your pod can't reach you mid-session — which is most of the point.")
                .font(.ui(11.5))
                .foregroundStyle(Ink.paper(0.38))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            GoldButton(title: "Lock me in") {
                state.finishOnboarding()
                state.askForNotificationsIfNeeded()
            }
            stepLabel("Step four of four")
        }
        .transition(.opacity)
    }

    // MARK: Pieces

    private func header(_ kicker: String, _ title: String, _ blurb: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Kicker(text: kicker, color: Color(hex: 0xC08F4E))
                .padding(.top, 30)
                .padding(.bottom, 12)
            Text(title)
                .font(.display(38))
                .foregroundStyle(Ink.paper)
                .padding(.bottom, 10)
            Text(blurb)
                .font(.ui(13.5))
                .foregroundStyle(Ink.paper(0.55))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)
        }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, uppercase: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.ui(12.5))
                .foregroundStyle(Ink.paper(0.45))
                .frame(width: 86, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.ui(14.5))
                .foregroundStyle(Ink.paper)
                .tint(Ink.gold)
                .textInputAutocapitalization(uppercase ? .characters : .never)
                .autocorrectionDisabled()
                .keyboardType(uppercase ? .asciiCapable : .URL)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Ink.paper(0.12), lineWidth: 1)
                }
        }
    }

    private func actionLabel(_ text: String, gold: Bool = true) -> some View {
        Text(text)
            .font(.display(15, .semibold))
            .foregroundStyle(gold ? Ink.goldType : Ink.paper)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .modifier(ActionSkin(gold: gold))
    }

    @ViewBuilder private var problemText: some View {
        if let problem {
            Text(problem)
                .font(.ui(11.5))
                .foregroundStyle(Ink.goldType)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    private func stepLabel(_ text: String) -> some View {
        Text(text)
            .font(.ui(11))
            .foregroundStyle(Ink.paper(0.3))
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
    }

    // MARK: Doing the work

    private func signIn(_ result: Result<ASAuthorization, Error>) async {
        busy = true
        problem = nil
        defer { busy = false }

        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            problem = error.localizedDescription

        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken,
                  let token = String(data: data, encoding: .utf8)
            else {
                problem = "Apple didn't return a usable sign-in token."
                return
            }

            // Apple sends the name once, ever. Send it now or lose it.
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")

            do {
                let config = try await Backend.signInWithApple(
                    baseURL: serverURL,
                    identityToken: token,
                    fullName: name.isEmpty ? nil : name,
                    tzOffsetMinutes: TimeZone.current.secondsFromGMT() / 60
                )
                if config.isInPod {
                    state.connect(config)
                    step = 3
                } else {
                    state.remote = config
                    step = 2
                }
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func createPod() async {
        guard let config = state.remote else { return }
        busy = true
        problem = nil
        defer { busy = false }

        let name = podName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let updated = try await Backend.createPod(config, name: name.isEmpty ? "Your pod" : name)
            state.connect(updated)
            step = 3
        } catch {
            problem = error.localizedDescription
        }
    }

    private func joinPod() async {
        guard let config = state.remote else { return }
        busy = true
        problem = nil
        defer { busy = false }

        do {
            let updated = try await Backend.joinPod(config, code: joinCode)
            state.connect(updated)
            step = 3
        } catch {
            problem = error.localizedDescription
        }
    }
}
