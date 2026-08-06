import UserNotifications
import XCTest
@testable import Locked

/// Records what the app would have sent to the server.
///
/// `isRemote` is true so the store takes its connected code paths without any
/// network. Not `@MainActor`: it has to satisfy the nonisolated protocol.
final class RecordingPodService: PodService {
    var isRemote: Bool { true }

    private let lock = NSLock()
    private var _answered: [(id: String, approve: Bool)] = []

    var answered: [(id: String, approve: Bool)] {
        lock.lock()
        defer { lock.unlock() }
        return _answered
    }

    func send(_ request: UnlockRequest, pod: [PodMember]) async -> Verdict { .expired }
    func pollIncoming(pod: [PodMember], mySeed: UInt64) async -> UnlockRequest? { nil }
    func publish(_ event: FeedEvent) async {}

    func answer(requestID: String, approve: Bool, quip: String) async {
        lock.lock()
        _answered.append((requestID, approve))
        lock.unlock()
    }
}

/// Ruling on somebody's request from the Lock Screen, without opening the app.
///
/// The real push delivery is verified against Apple's sandbox separately; this
/// covers what the app does when one of the buttons is pressed.
@MainActor
final class PushHandlingTests: XCTestCase {
    private var storage: URL!
    private var service: RecordingPodService!

    override func setUp() async throws {
        storage = FileManager.default.temporaryDirectory
            .appendingPathComponent("locked-push-\(UUID().uuidString).json")
        service = RecordingPodService()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: storage)
    }

    private func makeState() -> AppState {
        let state = AppState(
            service: service,
            shield: ShieldManager(),
            clock: { Date() },
            storageURL: storage,
            startTimer: false
        )
        // The test host shares the app group, so it may have a real server
        // config lying around. Drop it: these tests talk to nothing.
        state.remote = nil
        return state
    }

    private func requestPayload(_ id: String) -> [AnyHashable: Any] {
        ["kind": "request", "request_id": id, "requester": "Maya K"]
    }

    /// The store fires the network call in a detached task; give it a moment.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 200_000_000)
    }

    func testApprovingFromTheNotificationTellsTheServerAndWritesTheFeed() async {
        let state = makeState()
        state.handlePush(userInfo: requestPayload("req-approve"), action: Notifier.approveAction)
        await settle()

        XCTAssertEqual(service.answered.count, 1)
        XCTAssertEqual(service.answered.first?.id, "req-approve")
        XCTAssertEqual(service.answered.first?.approve, true)

        let event = state.data.feed.first
        XCTAssertNotNil(event)
        XCTAssertTrue(event?.isMe ?? false)
        if case .granted(let to, let minutes) = event?.kind {
            XCTAssertEqual(to, "Maya K")
            XCTAssertEqual(minutes, 5)
        } else {
            XCTFail("expected a granted event, got \(String(describing: event?.kind))")
        }
    }

    func testDenyingFromTheNotificationAlsoReachesTheServer() async {
        let state = makeState()
        state.handlePush(userInfo: requestPayload("req-deny"), action: Notifier.denyAction)
        await settle()

        XCTAssertEqual(service.answered.first?.id, "req-deny")
        XCTAssertEqual(service.answered.first?.approve, false)

        if case .denied(let to) = state.data.feed.first?.kind {
            XCTAssertEqual(to, "Maya K")
        } else {
            XCTFail("expected a denied event")
        }
    }

    func testAnsweringClearsTheRequestSittingInTheApp() async {
        let state = makeState()
        let waiting = UnlockRequest(
            remoteID: "req-open",
            requesterName: "Maya K", requesterInitials: "MK", isOutgoing: false,
            reason: "bored", goal: "thesis", remainingAtRequest: 900,
            streak: 3, cavesThisWeek: 0
        )
        state.data.requests = [waiting]
        state.incoming = waiting

        state.handlePush(userInfo: requestPayload("req-open"), action: Notifier.denyAction)
        await settle()

        XCTAssertNil(state.incoming, "the takeover screen shouldn't still be waiting")
        XCTAssertNotNil(state.data.requests.first?.verdict, "the request is settled")
        XCTAssertTrue(state.pendingIncoming.isEmpty)
    }

    func testATapWithNoActionJustOpensThePodInsteadOfDeciding() async {
        let state = makeState()
        state.route = .today

        state.handlePush(
            userInfo: requestPayload("req-tap"),
            action: UNNotificationDefaultActionIdentifier
        )
        await settle()

        XCTAssertEqual(state.route, .pod)
        XCTAssertTrue(service.answered.isEmpty, "a tap must not silently answer for them")
    }

    func testAVerdictPushDoesNotAnswerAnything() async {
        let state = makeState()
        state.handlePush(
            userInfo: ["kind": "verdict", "request_id": "mine"],
            action: UNNotificationDefaultActionIdentifier
        )
        await settle()

        XCTAssertTrue(service.answered.isEmpty)
    }

    func testTheDeviceTokenIsRememberedForNextLaunch() {
        let state = makeState()
        state.registerPushToken("abc123token")
        XCTAssertEqual(state.pushToken, "abc123token")

        let relaunched = makeState()
        XCTAssertEqual(relaunched.pushToken, "abc123token", "the token survives a launch")
    }
}
