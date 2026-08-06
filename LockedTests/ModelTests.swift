import XCTest
@testable import Locked

/// The small pure things every screen depends on: clock formatting and the
/// session's own arithmetic.
final class ModelTests: XCTestCase {

    // MARK: Formatting

    func testClockDropsHoursUntilThereAreSome() {
        XCTAssertEqual(Fmt.clock(0), "00:00")
        XCTAssertEqual(Fmt.clock(59), "00:59")
        XCTAssertEqual(Fmt.clock(90), "01:30")
        XCTAssertEqual(Fmt.clock(3_599), "59:59")
        XCTAssertEqual(Fmt.clock(3_600), "1:00:00")
        XCTAssertEqual(Fmt.clock(5_352), "1:29:12")
    }

    func testClockNeverShowsNegativeTime() {
        XCTAssertEqual(Fmt.clock(-10), "00:00")
    }

    func testSpanReadsLikeAPersonWroteIt() {
        XCTAssertEqual(Fmt.span(45), "45s")
        XCTAssertEqual(Fmt.span(60), "1m")
        XCTAssertEqual(Fmt.span(24 * 60), "24m")
        XCTAssertEqual(Fmt.span(3_600), "1h")
        XCTAssertEqual(Fmt.span(90 * 60), "1h 30m")
        XCTAssertEqual(Fmt.span(9_600), "2h 40m")
    }

    func testStandingsAlwaysShowBothUnits() {
        XCTAssertEqual(Fmt.standings(0), "0h 00m")
        XCTAssertEqual(Fmt.standings(50_700), "14h 05m")
    }

    func testOrdinalsHandleTheTeens() {
        XCTAssertEqual(Fmt.ordinal(1), "st")
        XCTAssertEqual(Fmt.ordinal(2), "nd")
        XCTAssertEqual(Fmt.ordinal(3), "rd")
        XCTAssertEqual(Fmt.ordinal(4), "th")
        XCTAssertEqual(Fmt.ordinal(11), "th")
        XCTAssertEqual(Fmt.ordinal(12), "th")
        XCTAssertEqual(Fmt.ordinal(13), "th")
        XCTAssertEqual(Fmt.ordinal(21), "st")
    }

    func testNameListsReadNaturally() {
        XCTAssertEqual(Fmt.names([]), "Nobody")
        XCTAssertEqual(Fmt.names(["Maya"]), "Maya")
        XCTAssertEqual(Fmt.names(["Maya", "Priya"]), "Maya and Priya")
        XCTAssertEqual(Fmt.names(["Maya", "Priya", "Dev"]), "Maya, Priya and Dev")
        XCTAssertEqual(Fmt.names(["Maya", "Priya", "Dev", "Jonah"]), "Maya and 3 others")
    }

    // MARK: Session arithmetic

    private func session(minutes: Int, from start: Date) -> Session {
        Session(
            goal: "Work",
            plannedMinutes: minutes,
            startedAt: start,
            endsAt: start.addingTimeInterval(Double(minutes) * 60),
            blocked: ["Instagram"],
            stake: .post
        )
    }

    func testRemainingCountsDownAndStopsAtZero() {
        let start = Date(timeIntervalSince1970: 1_785_412_800)
        let subject = session(minutes: 60, from: start)

        XCTAssertEqual(subject.remaining(at: start), 3_600)
        XCTAssertEqual(subject.remaining(at: start.addingTimeInterval(1_800)), 1_800)
        XCTAssertEqual(subject.remaining(at: start.addingTimeInterval(3_600)), 0)
        XCTAssertEqual(subject.remaining(at: start.addingTimeInterval(99_999)), 0, "never negative")
    }

    func testElapsedIsCappedAtTheSessionLength() {
        let start = Date(timeIntervalSince1970: 1_785_412_800)
        let subject = session(minutes: 30, from: start)

        XCTAssertEqual(subject.elapsed(at: start), 0)
        XCTAssertEqual(subject.elapsed(at: start.addingTimeInterval(600)), 600)
        XCTAssertEqual(subject.elapsed(at: start.addingTimeInterval(99_999)), 1_800)
    }

    func testProgressRunsZeroToOne() {
        let start = Date(timeIntervalSince1970: 1_785_412_800)
        let subject = session(minutes: 60, from: start)

        XCTAssertEqual(subject.progress(at: start), 0, accuracy: 0.001)
        XCTAssertEqual(subject.progress(at: start.addingTimeInterval(1_800)), 0.5, accuracy: 0.001)
        XCTAssertEqual(subject.progress(at: start.addingTimeInterval(7_200)), 1, accuracy: 0.001)
    }

    func testBreaksExpire() {
        let start = Date(timeIntervalSince1970: 1_785_412_800)
        var subject = session(minutes: 60, from: start)
        subject.breakUntil = start.addingTimeInterval(300)

        XCTAssertTrue(subject.onBreak(at: start))
        XCTAssertTrue(subject.onBreak(at: start.addingTimeInterval(299)))
        XCTAssertFalse(subject.onBreak(at: start.addingTimeInterval(301)))
    }

    // MARK: Requests

    func testARequestDiesAfterItsLifetime() {
        let request = UnlockRequest(
            requesterName: "Sam", requesterInitials: "SM", isOutgoing: false,
            reason: "bored", goal: "Work", remainingAtRequest: 600,
            streak: 1, cavesThisWeek: 0,
            createdAt: Date().addingTimeInterval(-120), lifetime: 60
        )
        XCTAssertEqual(request.secondsLeft, 0)
    }

    func testAFreshRequestHasTimeOnIt() {
        let request = UnlockRequest(
            requesterName: "Sam", requesterInitials: "SM", isOutgoing: false,
            reason: "bored", goal: "Work", remainingAtRequest: 600,
            streak: 1, cavesThisWeek: 0,
            createdAt: Date(), lifetime: 60
        )
        XCTAssertGreaterThan(request.secondsLeft, 50)
    }

    // MARK: Global rank

    func testGlobalRankImprovesWithHoursLogged() {
        var profile = Profile()
        profile.weeklySeconds = 0
        let idle = profile.globalRank

        profile.weeklySeconds = 8 * 3_600 + 15 * 60
        let busy = profile.globalRank

        XCTAssertLessThan(busy, idle, "more hours means a better rank")
        XCTAssertLessThanOrEqual(profile.globalPercentile, 5, "8h should land near the top")
    }
}
