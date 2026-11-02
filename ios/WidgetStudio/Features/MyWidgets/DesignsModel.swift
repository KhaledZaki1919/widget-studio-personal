import CoreGraphics
import Foundation
import Observation
import WidgetKit
import WidgetKitCore

/// The app's view of saved designs. Everything goes through `SharedStore` (ADR-015), so the same
/// code shares designs with the widget once an App Group exists.
@MainActor
@Observable
final class DesignsModel {
    private(set) var designs: [SavedDesign] = []
    let store: SharedStore
    /// Decoded photos by file name, for previews.
    @ObservationIgnored private var images: [String: CGImage] = [:]

    init(store: SharedStore = SharedStore()) {
        self.store = store
        reload()
    }

    var isShared: Bool { store.isShared }

    func reload() {
        designs = store.designs()
    }

    func image(for design: SavedDesign) -> CGImage? {
        guard let file = design.imageFile else { return nil }
        if let cached = images[file] { return cached }
        let image = store.image(named: file)
        images[file] = image
        return image
    }

    /// Saves (insert or update) a design, with a newly processed photo if there is one.
    func save(_ design: SavedDesign, newPhoto: CGImage?) throws {
        var design = design
        if let newPhoto {
            let lossless = (design.imageLayer?.layer.filter ?? .none) != .none
            design.imageFile = try store.storeImage(newPhoto, designID: design.id, lossless: lossless)
            if let file = design.imageFile { images[file] = newPhoto }
        }
        try store.save(design)
        store.removeUnusedImages()
        changed()
    }

    func rename(_ design: SavedDesign, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? store.rename(id: design.id, to: String(trimmed.prefix(SavedDesign.maxNameLength)))
        changed()
    }

    func duplicate(_ design: SavedDesign, name: String) {
        _ = try? store.duplicate(id: design.id, name: String(name.prefix(SavedDesign.maxNameLength)))
        changed()
    }

    func delete(_ design: SavedDesign) {
        try? store.delete(id: design.id)
        changed()
    }

    /// UI tests start from an empty list.
    func deleteAll() {
        for design in store.designs() { try? store.delete(id: design.id) }
        changed()
    }

    private func changed() {
        reload()
        // My widget reads the store; it only sees it with an App Group (store mode, ADR-014).
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Which tab is showing; Save in the editor switches to My widgets.
@MainActor
@Observable
final class AppState {
    enum Tab: Hashable { case library, myWidgets, settings }
    var tab: Tab = .library
    /// Create from image (M5), opened from the Library and My widgets.
    var isCreatingFromImage = false
    /// The introduction (M6): shown on first launch, reopenable from Settings.
    var isShowingOnboarding = !UserDefaults.standard.bool(forKey: AppState.onboardingDoneKey)
        || !UserDefaults.standard.bool(forKey: AppState.permissionsSeenKey)
    /// Users who finished the M6 introduction see only the permissions page, once (M6.1).
    var onboardingPermissionsOnly = UserDefaults.standard.bool(forKey: AppState.onboardingDoneKey)

    static let onboardingDoneKey = "onboardingDone"
    static let permissionsSeenKey = "permissionsPageSeen"

    func showIntroduction() {
        onboardingPermissionsOnly = false
        isShowingOnboarding = true
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingDoneKey)
        UserDefaults.standard.set(true, forKey: Self.permissionsSeenKey)
        isShowingOnboarding = false
    }
}
