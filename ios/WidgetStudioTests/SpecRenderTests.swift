import SwiftUI
import UIKit
import WidgetKitCore
import XCTest

/// Renders the specs on the Simulator, in both languages, through the same views as the app and
/// the widget (ADR-010). Catches RTL regressions (anything flipped like an image), missing fonts
/// and specs that fail to render in the widget view.
@MainActor
final class SpecRenderTests: XCTestCase {
    private let languages = ["en", "ar"]

    // MARK: Fonts

    /// The fonts must come from UIAppFonts, which is what the widget extension relies on too.
    func testBundledFontsAreAvailable() {
        for name in FontRegistry.bundledPostScriptNames {
            XCTAssertNotNil(UIFont(name: name, size: 12), "\(name) is not registered through UIAppFonts")
        }
    }

    // MARK: RTL invariants (no references needed)

    /// Layers without `mirror` must render pixel-identically in Arabic: no text, digit, clock,
    /// ring or chart may be flipped, also when the host view is right-to-left.
    func testUnmirroredLayersAreIdenticalInArabic() throws {
        let spec = Self.invariantSpec(mirror: false)
        let size = spec.family.canvas
        let english = try XCTUnwrap(Snapshot.render(SpecView(spec: spec, context: Snapshot.context(language: "en")), size: size))
        let arabic = try XCTUnwrap(Snapshot.render(SpecView(spec: spec, context: Snapshot.context(language: "ar")), size: size))
        let arabicHost = try XCTUnwrap(Snapshot.render(
            SpecView(spec: spec, context: Snapshot.context(language: "ar")).environment(\.layoutDirection, .rightToLeft),
            size: size
        ))
        Snapshot.write(english, name: "invariant.unmirrored.en")
        Snapshot.write(arabicHost, name: "invariant.unmirrored.ar-host")
        let plain = Pixels.compare(english, arabic, tolerance: 0, maxShare: 0)
        XCTAssertTrue(plain.matches, "Arabic render changed unmirrored layers: \(plain.summary)")
        let hosted = Pixels.compare(english, arabicHost, tolerance: 0, maxShare: 0)
        XCTAssertTrue(hosted.matches, "An RTL host changed unmirrored layers: \(hosted.summary)")
    }

    /// `mirror: true` may only move a layer to the mirrored frame and swap its alignment and item
    /// order: the Arabic render must equal an English render of the hand-mirrored spec.
    func testMirrorOnlyMovesLayersAndSwapsOrder() throws {
        let size = SpecFamily.medium.canvas
        let arabic = try XCTUnwrap(Snapshot.render(
            SpecView(spec: Self.invariantSpec(mirror: true), context: Snapshot.context(language: "ar")), size: size
        ))
        let expected = try XCTUnwrap(Snapshot.render(
            SpecView(spec: Self.handMirroredSpec(), context: Snapshot.context(language: "en")), size: size
        ))
        Snapshot.write(arabic, name: "invariant.mirrored.ar")
        Snapshot.write(expected, name: "invariant.mirrored.expected")
        let result = Pixels.compare(arabic, expected, tolerance: 0, maxShare: 0)
        XCTAssertTrue(result.matches, "Mirroring did more than move layers: \(result.summary)")
    }

    // MARK: Every spec through the widget view

    /// Each test spec renders through `SpecWidgetContent` (what the widget draws) in every widget
    /// size and both languages, and the result isn't blank.
    func testEverySpecRendersThroughTheWidgetView() throws {
        let specs = TestSpecs.load()
        XCTAssertEqual(specs.count, 12)
        for entry in specs {
            guard case .success(let spec) = entry.result else {
                XCTFail("\(entry.fileName) is invalid")
                continue
            }
            for family in SpecFamily.allCases {
                for language in languages {
                    let image = Snapshot.render(SpecWidgetContent(spec: spec, context: Snapshot.context(language: language)),
                                                size: family.canvas)
                    let rendered = try XCTUnwrap(image, "\(spec.id) didn't render (\(family), \(language))")
                    XCTAssertGreaterThan(Pixels.distinctColors(rendered), 1, "\(spec.id) rendered blank (\(family), \(language))")
                }
            }
        }
    }

