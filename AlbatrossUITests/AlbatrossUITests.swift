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
        XCTAssertTrue(hole.isHittable, "Hole 1 is not on screen")
        hole.tap()

        // Number pad: a single digit waits, and tapping the large figure commits it.
        let four = app.buttons["4"].firstMatch
        XCTAssertTrue(four.waitForExistence(timeout: 5))
        four.tap()
        let figure = app.staticTexts["4"].firstMatch
        XCTAssertTrue(figure.waitForExistence(timeout: 3))
        figure.tap()

        // The button label is the visible proof that one hole was recorded.
        let finish = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '1/18'")).firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 8), "Finish Round (1/18) not found\n\(app.debugDescription)")
    }
}
