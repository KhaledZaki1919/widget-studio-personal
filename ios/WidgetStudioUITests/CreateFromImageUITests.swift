import XCTest

/// M5: Create from image with the canned provider (`-uiTestingStubAI`: no key, no network).
/// Pick an image → generate → consent → editor → save → the design is in My widgets.
final class CreateFromImageUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateFromImageSavesToMyWidgets() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingStubAI", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let create = app.buttons["ax.library.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 15), "Create from image card missing in the Library")
        create.tap()

        // The Simulator's photo library isn't scriptable; the stub mode offers a generated sample.
        let sample = app.buttons["ax.create.sample"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10), "sample image button missing")
        sample.tap()

        let generate = app.buttons["ax.create.generate"]
        for _ in 0..<6 where !(generate.exists && generate.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(generate.waitForExistence(timeout: 5), "Create widget button missing")
        XCTAssertTrue(generate.isEnabled, "Create widget is disabled after picking an image")
        generate.tap()

        // First upload to this provider: the consent sheet names it.
        let allow = app.buttons["ax.create.consent.allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 10), "consent sheet not shown")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Google Gemini")).firstMatch.exists,
                      "consent doesn't name the provider")
        allow.tap()

        // The result opens in the editor, with Regenerate.
        let save = app.buttons["ax.editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 30), "editor didn't open with the result")
        XCTAssertTrue(app.buttons["ax.editor.regenerate"].exists, "Regenerate missing on the result")
        XCTAssertTrue(save.isEnabled, "Save is disabled for the generated design")

        // The layer editor (M6.1): open the list and the first layer, then come back.
        let layers = app.buttons["ax.editor.layers"]
        for _ in 0..<8 where !(layers.exists && layers.isHittable) { app.swipeUp() }
        XCTAssertTrue(layers.exists, "Layers entry missing in the editor")
        layers.tap()
        let firstLayer = app.buttons["ax.editor.layers.row.0"]
        XCTAssertTrue(firstLayer.waitForExistence(timeout: 10), "layer list is empty")
        firstLayer.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 10), "layer detail has no frame fields")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(firstLayer.waitForExistence(timeout: 10), "didn't return to the layer list")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(save.waitForExistence(timeout: 10), "didn't return to the editor")
        save.tap()

        let row = app.descendants(matching: .any).matching(identifier: "ax.mywidgets.design").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "generated design not in My widgets")
        XCTAssertTrue(row.label.contains("Stub Clock"), "row label is \(row.label)")
    }
}