    /// Every template renders through `SpecWidgetContent` in every size it supports, in both
    /// languages and both themes, and the result isn't blank (M2).
    func testEveryTemplateRendersThroughTheWidgetView() throws {
        let templates = TemplateLibrary.all()
        XCTAssertEqual(templates.count, 28)
        for spec in templates {
            for family in spec.family.supportedFamilies {
                for language in languages {
                    for theme in SpecTheme.allCases {
                        var context = Snapshot.context(language: language)
                        context.theme = theme
                        let image = Snapshot.render(SpecWidgetContent(spec: spec, context: context), size: family.canvas)
                        let rendered = try XCTUnwrap(image, "\(spec.id) didn't render (\(family), \(language), \(theme))")
                        XCTAssertGreaterThan(Pixels.distinctColors(rendered), 1,
                                             "\(spec.id) rendered blank (\(family), \(language), \(theme))")
                    }
                }
            }
        }
    }

    // MARK: Snapshots

    /// One reference image per template and language, in its default theme (`Snapshots/<id>.<lang>.png`).
    func testTemplateSnapshots() throws {
        try assertSnapshots(TemplateLibrary.all())
    }

    /// One reference image per test spec and language (`Snapshots/<id>.<lang>.png`).
    func testSpecSnapshots() throws {
        try assertSnapshots(TestSpecs.all())
    }

    private func assertSnapshots(_ specs: [WidgetSpec]) throws {
        var missing: [String] = []
        for spec in specs {
            for language in languages {
                let name = "\(spec.id).\(language)"
                let image = try XCTUnwrap(Snapshot.render(SpecView(spec: spec, context: Snapshot.context(language: language)),
                                                          size: spec.family.canvas))
                do {
                    try Snapshot.assertMatches(image, name: name)
                } catch is XCTSkip {
                    missing.append(name)
                }
            }
        }
        if !missing.isEmpty {
            throw XCTSkip("Recorded \(missing.count) snapshots without references: \(missing.joined(separator: ", "))")
        }
    }

    // MARK: Fixtures

    /// Text with Latin digits, an analog clock, a ring, dot bars and an icon, all with `mirror`.
    static func invariantSpec(mirror: Bool) -> WidgetSpec {
        WidgetSpec(
            id: "test.invariant", name: .localized(en: "Invariant", ar: "ثابت"), family: .medium,
            background: .solid("#0E0E0E"),
            layers: [
                Layer(frame: Frame(x: 10, y: 10, w: 150, h: 40), mirror: mirror, content: .text(TextLayer(
                    value: "AB 12:34", font: FontSpec(family: "dot", size: 28, weight: .bold), color: "#FFFFFF"
                ))),
                Layer(frame: Frame(x: 10, y: 60, w: 100, h: 100), mirror: mirror, content: .analogClock(AnalogClockLayer())),
                Layer(frame: Frame(x: 120, y: 60, w: 100, h: 100), mirror: mirror, content: .ring(RingLayer(
                    progress: "0.3", color: "#E31C24", lineWidth: 8
                ))),
                Layer(frame: Frame(x: 240, y: 20, w: 110, h: 130), mirror: mirror, content: .dotBars(DotBarsLayer(
                    bars: 4, maxDots: 6, values: "0.2,0.5,0.8,1", color: "#FFFFFF", labels: "a,b,c,d"
                ))),
                Layer(frame: Frame(x: 180, y: 10, w: 30, h: 30), mirror: mirror, content: .icon(IconLayer(
                    symbol: "figure.walk", size: 22, color: "#FFFFFF"
                ))),
            ]
        )
    }

    /// `invariantSpec(mirror: true)` as Arabic should draw it, built by hand without `mirror`.
    static func handMirroredSpec() -> WidgetSpec {
        var spec = invariantSpec(mirror: false)
        let width = spec.family.canvas.width
        for index in spec.layers.indices {
            spec.layers[index].frame = spec.layers[index].frame.mirrored(canvasWidth: width)
            switch spec.layers[index].content {
            case .text(var text):
                text.align = .trailing
                spec.layers[index].content = .text(text)
            case .dotBars(var bars):
                bars.values = "1,0.8,0.5,0.2"
                bars.labels = "d,c,b,a"
                spec.layers[index].content = .dotBars(bars)
            default:
                break
            }
        }
        return spec
    }
}
