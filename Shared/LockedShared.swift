import Foundation

/// The seam between the app and its three extensions. Everything here is
/// compiled into all four targets, so it must stay dependency-free.
enum LockedShared {
    static let appGroup = "group.com.aaryanpanchal.locked"

    /// The DeviceActivity schedule the monitor extension watches.
    static let activityName = "locked.session"

    /// Where the picked app tokens live, readable by the monitor extension.
    static let selectionKey = "locked.shield.selection"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// The shared container, falling back to the app's own Documents if the
    /// group isn't provisioned yet (so a broken entitlement degrades to
    /// app-only storage instead of losing data).
    static var container: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func file(_ name: String) -> URL {
        container.appendingPathComponent(name)
    }

    static var groupIsAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil
    }
}

/// A small, extension-readable slice of the running session.
///
/// The extensions can't decode the app's whole `AppData` (it isn't compiled into
/// them, and shouldn't be), so the app writes this alongside it whenever the
/// session changes. The shield screen and the Live Activity both read it.
struct SessionSnapshot: Codable, Equatable {
    var goal: String
    var startedAt: Date
    var endsAt: Date
    var breakUntil: Date?
    var podNames: [String]
    var blockedCount: Int
    var ownerName: String

    static let filename = "session-snapshot.json"

    var remaining: Int { max(0, Int(endsAt.timeIntervalSinceNow.rounded(.up))) }
    var onBreak: Bool { (breakUntil ?? .distantPast) > Date() }
    var isRunning: Bool { endsAt > Date() }

    /// "Maya, Priya and Dev are watching"
    var watcherLine: String {
        guard !podNames.isEmpty else { return "Nobody is watching. That was the point." }
        let verb = podNames.count == 1 ? "is" : "are"
        return "\(Fmt.names(podNames)) \(verb) watching."
    }

    static func load() -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: LockedShared.file(filename)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SessionSnapshot.self, from: data)
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: LockedShared.file(Self.filename), options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: LockedShared.file(filename))
    }
}
