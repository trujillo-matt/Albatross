import XCTest

/// These run against a Debug build, which skips sign-in and can seed one empty round.
/// XCUITest cannot fold the device: set the posture in Device Hub before running.
final class AlbatrossUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uitest-seed-round"]
        app.launch()
    }

    /// The splash plays for a few seconds before the tabs appear.
    private func tab(_ name: String) -> XCUIElement {
        app.buttons[name].firstMatch
    }

    @MainActor
    func testTabNavigation() throws {
        XCTAssertTrue(tab("Scorecards").waitForExistence(timeout: 20))
        for name in ["Clubhouse", "Stats", "Profile", "Scorecards"] {
            tab(name).tap()
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5), "\(name) did not appear")
        }
    }

    @MainActor
    func testNewRoundSheetOpensAndCancels() throws {
        XCTAssertTrue(tab("Scorecards").waitForExistence(timeout: 20))
        tab("Scorecards").tap()
        app.buttons["New Round"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Round"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertFalse(app.navigationBars["New Round"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testEnterScoreInSeededRound() throws {
        XCTAssertTrue(tab("Scorecards").waitForExistence(timeout: 20))
        tab("Scorecards").tap()

        // Open the seeded booklet from its cover on the shelf.
        let cover = app.buttons.matching(NSPredicate(format: "label CONTAINS 'UI Test Course'")).firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: 10))
        cover.tap()

        // On the closed Duo the cover is page one: swipe to open it. The open Duo shows the pages directly.
        let hole = app.buttons["Hole 1, par 4"].firstMatch
        if app.staticTexts["Swipe to open"].waitForExistence(timeout: 3) {
            app.swipeLeft()
        }
        XCTAssertTrue(hole.waitForExistence(timeout: 5))
        // The page is still settling after the swipe, so wait until the row can be tapped.
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: hole)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 6), .completed, "Hole 1 is not on screen")
        hole.tap()

        // The pencil strip writes the score in one tap: "Par 4" for a par 4.
        let par = app.buttons["Par 4"].firstMatch
        XCTAssertTrue(par.waitForExistence(timeout: 5))
        par.tap()

        // The button label is the visible proof that one hole was recorded (the strip's Finish button).
        let finish = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '1/18'")).firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 8), "Finish Round (1/18) not found\n\(app.debugDescription)")
    }
}

/// Runs against the made-up tournament that a Debug build shows with `-demo-tournament`.
final class AlbatrossTournamentUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-demo-tournament"]
        app.launch()
    }

    @MainActor
    func testDemoTournamentOpens() throws {
        XCTAssertTrue(app.buttons["Tournaments"].firstMatch.waitForExistence(timeout: 20))
        app.buttons["Tournaments"].firstMatch.tap()

        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Reynolds Cup'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "The demo tournament is not on the shelf")
        card.tap()

        XCTAssertTrue(app.navigationBars["Reynolds Cup"].waitForExistence(timeout: 8), app.debugDescription)
    }

    /// Opens the live match and starts its scorecard: the booklet, not the old scorecard.
    @MainActor
    func testDemoMatchOpensBooklet() throws {
        XCTAssertTrue(app.buttons["Tournaments"].firstMatch.waitForExistence(timeout: 20))
        app.buttons["Tournaments"].firstMatch.tap()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Reynolds Cup'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.navigationBars["Reynolds Cup"].waitForExistence(timeout: 8))

        let match = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Match 3' OR label CONTAINS 'Matchup 3'")).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 5), app.debugDescription)
        match.tap()

        // A match that was started on an earlier run says "Resume" instead of "Enter".
        let enter = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Enter Scorecard' OR label CONTAINS 'Resume Scorecard'")).firstMatch
        XCTAssertTrue(enter.waitForExistence(timeout: 8), app.debugDescription)
        enter.tap()

        // The booklet's cover says to swipe; the pencil strip appears once the card is open.
        XCTAssertTrue(app.staticTexts["Swipe to open"].waitForExistence(timeout: 10) || app.buttons["Hole 1, par 4"].firstMatch.waitForExistence(timeout: 2), app.debugDescription)
    }
}

/// The sign-in screen, with its way in that needs no account.
final class AlbatrossSignInUITests: XCTestCase {

    @MainActor
    func testContinueWithoutAnAccountThenSignInLater() throws {
        let app = XCUIApplication()
        // -show-sign-in starts from a phone that has not chosen yet.
        app.launchArguments += ["-show-sign-in"]
        app.launch()

        let continueButton = app.buttons["Continue without an account"].firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 25), "The sign-in screen did not appear")
        // The splash fades into the sign-in screen; let that finish so the tap lands on the screen, not the fade.
        Thread.sleep(forTimeInterval: 2)
        continueButton.tap()

        // In the app without an account: the tabs are there and Profile offers sign-in.
        XCTAssertTrue(app.buttons["Profile"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["Profile"].firstMatch.tap()
        let signIn = app.buttons["Sign in to sync"].firstMatch
        XCTAssertTrue(signIn.waitForExistence(timeout: 8))
        signIn.tap()

        // And it is back at the sign-in screen.
        XCTAssertTrue(app.buttons["Continue without an account"].firstMatch.waitForExistence(timeout: 10))
    }
}
