import XCTest
@testable import Locked

/// The Orbit seam.
///
/// Everything here is either pure or read-only. The write paths — `writePlan`,
/// `append`, `removeReceipts` — deliberately have no unit test: they touch the
/// one real shared container, and a test suite run on a phone mid-session would
/// delete a queued receipt that represents hours somebody actually served.
/// Those paths are covered by the end-to-end check in INTEGRATION.md instead,
/// which is the only place they can be exercised honestly anyway.
final class OrbitBridgeTests: XCTestCase {

    // MARK: The entitlement

    /// The whole integration rests on this being true, and it fails silently:
    /// an unprovisioned group returns a private Application Support directory
    /// rather than nil, both apps happily write to their own sandbox, and
    /// nothing anywhere reports a problem.
    func testTheSharedContainerIsActuallyShared() {
        XCTAssertTrue(
            OrbitBridge.isAvailable,
            "group.com.aaryanpanchal.orbitlocked is not provisioned to this build — "
                + "the bridge has silently degraded to app-local storage."
        )
        XCTAssertTrue(
            OrbitBridge.containerURL.path.contains("AppGroup"),
            "Resolved to the fallback directory instead of the App Group."
        )
    }

    // MARK: What we can honestly claim about Orbit

    /// The bug this replaced: the panel keyed off the App Group entitlement,
    /// which LOCKED grants itself. On a TestFlight phone that had never seen
    /// Orbit it read "Orbit is connected but has nothing due" — confidently, and
    /// about an app the tester did not have installed.
    func testAPhoneWithoutOrbitIsNotReportedAsConnected() {
        let status = OrbitLink.status(for: nil, provisioned: true)
        XCTAssertEqual(status, .noPlan)
    }

    func testAnUnprovisionedContainerOutranksEverythingElse() {
        let plan = OrbitBridge.FocusPlan(candidates: [
            .init(id: UUID(), title: "Essay", minutes: 60)
        ])
        XCTAssertEqual(OrbitLink.status(for: plan, provisioned: false), .unavailable)
    }

    /// "Orbit wrote this a week ago" and "Orbit has never written here" need
    /// opposite advice — open the app, versus install it — so they must not
    /// collapse into one state.
    func testStaleIsDistinctFromNeverWritten() {
        let now = Date()
        let old = now.addingTimeInterval(-30 * 3600)
        let plan = OrbitBridge.FocusPlan(generatedAt: old, candidates: [
            .init(id: UUID(), title: "Essay", minutes: 60)
        ])

        XCTAssertEqual(OrbitLink.status(for: plan, provisioned: true, now: now), .stale(since: old))
        XCTAssertNotEqual(OrbitLink.status(for: plan, provisioned: true, now: now), .noPlan)
    }

    func testFreshAndEmptyMeansOrbitLookedAndFoundNothing() {
        let plan = OrbitBridge.FocusPlan(candidates: [])
        XCTAssertEqual(OrbitLink.status(for: plan, provisioned: true), .empty)
    }

    func testFreshWithTasksReportsHowMany() {
        let plan = OrbitBridge.FocusPlan(candidates: [
            .init(id: UUID(), title: "Essay", minutes: 60),
            .init(id: UUID(), title: "Pset", minutes: 90),
        ])
        XCTAssertEqual(OrbitLink.status(for: plan, provisioned: true), .ready(count: 2))
    }

    // MARK: Durations

    func testMinutesAreClampedToSomethingLockable() {
        // Apple rejects a DeviceActivity schedule under 15 minutes, so a
        // shorter estimate cannot arm the real shield.
        XCTAssertEqual(OrbitBridge.FocusCandidate.clamp(1), 15)
        XCTAssertEqual(OrbitBridge.FocusCandidate.clamp(14), 15)
        XCTAssertEqual(OrbitBridge.FocusCandidate.clamp(0), 15)
        XCTAssertEqual(OrbitBridge.FocusCandidate.clamp(-30), 15)
        // Four hours is already a bluff; past that it is a typo.
        XCTAssertEqual(OrbitBridge.FocusCandidate.clamp(600), 240)
        // Otherwise round to the 5s the duration slider moves in.
        XCTAssertEqual(OrbitBridge.FocusCandidate.clamp(47), 45)
        XCTAssertEqual(OrbitBridge.FocusCandidate.clamp(90), 90)
    }

    func testCandidateClampsOnTheWayIn() {
        let candidate = OrbitBridge.FocusCandidate(id: UUID(), title: "Essay", minutes: 3)
        XCTAssertEqual(candidate.minutes, 15)
    }

