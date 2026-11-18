import XCTest

/// Drives the system file picker for real (the owner's report: tapping a file does nothing). The
/// runner writes files straight into the Simulator's "On My iPhone" storage, then Import opens the
/// picker and taps them. Each case records what it saw, so a failure says where the path stopped.
final class ImportPickerUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private static let widget = """
    {"inventory":["time"],"name":{"en":"Probe","ar":"Probe"},"family":"small","theme":"dark",\
    "palette":{"bg":"#101418","fg":"#F5F5F5","accent":"#FF5A36"},\
    "background":{"type":"solid","color":"@bg","colors":null,"angle":null,"outerColor":null},"fields":[],\
    "layers":[{"type":"stack","axis":"vertical","spacing":4,"padding":null,"alignItems":"center","justify":"center","columns":null,\
    "frame":{"x":12,"y":40,"w":146,"h":90},"opacity":null,"mirror":null,"children":[\
    {"type":"text","value":{"en":"{{time.hh}}:{{time.mm}}","ar":"{{time.hh}}:{{time.mm}}"},"font":{"family":"dot","size":44,"weight":"black"},\
    "color":"@fg","align":"center","maxLines":1,"live":null}]}]}
    """

    /// "On My iPhone" on this Simulator: the Files app's local storage container.
    private func localStorage() throws -> URL {
        // Opening Files once creates the container.
        let files = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
        files.launch()
        _ = files.wait(for: .runningForeground, timeout: 10)
        files.terminate()
        let shared = try XCTUnwrap(ProcessInfo.processInfo.environment["SIMULATOR_SHARED_RESOURCES_DIRECTORY"], "not on a Simulator")
        let groups = URL(fileURLWithPath: shared).appendingPathComponent("Containers/Shared/AppGroup")
        let manager = FileManager.default
        for group in (try? manager.contentsOfDirectory(at: groups, includingPropertiesForKeys: nil)) ?? [] {
            let plist = group.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            guard let data = try? Data(contentsOf: plist),
                  let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  (info["MCMMetadataIdentifier"] as? String)?.contains("FileProvider.LocalStorage") == true else { continue }
            let storage = group.appendingPathComponent("File Provider Storage")
            try manager.createDirectory(at: storage, withIntermediateDirectories: true)
            return storage
        }
        throw XCTSkip("no local storage container on this Simulator")
    }

    /// The picker may live in the app or in its own service process, depending on the iOS version.
    /// Only a running service is asked: querying one that isn't makes XCTest try to launch it.
    private func picker(_ app: XCUIApplication) -> [XCUIApplication] {
        let service = XCUIApplication(bundleIdentifier: "com.apple.DocumentManagerUICore.Service")
        return service.state == .notRunning ? [app] : [app, service]
    }

    private func element(named name: String, in apps: [XCUIApplication], timeout: TimeInterval = 15) -> XCUIElement? {
        let end = Date.now.addingTimeInterval(timeout)
        repeat {
            for app in apps {
                for query in [app.cells, app.buttons, app.staticTexts] {
                    let match = query.matching(NSPredicate(format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@", name, name)).firstMatch
                    if match.exists { return match }
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date.now < end
        return nil
    }

    private func attach(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingStubAI", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment = environment
        app.launch()
        return app
    }

    private func openFromMyWidgets(_ app: XCUIApplication) {
        app.tabBars.buttons.element(boundBy: 1).tap()
        let open = app.buttons["ax.mywidgets.import"]
        for _ in 0..<6 where !(open.exists && open.isHittable) { app.swipeUp() }
        XCTAssertTrue(open.waitForExistence(timeout: 10), "Import button missing in My widgets")
        open.tap()
    }

    /// The owner's path: inside the Create sheet.
    private func openFromUseAnotherAI(_ app: XCUIApplication) {
        let create = app.buttons["ax.library.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        create.tap()
        let external = app.buttons["ax.create.external"]
        for _ in 0..<6 where !(external.exists && external.isHittable) { app.swipeUp() }
        external.tap()
        let open = app.buttons["ax.create.external.file"]
        for _ in 0..<8 where !(open.exists && open.isHittable) { app.swipeUp() }
        XCTAssertTrue(open.waitForExistence(timeout: 10), "Import from file button missing")
        open.tap()
    }

    /// Finds `file` in the open picker, taps it, confirms with Open when there is one, and says
    /// whether the app moved on. Skips when this Simulator's picker can't be driven at all.
    private func pick(_ file: String, app: XCUIApplication) throws {
        sleep(2)
        let apps = picker(app)
        // Exact names: "Browse templates" sits behind the picker in an empty My widgets.
        for app in apps where app.buttons["Browse"].exists {
            app.buttons["Browse"].firstMatch.tap()
            break
        }
        if let local = element(named: "On My iPhone", in: apps, timeout: 6) { local.tap() }
        guard let cell = element(named: (file as NSString).deletingPathExtension, in: apps) else {
            attach(apps.map(\.debugDescription).joined(separator: "\n\n"), name: "picker tree, \(file) not found")
            throw XCTSkip("the picker didn't list \(file) on this Simulator")
        }
        // Cells live in the picker's remote view: a screen coordinate reaches them.
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        sleep(3)
        attach(apps.map(\.debugDescription).joined(separator: "\n\n"), name: "after tapping \(file)")
        for candidate in apps where candidate.buttons["Open"].exists {
            candidate.buttons["Open"].firstMatch.tap()
            break
        }
    }

    private func expectImported(_ app: XCUIApplication, _ what: String) {
        let added = app.descendants(matching: .any).matching(identifier: "ax.bulk.added").firstMatch
        if !added.waitForExistence(timeout: 20) {
            attach(picker(app).map(\.debugDescription).joined(separator: "\n\n"), name: "no summary: \(what)")
            XCTFail("\(what): nothing was imported")
        }
    }

    /// A minimal zip with one stored file (the reader doesn't need a checksum).
    private static func zip(name: String, content: String) -> Data {
        func u16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)] }
        func u32(_ value: Int) -> [UInt8] { u16(value & 0xFFFF) + u16(value >> 16) }
        let (fileName, body) = (Array(name.utf8), Array(content.utf8))
        let shared = u16(20) + u16(0) + u16(0) + u16(0) + u16(0) + u32(0) + u32(body.count) + u32(body.count) + u16(fileName.count) + u16(0)
        let local = u32(0x0403_4B50) + shared + fileName + body
        let central = u32(0x0201_4B50) + u16(20) + shared + u16(0) + u16(0) + u16(0) + u32(0) + u32(0) + fileName
        let end = u32(0x0605_4B50) + u16(0) + u16(0) + u16(1) + u16(1) + u32(central.count) + u32(local.count) + u16(0)
        return Data(local + central + end)
    }

    /// A .json and a .zip reach My widgets: the files the picker would return, through the whole
    /// pipeline, with no system picker in the way.
    @MainActor
    func testImportingAJsonAndAZip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let json = folder.appendingPathComponent("one.json")
        try Self.widget.write(to: json, atomically: true, encoding: .utf8)
        let zip = folder.appendingPathComponent("pack.zip")
        try Self.zip(name: "nested/two.json", content: Self.widget.replacingOccurrences(of: "{{time.hh}}", with: "{{time.mm}}")).write(to: zip)
        let app = launch(environment: ["WS_UITEST_IMPORT": [json, zip].map(\.path).joined(separator: ",")])
        openFromMyWidgets(app)
        expectImported(app, "json and zip")
        XCTAssertTrue(app.staticTexts["2 added"].waitForExistence(timeout: 5), "the summary doesn't say 2 added")
        XCTAssertTrue(app.buttons["ax.bulk.open"].firstMatch.exists, "no Open button for the added designs")
    }

    /// Runs the real picker on a new file, in one combination of mode and place.
    private func realPicker(file: String, data: Data, single: Bool, inSheet: Bool) throws {
        let storage = try localStorage()
        try data.write(to: storage.appendingPathComponent(file))
        let app = launch(environment: single ? ["WS_UITEST_SINGLE_PICK": "1"] : [:])
        if inSheet { openFromUseAnotherAI(app) } else { openFromMyWidgets(app) }
        try pick(file, app: app)
        expectImported(app, "\(file), \(single ? "single" : "multi") selection, \(inSheet ? "in the Create sheet" : "from My widgets")")
    }

    // The import bug's matrix: one variable at a time.

    @MainActor
    func testRealPickerMultiFromMyWidgets() throws {
        try realPicker(file: "probe-a.json", data: Data(Self.widget.utf8), single: false, inSheet: false)
    }

    @MainActor
    func testRealPickerSingleFromMyWidgets() throws {
        try realPicker(file: "probe-b.json", data: Data(Self.widget.utf8), single: true, inSheet: false)
    }

    @MainActor
    func testRealPickerMultiInTheSheet() throws {
        try realPicker(file: "probe-c.json", data: Data(Self.widget.utf8), single: false, inSheet: true)
    }

    /// The owner's path and the old importer's mode.
    @MainActor
    func testRealPickerSingleInTheSheet() throws {
        try realPicker(file: "probe-d.json", data: Data(Self.widget.utf8), single: true, inSheet: true)
    }

    /// A .zip through the real picker: the old importer's types didn't allow it at all.
    @MainActor
    func testRealPickerZip() throws {
        try realPicker(file: "probe-e.zip", data: Self.zip(name: "probe.json", content: Self.widget), single: false, inSheet: false)
    }
}
