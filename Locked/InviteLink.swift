import Foundation

/// `locked://join?code=ABC123` — the shareable form of an invite code.
///
/// Six typed characters is the last removable step in getting a friend into a
/// pod, and it happens after they have already installed TestFlight and the
/// app. Removing it is most of what stands between a working app and a working
/// pod.
///
/// Foundation only, and pure, so every branch below is reachable from a test
/// rather than only from a phone with the right link pasted into it.
enum InviteLink {
    static let scheme = "locked"
    static let host = "join"

    /// The invite alphabet the server draws from: Crockford-style, with the
    /// characters people misread already removed (no I, O, 0, 1).
    static let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let codeLength = 6

    static func url(code: String) -> URL? {
        guard let code = normalise(code) else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "code", value: code)]
        return components.url
    }

    /// What you actually send someone. The bare URL alone reads as a string of
    /// noise in a message, and a link nobody understands is a link nobody taps.
    static func shareText(code: String, podName: String?) -> String? {
        guard let url = url(code: code) else { return nil }
        let pod = (podName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        }
        return """
        Join \(pod ?? "my pod") on Locked.

        \(url.absoluteString)

        Or open Locked and enter \(code).
        """
    }

    /// The code carried by a link, if it is one of ours and well-formed.
    ///
    /// Returns nil rather than guessing. A malformed link opens the app and
    /// does nothing, which is the correct outcome — the alternative is showing
    /// someone a join prompt for a pod that cannot exist.
    static func code(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == "code" })?.value
        else { return nil }
        return normalise(raw)
    }

    /// Uppercases, trims, and refuses anything that is not exactly one code.
    ///
    /// Validated on the way in so a link cannot smuggle arbitrary text into the
    /// join field, and so an obviously wrong code never costs a network round
    /// trip — or one of the ten attempts an hour the server now allows.
    static func normalise(_ raw: String) -> String? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard cleaned.count == codeLength, cleaned.allSatisfy(alphabet.contains) else { return nil }
        return cleaned
    }
}