    // MARK: Freshness

    func testAPlanGoesStaleAfterHalfADay() {
        let now = Date()
        let fresh = OrbitBridge.FocusPlan(generatedAt: now.addingTimeInterval(-3600), candidates: [])
        let stale = OrbitBridge.FocusPlan(generatedAt: now.addingTimeInterval(-13 * 3600), candidates: [])

        XCTAssertTrue(fresh.isFresh(at: now))
        XCTAssertFalse(
            stale.isFresh(at: now),
            "Locking the phone against yesterday's priorities is worse than locking it against a generic goal."
        )
    }

    // MARK: Wire format

    /// Both apps decode what the other encodes, or the bridge is a no-op that
    /// reports success.
    func testPlanSurvivesARoundTripThroughJSON() throws {
        let id = UUID()
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let plan = OrbitBridge.FocusPlan(candidates: [
            .init(id: id, title: "Finish the problem set", minutes: 90, dueAt: due, project: "CS 340")
        ])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(
            OrbitBridge.FocusPlan.self, from: try encoder.encode(plan)
        )

        XCTAssertEqual(decoded.candidates.count, 1)
        XCTAssertEqual(decoded.candidates[0].id, id)
        XCTAssertEqual(decoded.candidates[0].title, "Finish the problem set")
        XCTAssertEqual(decoded.candidates[0].minutes, 90)
        XCTAssertEqual(decoded.candidates[0].project, "CS 340")
        XCTAssertEqual(decoded.candidates[0].dueAt, due)
    }

    /// `markedDone` exists so LOCKED can later offer "mark it done?" without a
    /// schema change. An older LOCKED writing a receipt without it must still
    /// decode in a newer Orbit.
    func testAReceiptWithoutMarkedDoneStillDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","taskID":"\(UUID().uuidString)","outcome":"caved",
         "servedSeconds":240,"startedAt":"2026-08-10T09:00:00Z","endedAt":"2026-08-10T09:04:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let receipt = try decoder.decode(
            OrbitBridge.SessionReceipt.self, from: Data(json.utf8)
        )
        XCTAssertNil(receipt.markedDone)
        XCTAssertEqual(receipt.outcome, .caved)
        XCTAssertEqual(receipt.servedSeconds, 240)
    }

    // MARK: The deep link

    func testStartURLRoundTrips() throws {
        let id = UUID()
        let url = try XCTUnwrap(OrbitBridge.startURL(taskID: id, minutes: 45))
        let request = try XCTUnwrap(OrbitBridge.parseStart(url))

        XCTAssertEqual(request.taskID, id)
        XCTAssertEqual(request.minutes, 45)
    }

    /// The URL is a pointer, not a payload. What you are working on is already
    /// in the shared container; putting it in a custom-scheme URL writes it
    /// into something the system logs and shows in the open-in prompt.
    func testStartURLCarriesNoTitle() throws {
        let url = try XCTUnwrap(OrbitBridge.startURL(taskID: UUID(), minutes: 60))
        let text = url.absoluteString

        XCTAssertFalse(text.contains("title"))
        XCTAssertEqual(url.scheme, "locked")
        XCTAssertEqual(url.host, "start")
        // Exactly two parameters, both opaque.
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.map(\.name).sorted(), ["minutes", "task"])
    }

    func testMalformedLinksAreRefusedRatherThanGuessed() {
        let cases = [
            "https://start?task=\(UUID().uuidString)",       // not our scheme
            "locked://stop?task=\(UUID().uuidString)",       // not our host
            "locked://start?task=garbage",                   // not a UUID
            "locked://start",                                // no task at all
            "locked://start?minutes=45",                     // minutes without a task
        ]
        for text in cases {
            let url = URL(string: text)
            XCTAssertNil(
                url.flatMap(OrbitBridge.parseStart),
                "\(text) should not have produced a start request"
            )
        }
    }

    func testAbsurdDurationsInALinkAreClampedNotHonoured() throws {
        let id = UUID()
        let url = try XCTUnwrap(URL(string: "locked://start?task=\(id.uuidString)&minutes=99999"))
        XCTAssertEqual(OrbitBridge.parseStart(url)?.minutes, 240)

        let missing = try XCTUnwrap(URL(string: "locked://start?task=\(id.uuidString)"))
        XCTAssertEqual(OrbitBridge.parseStart(missing)?.minutes, 60, "a link without a duration should default, not fail")
    }
}
