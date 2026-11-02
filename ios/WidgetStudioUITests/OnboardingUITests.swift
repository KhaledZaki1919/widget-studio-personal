import XCTest

/// M6: the introduction shows on first launch, pages through to the Library, and can be skipped.
final class OnboardingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingOnboarding", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", language == "ar" ? "ar_EG" : "en_US"]
        app.launch()
        return app
    }

    @MainActor
    func testPagesThroughToTheLibraryInArabic() {
        let app = launch(language: "ar")
        let next = app.buttons["ax.onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15), "introduction not shown on first launch")
        next.tap()
        XCTAssertTrue(app.buttons["ax.onboarding.next"].waitForExistence(timeout: 5))
        app.buttons["ax.onboarding.next"].tap()
        // M6.1: the permissions page, with an Allow button for each permission (skipped here:
        // the system prompts can't be scripted).
        XCTAssertTrue(app.descendants(matching: .any)["ax.permissions.location"].waitForExistence(timeout: 5), "permissions page missing")
        XCTAssertTrue(app.buttons["ax.permissions.allow"].firstMatch.exists, "no Allow button on the permissions page")
        app.buttons["ax.onboarding.next"].tap()
        let start = app.buttons["ax.onboarding.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "last page has no start button")
        XCTAssertFalse(app.buttons["ax.onboarding.skip"].exists, "skip shown on the last page")
        start.tap()
        XCTAssertTrue(app.buttons["ax.library.create"].waitForExistence(timeout: 10), "Library not shown after the introduction")
    }

    @MainActor
    func testSkipGoesToTheLibraryInEnglish() {
        let app = launch(language: "en")
        let skip = app.buttons["ax.onboarding.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 15))
        skip.tap()
        XCTAssertTrue(app.buttons["ax.library.create"].waitForExistence(timeout: 10))
    }
}
