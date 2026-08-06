import XCTest
@testable import Locked

/// The session state machine: streaks, rollover, folding, completion.
///
/// `AppState` takes an injected clock and storage URL, so these run instantly
/// against a temp file and can cross a midnight or a week boundary at will.
@MainActor
final class AppStateTests: XCTestCase {
    private var storage: URL!
    private var moment: Date!

    /// Wednesday 6 August 2026, midday UTC.
    private static let start = Date(timeIntervalSince1970: 1_785_412_800)

    override func setUp() async throws {
        storage = FileManager.default.temporaryDirectory
            .appendingPathComponent("locked-test-\(UUID().uuidString).json")
        moment = Self.start
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: storage)
    }

    private func makeState() -> AppState {
        AppState(
            service: OfflinePodService(),
            shield: ShieldManager(),
            clock: { self.moment },
            storageURL: storage,
            startTimer: false
        )
    }

    private func advance(minutes: Double) {
        moment = moment.addingTimeInterval(minutes * 60)
    }

    private func advance(days: Int) {
        moment = moment.addingTimeInterval(Double(days) * 86_400)
    }

    // MARK: Completing

    func testCompletingASessionCreditsThePlannedTimeAndBanksMinutes() {
        let state = makeState()
        state.data.me.todaySeconds = 0
        state.data.me.weeklySeconds = 0
        state.data.me.bankedMinutes = 0
        state.data.me.streak = 0

        state.startSession(goal: "Finish the problem set", minutes: 90, stake: .post)
        XCTAssertNotNil(state.session)

        advance(minutes: 90)
        state.completeSession()

        XCTAssertNil(state.session, "a completed session is over")
        XCTAssertEqual(state.data.me.todaySeconds, 90 * 60)
        XCTAssertEqual(state.data.me.weeklySeconds, 90 * 60)
        XCTAssertEqual(state.data.me.streak, 1)
        XCTAssertEqual(state.data.me.bankedMinutes, 18, "a 90 minute lock banks 18 minutes of scroll")
        XCTAssertEqual(state.data.history.first?.outcome, .completed)
    }

    func testTwoSessionsInOneDayOnlyCountAsOneStreakDay() {
        let state = makeState()
        state.data.me.streak = 0

        state.startSession(goal: "First", minutes: 30, stake: .post)
        advance(minutes: 30)
        state.completeSession()

        advance(minutes: 60)
        state.startSession(goal: "Second", minutes: 30, stake: .post)
        advance(minutes: 30)
        state.completeSession()

        XCTAssertEqual(state.data.me.streak, 1, "a streak counts days, not sessions")
        XCTAssertEqual(state.data.me.todaySeconds, 60 * 60)
    }

    func testTheStreakGrowsOnConsecutiveDays() {
        let state = makeState()
        state.data.me.streak = 0

        for day in 0..<3 {
            if day > 0 { advance(days: 1) }
            state.startSession(goal: "Day \(day)", minutes: 30, stake: .post)
            advance(minutes: 30)
            state.completeSession()
        }

        XCTAssertEqual(state.data.me.streak, 3)
    }

    // MARK: Folding

    func testFoldingCreditsTimeServedButBurnsTheStreak() {
        let state = makeState()
        state.data.me.streak = 9
        state.data.me.todaySeconds = 0
        state.data.me.cavesThisWeek = 0

        state.startSession(goal: "Write the essay", minutes: 60, stake: .streak)
        advance(minutes: 12)
        state.cave()

        XCTAssertNil(state.session)
        XCTAssertEqual(state.data.me.todaySeconds, 12 * 60, "time actually served still counts")
        XCTAssertEqual(state.data.me.streak, 0)
        XCTAssertEqual(state.data.me.cavesThisWeek, 1)
        XCTAssertEqual(state.data.history.first?.outcome, .caved)
        XCTAssertEqual(state.route, .pod, "folding drops you in front of the pod")

        let failure = state.data.feed.first { $0.isFailure && $0.isMe }
        XCTAssertNotNil(failure, "folding publishes to the feed")
    }

    func testFoldingImmediatelyCreditsNothing() {
        let state = makeState()
        state.data.me.todaySeconds = 0

        state.startSession(goal: "Nope", minutes: 60, stake: .post)
        state.cave()

        XCTAssertEqual(state.data.me.todaySeconds, 0)
    }

    // MARK: Rollover

    func testANewDayClearsTodayButKeepsTheWeek() {
        let state = makeState()
        state.startSession(goal: "Yesterday's work", minutes: 60, stake: .post)
        advance(minutes: 60)
        state.completeSession()
        XCTAssertEqual(state.data.me.todaySeconds, 60 * 60)

        advance(days: 1)
        state.refresh()

        XCTAssertEqual(state.data.me.todaySeconds, 0)
        XCTAssertEqual(state.data.me.weeklySeconds, 60 * 60, "the week survives a new day")
    }

    func testANewWeekClearsTheWeeklyTotals() {
        let state = makeState()
        state.data.members = [
            PodMember(name: "Priya", initials: "PR", note: "", inPod: true, weeklySeconds: 5000)
        ]
        state.startSession(goal: "Last week", minutes: 60, stake: .post)
        advance(minutes: 60)
        state.completeSession()
        state.data.me.cavesThisWeek = 3

        advance(days: 8)
        state.refresh()

        XCTAssertEqual(state.data.me.weeklySeconds, 0)
        XCTAssertEqual(state.data.me.cavesThisWeek, 0)
        XCTAssertTrue(state.data.members.allSatisfy { $0.weeklySeconds == 0 })
    }

    func testAStreakSurvivesOneNightButNotTwo() {
        let state = makeState()
        state.data.me.streak = 0

        state.startSession(goal: "Monday", minutes: 30, stake: .post)
        advance(minutes: 30)
        state.completeSession()
        XCTAssertEqual(state.data.me.streak, 1)

        // One night off: still alive.
        advance(days: 1)
        state.refresh()
        XCTAssertEqual(state.data.me.streak, 1)

        // Two nights off: gone.
        advance(days: 1)
        state.refresh()
        XCTAssertEqual(state.data.me.streak, 0)
    }

    // MARK: Sessions that end while the app is dead

    func testASessionThatRanOutWhileClosedIsSettledOnLaunch() {
        let first = makeState()
        first.startSession(goal: "Interrupted", minutes: 30, stake: .post)
        first.saveNow()

        // The app dies, time passes, it comes back.
        advance(minutes: 45)
        let second = makeState()

        XCTAssertNil(second.session, "the clock ran out, so the session is closed")
        XCTAssertEqual(second.data.me.todaySeconds, 30 * 60)
        XCTAssertNil(second.completed, "settling silently shouldn't pop the celebration")
    }

    func testStateSurvivesARelaunch() {
        let first = makeState()
        first.data.me.name = "Aaryan"
        first.data.me.streak = 4
        first.data.podName = "Fifth Floor"
        first.saveNow()

        let second = makeState()
        XCTAssertEqual(second.data.me.name, "Aaryan")
        XCTAssertEqual(second.data.me.streak, 4)
        XCTAssertEqual(second.data.podName, "Fifth Floor")
    }

    // MARK: The pod's verdict

    func testAnApprovedVerdictOpensABreakWithoutStoppingTheClock() {
        let state = makeState()
        state.startSession(goal: "Grind", minutes: 60, stake: .post)
        let endsAt = state.session?.endsAt

        let request = UnlockRequest(
            requesterName: "Sam", requesterInitials: "SM", isOutgoing: true,
            reason: "My mom is calling", goal: "Grind",
            remainingAtRequest: 3_000, streak: 1, cavesThisWeek: 0,
            createdAt: moment
        )
        state.applyVerdict(.approved(by: "Maya", minutes: 5), for: request.id)

        XCTAssertTrue(state.onBreak)
        XCTAssertEqual(state.session?.endsAt, endsAt, "a break doesn't extend the session")
        XCTAssertEqual(state.breakRemaining, 5 * 60)
    }

    func testADeniedVerdictChangesNothingAboutTheSession() {
        let state = makeState()
        state.startSession(goal: "Grind", minutes: 60, stake: .post)
        let request = UnlockRequest(
            requesterName: "Sam", requesterInitials: "SM", isOutgoing: true,
            reason: "bored", goal: "Grind",
            remainingAtRequest: 3_000, streak: 1, cavesThisWeek: 0,
            createdAt: moment
        )

        state.applyVerdict(.denied(by: "Priya", quip: "no."), for: request.id)

        XCTAssertFalse(state.onBreak)
        XCTAssertNotNil(state.session)
    }

    // MARK: Standings

    func testStandingsRankMeAgainstThePod() {
        let state = makeState()
        state.data.members = [
            PodMember(name: "Priya", initials: "PR", note: "", inPod: true, weeklySeconds: 5000),
            PodMember(name: "Dev", initials: "DV", note: "", inPod: true, weeklySeconds: 100),
        ]
        state.data.me.weeklySeconds = 1000

        let rows = state.standings
        XCTAssertEqual(rows.map(\.name), ["Priya", "You", "Dev"])
        XCTAssertEqual(state.myPodRank, 2)
        XCTAssertEqual(state.podSize, 3)
    }
}
