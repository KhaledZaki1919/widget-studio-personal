import Foundation
import Testing
@testable import WidgetKitCore

/// Bulk import (ADR-027). The zips are in `Fixtures/Bulk`; the Kotlin tests read the same files.
struct BulkImportTests {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Bulk")
    static let widget = """
    {"inventory":["time"],"name":{"en":"One","ar":"One"},"family":"small","theme":"dark",\
    "palette":{"bg":"#101418","fg":"#F5F5F5","accent":"#FF5A36"},\
    "background":{"type":"solid","color":"@bg"},"fields":[],\
    "layers":[{"type":"stack","axis":"vertical","frame":{"x":12,"y":40,"w":146,"h":90},"children":[\
    {"type":"text","value":{"en":"{{time.hh}}","ar":"{{time.hh}}"},"font":{"family":"dot","size":44},"color":"@fg"}]}]}
    """

    @Test func splitsArraysAndObjectsInARow() {
        #expect(BulkImport.split(Self.widget).count == 1)
        #expect(BulkImport.split("[\(Self.widget),\(Self.widget)]").count == 2)
        #expect(BulkImport.split("```json\n\(Self.widget)\n```\nand\n```json\n\(Self.widget)\n```").count == 2)
        #expect(BulkImport.split("{\"widgets\":[\(Self.widget),\(Self.widget),\(Self.widget)]}").count == 3)
        // A brace inside a string doesn't end the object.
        #expect(BulkImport.split("{\"a\":\"}{\"}").count == 1)
        #expect(BulkImport.split("no json here") == ["no json here"])
    }

    @Test func readsNestedZipsAndIgnoresOtherFiles() throws {
        let data = try Data(contentsOf: Self.folder.appendingPathComponent("nested.zip"))
        let entries = try BulkImport.zipEntries(data)
        #expect(entries.map(\.name).sorted() == ["a.json", "deep/er/c.json", "deep/stored.json"])
        #expect(entries.allSatisfy { $0.text.contains("layers") })
    }

    @Test func rejectsPathTraversal() throws {
        #expect(!BulkImport.isSafe("../x.json") && !BulkImport.isSafe("/etc/x.json") && !BulkImport.isSafe("a/../../x.json"))
        #expect(!BulkImport.isSafe("a\\x.json") && !BulkImport.isSafe("C:/x.json") && BulkImport.isSafe("a/b.json"))
        let data = try Data(contentsOf: Self.folder.appendingPathComponent("traversal.zip"))
        #expect(throws: ExternalAI.ImportError.self) { try BulkImport.zipEntries(data) }
    }

    @Test func aFileThatIsNoZipSaysSo() {
        #expect(throws: BulkImport.ZipError.self) { try BulkImport.zipEntries(Data("PK\u{03}\u{04}broken".utf8)) }
    }

    @Test func runAddsSkipsDuplicatesAndNumbersNames() throws {
        let other = Self.widget.replacingOccurrences(of: "{{time.hh}}", with: "{{time.mm}}")
        let sources = [BulkImport.Source(name: "1", text: Self.widget), BulkImport.Source(name: "2", text: Self.widget),
                       BulkImport.Source(name: "3", text: other), BulkImport.Source(name: "4", text: "nope"),
                       BulkImport.Source(name: "5", text: "{\"layers\":[]}")]
        let summary = BulkImport.run(sources, existing: [], language: "en")
        #expect(summary.added.map(\.design.name) == ["One", "One (2)"])
        #expect(summary.duplicates == ["2"])
        #expect(summary.failed.map(\.name) == ["4", "5"])
        #expect(BulkImport.fixRequest(summary.failed).contains("4:"))
        // What is already saved counts too.
        let again = BulkImport.run([sources[0]], existing: summary.added.map(\.design), language: "en")
        #expect(again.added.isEmpty && again.duplicates == ["1"])
    }

    @Test func eachDesignGoesThroughAutoWire() {
        let battery = Self.widget.replacingOccurrences(of: "{{time.hh}}", with: "22 %").replacingOccurrences(of: "\"One\"", with: "\"Battery\"")
        let summary = BulkImport.run([BulkImport.Source(name: "b", text: battery)], existing: [], language: "en")
        #expect(summary.fixedCount == 1)
        #expect(summary.added.first.map { WiringScore.ids(in: $0.design.spec).contains("battery.level") } == true)
    }

    @Test func loadsFilesAndFolders() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Self.widget.write(to: folder.appendingPathComponent("a.json"), atomically: true, encoding: .utf8)
        try Self.widget.write(to: folder.appendingPathComponent("sub/b.json"), atomically: true, encoding: .utf8)
        try "skip".write(to: folder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try Data(contentsOf: Self.folder.appendingPathComponent("nested.zip")).write(to: folder.appendingPathComponent("sub/more.zip"))
        let loaded = BulkImport.load(urls: [folder])
        #expect(loaded.sources.count == 5)
        #expect(loaded.failed.isEmpty)
        let missing = BulkImport.load(urls: [folder.appendingPathComponent("gone.json")])
        #expect(missing.failed.first?.error == .unreadable)
    }
}
