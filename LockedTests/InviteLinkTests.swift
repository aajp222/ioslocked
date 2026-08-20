import XCTest
@testable import Locked

/// Invite links. Pure and total, so every branch is reachable here rather than
/// only from a phone with the right thing pasted into it.
final class InviteLinkTests: XCTestCase {

    func testRoundTrip() throws {
        let url = try XCTUnwrap(InviteLink.url(code: "ABC234"))
        XCTAssertEqual(url.absoluteString, "locked://join?code=ABC234")
        XCTAssertEqual(InviteLink.code(from: url), "ABC234")
    }

    func testLowercaseAndWhitespaceAreForgiven() {
        XCTAssertEqual(InviteLink.normalise(" abc234 "), "ABC234")
        XCTAssertEqual(
            InviteLink.code(from: URL(string: "locked://join?code=abc234")!),
            "ABC234",
            "someone retyping a link by hand should not be punished for shift"
        )
    }

    /// Validated on the way in so a link cannot smuggle arbitrary text into the
    /// join field, and so an obviously wrong code never spends one of the ten
    /// attempts an hour the server allows.
    func testMalformedCodesAreRefusedRatherThanGuessed() {
        for bad in ["", "ABC", "ABC2345", "ABC-23", "ABC 23", "ABCDEI", "ABCDE0", "ABCDE1"] {
            XCTAssertNil(InviteLink.normalise(bad), "\(bad) should not be accepted")
        }
    }

    func testAmbiguousLettersAreNotInTheAlphabet() {
        // The server draws codes from an alphabet with I, O, 0 and 1 removed
        // because people misread them. Accepting them here would produce codes
        // that cannot exist and a 404 that looks like a server fault.
        for ambiguous in "IO01" {
            XCTAssertFalse(InviteLink.alphabet.contains(ambiguous))
        }
    }

    func testForeignLinksAreIgnored() {
        for bad in [
            "https://join?code=ABC234",          // not our scheme
            "locked://start?code=ABC234",        // the Orbit hand-off, not an invite
            "locked://join",                     // no code
            "locked://join?code=NOPE",           // too short
            "locked://join?invite=ABC234",       // wrong parameter
        ] {
            let url = URL(string: bad)
            XCTAssertNil(url.flatMap(InviteLink.code), "\(bad) should not produce a code")
        }
    }

    func testShareTextCarriesBothWaysIn() throws {
        let text = try XCTUnwrap(InviteLink.shareText(code: "ABC234", podName: "Fifth Floor"))
        XCTAssertTrue(text.contains("locked://join?code=ABC234"))
        // The code in plain text as well: a link is useless to somebody who
        // has not installed the app yet, and that is everyone being invited.
        XCTAssertTrue(text.contains("ABC234"))
        XCTAssertTrue(text.contains("Fifth Floor"))
    }

    func testShareTextSurvivesAMissingPodName() throws {
        let text = try XCTUnwrap(InviteLink.shareText(code: "ABC234", podName: nil))
        XCTAssertTrue(text.contains("my pod"))
        let blank = try XCTUnwrap(InviteLink.shareText(code: "ABC234", podName: "   "))
        XCTAssertTrue(blank.contains("my pod"), "whitespace is not a pod name")
    }

    func testNoLinkForAnImpossibleCode() {
        XCTAssertNil(InviteLink.url(code: "nope"))
        XCTAssertNil(InviteLink.shareText(code: "nope", podName: "Fifth Floor"))
    }
}
