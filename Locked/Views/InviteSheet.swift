import SwiftUI

/// What a tapped invite link opens.
///
/// It asks. Links get forwarded, screenshotted and pasted into group chats,
/// and joining a pod is not a small thing — from that moment four people see
/// what you said you would do, how long you lasted, and every time you folded.
/// Auto-joining would make a link that leaked into the wrong chat a way to put
/// strangers in your feed, and would hand anyone who could get you to tap
/// something the ability to choose who watches you.
struct InviteSheet: View {
    let code: String
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var busy = false
    @State private var failure: String?

    private var alreadyInAPod: Bool { state.remote?.isInPod == true }
    private var signedIn: Bool { state.remote != nil }

    var body: some View {
        ZStack {
            LockedBackground()

            VStack(alignment: .leading, spacing: 0) {
                Kicker(text: "You've been invited", color: Ink.paper(0.42))
                    .padding(.bottom, 12)

                Text(code)
                    .font(.display(46))
                    .tracking(6)
                    .foregroundStyle(Ink.goldType)
                    .padding(.bottom, 18)

                Text(explanation)
                    .font(.ui(13))
                    .foregroundStyle(Ink.paper(0.6))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 22)

                if let failure {
                    Text(failure)
                        .font(.ui(12))
                        .foregroundStyle(Ink.goldType)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 16)
                }

                if signedIn {
                    GoldButton(title: busy ? "Joining…" : "Join the pod", radius: 18, vertical: 15) {
                        Task { await join() }
                    }
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)
                    .padding(.bottom, 10)
                } else {
                    GoldButton(title: "Sign in first", radius: 18, vertical: 15) {
                        // Held rather than dropped. The copy above promises the
                        // code will be waiting, and `deferInvite` is what makes
                        // that true across the trip out to Sign in with Apple.
                        state.deferInvite(code)
                        state.showSettings = true
                        dismiss()
                    }
                    .padding(.bottom, 10)
                }

                QuietButton(title: "Not now") {
                    state.dismissInvite()
                    dismiss()
                }
            }
            .padding(24)
            .frame(maxWidth: 360)
        }
    }

    private var explanation: String {
        if !signedIn {
            return "Joining a pod needs an account — yours follows your Apple ID, so reinstalling never loses it. Sign in and this code will be waiting."
        }
        if alreadyInAPod {
            return "You're already in \(state.data.podName). Joining this one leaves that pod, and the people in it stop seeing your sessions."
        }
        return "Everyone in this pod will see what you said you'd do, how long you lasted, and every time you fold. That is the entire point, and it is not reversible session by session."
    }

    private func join() async {
        guard let config = state.remote else { return }
        busy = true
        failure = nil
        do {
            let updated = try await Backend.joinPod(config, code: code)
            state.connect(updated)
            state.dismissInvite()
            Haptics.success()
            dismiss()
        } catch {
            // Includes the server's 429, which reads as "too many attempts —
            // try again in Ns". Worth showing verbatim rather than flattening
            // to "couldn't join": the two have completely different answers.
            failure = error.localizedDescription
            Haptics.failure()
        }
        busy = false
    }
}
