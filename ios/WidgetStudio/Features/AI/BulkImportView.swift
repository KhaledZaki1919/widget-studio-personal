import ObjectiveC
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKitCore

/// What to import: picked or shared files, or pasted text.
struct BulkRequest: Identifiable, Hashable {
    let id = UUID()
    var urls: [URL] = []
    var text: String?
}

/// The system file picker (ADR-027). It replaces SwiftUI's `fileImporter`: every file can be tapped
/// (`.item`, so a `.json` tagged as text or data is never greyed out, and `.zip` works), the picker
/// is presented over the top view controller so no `.sheet` on the same view can cancel it, and
/// files arrive as local copies, so reading needs no security scope.
@MainActor
enum DocumentPicker {
    private final class Delegate: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }

    private static var key: UInt8 = 0

    static func present(folder: Bool = false, onPick: @escaping ([URL]) -> Void) {
        // UI tests only (`-uiTesting`): the files the picker would return.
        let testing = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        if testing, let paths = ProcessInfo.processInfo.environment["WS_UITEST_IMPORT"] {
            onPick(paths.split(separator: ",").map { URL(fileURLWithPath: String($0)) })
            return
        }
        let picker = folder
            ? UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
            : UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = !folder
        // The import bug's control (ADR-027): this picker in single selection, as fileImporter was.
        if testing, ProcessInfo.processInfo.environment["WS_UITEST_SINGLE_PICK"] != nil { picker.allowsMultipleSelection = false }
        let delegate = Delegate(onPick: onPick)
        picker.delegate = delegate
        objc_setAssociatedObject(picker, &key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        topController()?.present(picker, animated: true)
    }

    private static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Bulk import (ADR-027): progress, then what happened. Valid designs are already in My widgets.
struct BulkImportView: View {
    @Environment(DesignsModel.self) private var designs
    @Environment(LiveDataModel.self) private var live
    let request: BulkRequest
    @State private var done = 0
    @State private var total = 0
    @State private var summary: BulkImport.Summary?
    @State private var failedToLoad: [BulkImport.Failure] = []
    @State private var opened: SavedDesign?
    @State private var fixCopied = false
    private let language = RenderContext.preferredLanguage

    private var failed: [BulkImport.Failure] { failedToLoad + (summary?.failed ?? []) }

    var body: some View {
        Group {
            if let summary {
                results(summary)
            } else {
                VStack(spacing: 12) {
                    ProgressView(value: Double(done), total: Double(max(total, 1)))
                    Text("bulk.progress \(done) \(total)").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(32)
                .accessibilityIdentifier("ax.bulk.progress")
            }
        }
        .navigationTitle("bulk.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { if summary == nil { await run() } }
        .sheet(item: $opened) { design in
            EditorView(design: design, isNew: false)
        }
    }

    private func run() async {
        let request = request
        let existing = designs.designs
        let language = language
        let (sources, unread) = await Task.detached(priority: .userInitiated) { () -> ([BulkImport.Source], [BulkImport.Failure]) in
            var (sources, unread) = BulkImport.load(urls: request.urls)
            if let text = request.text { sources += BulkImport.sources(text: text, name: "1") }
            return (sources, unread)
        }.value
        failedToLoad = unread
        total = sources.count
        let result = await Task.detached(priority: .userInitiated) { () -> BulkImport.Summary in
            BulkImport.run(sources, existing: existing, language: language) { index in
                Task { @MainActor in done = index }
            }
        }.value
        var finished = result
        var saved: [BulkImport.Added] = []
        for item in result.added {
            do {
                try designs.save(item.design, newPhoto: nil)
                saved.append(item)
            } catch {
                finished.failed.append(BulkImport.Failure(name: item.design.name, error: .unreadable))
            }
        }
        finished.added = saved
        summary = finished
        await WidgetPermissions.request(for: saved.map(\.design.spec), live: live)
    }

    private func results(_ summary: BulkImport.Summary) -> some View {
        List {
            Section {
                Label("bulk.added \(summary.added.count)", systemImage: "checkmark.circle.fill")
                    .accessibilityIdentifier("ax.bulk.added")
                if summary.fixedCount > 0 { Label("bulk.fixed \(summary.fixedCount)", systemImage: "wand.and.stars") }
                if !summary.duplicates.isEmpty { Label("bulk.duplicates \(summary.duplicates.count)", systemImage: "equal.circle") }
                if !failed.isEmpty {
                    Label("bulk.failed \(failed.count)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            if !summary.added.isEmpty {
                Section("bulk.addedList") {
                    ForEach(summary.added) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: item.design.name)
                                if item.needsEditing {
                                    Text("editor.layout.needsEditing").font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Button("bulk.open") { opened = item.design }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("ax.bulk.open")
                        }
                    }
                }
            }
            if !failed.isEmpty {
                Section("bulk.failedList") {
                    ForEach(failed) { failure in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: failure.name).font(.subheadline)
                            Text(ExternalAIView.message(failure.error)).font(.caption).foregroundStyle(.secondary)
                            if case .invalid(let problems) = failure.error {
                                Text(verbatim: problems)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                        }
                    }
                    Button {
                        UIPasteboard.general.string = BulkImport.fixRequest(failed)
                        fixCopied = true
                    } label: {
                        Label(fixCopied ? LocalizedStringKey("create.external.fixCopied") : "create.external.copyFix",
                              systemImage: fixCopied ? "checkmark.circle.fill" : "arrow.uturn.left.circle")
                    }
                    .accessibilityIdentifier("ax.bulk.copyFix")
                }
            }
        }
    }
}
