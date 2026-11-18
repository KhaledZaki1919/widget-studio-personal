import XCTest

/// Simulator smoke test (brief §9): the app launches in both languages and Diagnostics opens.
final class SmokeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func launch(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        // -uiTesting: start without saved designs.
        app.launchArguments = ["-uiTesting", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "ar" ? "ar_EG" : "en_US"]
        app.launch()
        return app
    }

    /// Diagnostics is hidden (M6): Settings → long-press the version row.
    @MainActor
    func openDiagnostics(_ app: XCUIApplication) {
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 15), "tab bar not found")
        tabs.buttons.element(boundBy: 3).tap()
        let version = app.descendants(matching: .any)["ax.settings.version"]
        for _ in 0..<12 where !(version.exists && version.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(version.waitForExistence(timeout: 5), "version row not found in Settings")
        version.press(forDuration: 1.2)
    }

    @MainActor
    private func opensDiagnostics(language: String) {
        let app = launch(language: language)
        openDiagnostics(app)
        XCTAssertTrue(app.collectionViews["ax.diag.list"].waitForExistence(timeout: 10))
        // List cells exist only on screen, so scroll down to the App Group button.
        let write = app.buttons["ax.diag.writeValue"]
        // Signing sections (app + widget) sit above it since ADR-012.
        for _ in 0..<14 where !write.exists {
            app.collectionViews["ax.diag.list"].swipeUp()
        }
        XCTAssertTrue(write.waitForExistence(timeout: 5))
        write.tap()
    }

    /// The library filters by category and opens a template's detail with every supported size.
    @MainActor
    private func browsesLibrary(language: String) {
        let app = launch(language: language)
        let chip = app.buttons["ax.library.chip.prayer"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15), "prayer chip not found")
        chip.tap()
        let template = app.buttons["ax.library.template.mono.prayer.day"]
        XCTAssertTrue(template.waitForExistence(timeout: 10), "prayer-day template not found after the chip")
        // Other categories are hidden while a chip is selected.
        XCTAssertFalse(app.buttons["ax.library.template.mono.clock.analog"].exists, "time templates still shown")
        template.tap()
        let medium = app.descendants(matching: .any)["ax.detail.preview.medium"]
        XCTAssertTrue(medium.waitForExistence(timeout: 10), "medium preview missing in detail")
        XCTAssertTrue(app.descendants(matching: .any)["ax.detail.preview.large"].exists, "large preview missing in detail")
        XCTAssertFalse(app.descendants(matching: .any)["ax.detail.preview.small"].exists, "small preview shown for a medium template")
    }

    /// M3: Customize a template, rename it, save, and find it in My widgets.
    @MainActor
    private func customizesAndSaves(language: String, name: String) {
        let app = launch(language: language)
        let chip = app.buttons["ax.library.chip.weather"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15), "weather chip not found")
        chip.tap()
        let template = app.buttons["ax.library.template.mono.weather.forecast"]
        XCTAssertTrue(template.waitForExistence(timeout: 10), "forecast template not found")
        template.tap()
        let customize = app.buttons["ax.detail.customize"]
        XCTAssertTrue(customize.waitForExistence(timeout: 10), "Customize button not found")
        customize.tap()

        let field = app.textFields["ax.editor.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "name field not found in the editor")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        field.typeText(name)
        let save = app.buttons["ax.editor.save"]
        XCTAssertTrue(save.isEnabled, "Save is disabled for a fresh design")
        save.tap()

        // Save switches to My widgets.
        let row = app.descendants(matching: .any).matching(identifier: "ax.mywidgets.design").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "saved design not in My widgets")
        XCTAssertTrue(row.label.contains(name), "row label is \(row.label)")
        XCTAssertFalse(app.descendants(matching: .any)["ax.mywidgets.empty"].exists, "empty state still shown")
    }

    /// M4: the Settings tab shows units, prayer method, step goal and the permissions.
    @MainActor
    func testSettingsTabInArabic() {
        let app = launch(language: "ar")
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 15), "tab bar not found")
        tabs.buttons.element(boundBy: 3).tap()
        XCTAssertTrue(app.descendants(matching: .any)["ax.settings.units"].waitForExistence(timeout: 10), "units picker missing")
        XCTAssertTrue(app.descendants(matching: .any)["ax.settings.method"].exists, "prayer method missing")
        XCTAssertTrue(app.descendants(matching: .any)["ax.settings.stepGoal"].exists, "step goal missing")
    }

    @MainActor
    func testCustomizeSaveShowsInMyWidgetsInEnglish() {
        customizesAndSaves(language: "en", name: "Forecast EN")
    }

    @MainActor
    func testCustomizeSaveShowsInMyWidgetsInArabic() {
        customizesAndSaves(language: "ar", name: "Forecast AR")
    }

    @MainActor
    func testBrowsesLibraryInEnglish() {
        browsesLibrary(language: "en")
    }

    @MainActor
    func testBrowsesLibraryInArabic() {
        browsesLibrary(language: "ar")
    }

    /// The test designs gallery (now under Diagnostics) renders specs in both languages.
    @MainActor
    func testTestDesignsRenderInBothLanguages() {
        let app = launch(language: "en")
        openDiagnostics(app)
        let link = app.buttons["ax.diag.testSpecs"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        XCTAssertTrue(app.collectionViews["ax.specs.list"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["ax.specs.preview.test.clock.digital"].waitForExistence(timeout: 10))
        app.buttons["العربية"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ax.specs.preview.test.clock.digital"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testOpensDiagnosticsInArabic() {
        opensDiagnostics(language: "ar")
    }

    @MainActor
    func testOpensDiagnosticsInEnglish() {
        opensDiagnostics(language: "en")
    }
}
