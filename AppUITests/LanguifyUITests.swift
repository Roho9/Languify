import XCTest

/// End-to-end UI journeys that don't need a microphone or the AI backend.
/// Each launch uses `-ui-testing`, which resets preferences and uses an
/// in-memory store.
final class LanguifyUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    /// Journey A: first-time setup without an account.
    func testOnboardingWithoutAccount() {
        snapshot("01-welcome")
        tapContinue()
        app.buttons["language.ml"].tap()
        snapshot("02-language")
        tapContinue() // abilities
        snapshot("03-abilities")
        tapContinue() // goals
        tapContinue() // display
        snapshot("04-display")
        tapContinue() // responses
        snapshot("05-responses")
        tapContinue() // privacy
        snapshot("06-privacy")
        let consent = app.switches["onboarding.cloudConsent"]
        XCTAssertTrue(consent.waitForExistence(timeout: 2))
        tapContinue() // setup
        snapshot("07-setup")
        app.buttons["Start using Languify"].tap()

        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.start"].exists)
        snapshot("08-home")
    }

    func testTabsAndLiveRewindIdleState() {
        completeOnboarding()
        app.tabBars.buttons["Rewind"].tap()
        XCTAssertTrue(app.buttons["rewind.start"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Not listening"].exists)
        snapshot("10-rewind-idle")
        app.tabBars.buttons["Learn"].tap()
        XCTAssertTrue(app.staticTexts["Flashcards"].waitForExistence(timeout: 3))
        snapshot("11-learn")
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 3))
        snapshot("12-profile")
        let privacy = app.buttons["Privacy & consent"]
        for _ in 0..<5 where !privacy.isHittable { app.swipeUp() }
        privacy.tap()
        XCTAssertTrue(app.switches["Allow AI explanations"].waitForExistence(timeout: 3) || app.staticTexts["Allow AI explanations"].exists)
        snapshot("13-privacy")
    }

    /// Journey G (manual path): add a word, find it, review it with flashcards.
    func testAddWordSearchAndReview() {
        completeOnboarding()
        app.tabBars.buttons["Vocabulary"].tap()
        snapshot("20-vocab-empty")
        app.buttons["Add a word yourself"].tap()
        let translit = app.textFields["Transliteration (e.g. madi)"]
        XCTAssertTrue(translit.waitForExistence(timeout: 3))
        translit.tap()
        translit.typeText("madi")
        let meaning = app.textFields["English meaning"]
        meaning.tap()
        meaning.typeText("laziness")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["madi"].waitForExistence(timeout: 3))
        snapshot("21-vocab-list")

        app.staticTexts["madi"].tap()
        XCTAssertTrue(app.staticTexts["Meaning: laziness"].waitForExistence(timeout: 3))
        snapshot("22-vocab-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["Practice"].tap()
        XCTAssertTrue(app.buttons["flashcard.reveal"].waitForExistence(timeout: 3))
        snapshot("23-flashcard-front")
        app.buttons["flashcard.reveal"].tap()
        XCTAssertTrue(app.buttons["grade.Good"].waitForExistence(timeout: 3))
        snapshot("24-flashcard-back")
        app.buttons["grade.Good"].tap()
        XCTAssertTrue(app.staticTexts["Session complete"].waitForExistence(timeout: 3))
    }

    func testDeleteWordFromJournal() {
        completeOnboarding()
        app.tabBars.buttons["Vocabulary"].tap()
        app.buttons["Add a word yourself"].tap()
        app.textFields["Transliteration (e.g. madi)"].tap()
        app.textFields["Transliteration (e.g. madi)"].typeText("vellam")
        app.textFields["English meaning"].tap()
        app.textFields["English meaning"].typeText("water")
        app.buttons["Save"].tap()
        let cell = app.staticTexts["vellam"]
        XCTAssertTrue(cell.waitForExistence(timeout: 3))
        app.cells.containing(.staticText, identifier: "vellam").firstMatch.swipeLeft()
        // A long swipe deletes immediately; a short one reveals the button.
        let delete = app.buttons["Delete"]
        if delete.waitForExistence(timeout: 1) { delete.tap() }
        XCTAssertTrue(app.staticTexts["No words yet"].waitForExistence(timeout: 3))
    }

    // MARK: Helpers

    private func tapContinue() {
        let button = app.buttons["onboarding.continue"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
    }

    private func completeOnboarding() {
        for _ in 0..<7 { tapContinue() }
        app.buttons["Start using Languify"].tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
    }

    private func snapshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
