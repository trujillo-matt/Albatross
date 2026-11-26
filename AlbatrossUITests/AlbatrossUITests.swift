import XCTest

/// Opens a section of the app. A narrow screen has a tab bar; a wide one has a "Sections" menu button instead.
/// The splash plays for a few seconds first, so this waits for whichever appears.
@MainActor
private func openSection(_ name: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let menu = app.buttons["Sections"].firstMatch
    let tabButton = app.buttons[name].firstMatch
    let deadline = Date().addingTimeInterval(25)
    while !menu.exists && !tabButton.exists && Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
    if menu.exists {
        menu.tap()
        let item = app.buttons[name].firstMatch
        // The menu animates open; if the first tap landed too early, open it again once.
        if !item.waitForExistence(timeout: 3) { menu.tap() }
        XCTAssertTrue(item.waitForExistence(timeout: 5), "No \(name) in the sections menu", file: file, line: line)
        item.tap()
    } else {
        XCTAssertTrue(tabButton.exists, "No \(name) tab or sections menu", file: file, line: line)
        tabButton.tap()
    }
}

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

    /// Taps a round's card. In the stack the card lifts first and "Open scorecard" opens it; on a shelf the tap opens it.
    @MainActor
    private func openRound(containing course: String) {
        let cover = app.buttons.matching(NSPredicate(format: "label CONTAINS '\(course)'")).firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: 10))
        cover.tap()
        let open = app.buttons["Open scorecard"].firstMatch
        if open.waitForExistence(timeout: 3) { open.tap() }
    }

    @MainActor
    func testTabNavigation() throws {
        for name in ["Clubhouse", "Stats", "Profile", "Scorecards"] {
            openSection(name, in: app)
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5), "\(name) did not appear")
        }
    }

    @MainActor
    func testNewRoundSheetOpensAndCancels() throws {
        openSection("Scorecards", in: app)
        app.buttons["New Round"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["New Round"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertFalse(app.navigationBars["New Round"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testEnterScoreInSeededRound() throws {
        openSection("Scorecards", in: app)

        // Open the seeded booklet from its card.
        openRound(containing: "UI Test Course")

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

    /// Tapping a card lifts it and shows its details; Close puts it back.
    @MainActor
    func testCardLiftsAndCloses() throws {
        openSection("Scorecards", in: app)
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'UI Test Course'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        // The card's details and actions appear.
        XCTAssertTrue(app.buttons["Open scorecard"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Edit"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Front nine"].firstMatch.exists)

        // Close drops it back into the stack.
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Open scorecard"].firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 6), .completed)
    }

    /// The strip offers Triple and More, a double tap writes only one hole, and Undo takes a score back.
    @MainActor
    func testScoreEntryOptionsDoubleTapAndUndo() throws {
        openSection("Scorecards", in: app)
        openRound(containing: "UI Test Course")
        if app.staticTexts["Swipe to open"].waitForExistence(timeout: 3) {
            app.swipeLeft()
        }

        func row(_ hole: Int) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Hole \(hole),'")).firstMatch
        }
        func scoreValue(_ hole: Int) -> String { (row(hole).value as? String) ?? "" }

        let holeFive = row(5)
        XCTAssertTrue(holeFive.waitForExistence(timeout: 8))
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: holeFive)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 6), .completed, "Hole 5 is not on screen")
        holeFive.tap()

        // Results above a double bogey are on the strip.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Triple'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["More scores"].firstMatch.exists)

        // A double tap on a result writes hole 5 and leaves hole 6 empty.
        let par = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Par '")).firstMatch
        XCTAssertTrue(par.waitForExistence(timeout: 5))
        par.doubleTap()
        XCTAssertNotEqual(scoreValue(5), "No score", "Hole 5 should have a score")
        XCTAssertEqual(scoreValue(6), "No score", "A double tap must not write the next hole")

        // Undo takes hole 5's score back.
        let undo = app.buttons["Undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertEqual(scoreValue(5), "No score")
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
        openSection("Tournaments", in: app)

        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Reynolds Cup'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "The demo tournament is not on the shelf")
        card.tap()

        XCTAssertTrue(app.navigationBars["Reynolds Cup"].waitForExistence(timeout: 8), app.debugDescription)
    }

    /// Opens the live match and starts its scorecard: the booklet, not the old scorecard.
    @MainActor
    func testDemoMatchOpensBooklet() throws {
        openSection("Tournaments", in: app)
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
        openSection("Profile", in: app)
        let signIn = app.buttons["Sign in to sync"].firstMatch
        XCTAssertTrue(signIn.waitForExistence(timeout: 8))
        signIn.tap()

        // And it is back at the sign-in screen.
        XCTAssertTrue(app.buttons["Continue without an account"].firstMatch.waitForExistence(timeout: 10))
    }
}
