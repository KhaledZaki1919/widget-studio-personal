import CoreGraphics
import Foundation
import Testing
@testable import WidgetKitCore

private func template(_ id: String) throws -> WidgetSpec {
    try TemplateLibrary.load(id: id).get()
}

private func solid(width: Int, height: Int, gray: CGFloat) -> CGImage? {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    context?.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
    context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context?.makeImage()
}

/// Share of pixels darker than mid gray.
private func darkShare(_ image: CGImage) -> Double {
    let gray = ImageProcessing.luminance(image) ?? []
    return Double(gray.filter { $0 < 0.5 }.count) / Double(max(gray.count, 1))
}

/// M3: field editing and validation of edited designs (ADR-015).
struct DesignEditingTests {
    @Test func freshDesignsFromEveryTemplateAreValid() throws {
        for spec in TemplateLibrary.all() {
            let design = SavedDesign.new(from: spec, language: "ar")
            #expect(DesignEditing.validate(design).isEmpty, "\(spec.id): \(DesignEditing.validate(design))")
        }
    }

    @Test func editedValuesRenderInBothLanguages() throws {
        var design = SavedDesign.new(from: try template("mono.countdown.red"), language: "en")
        design.fieldValues["title"] = .localized(en: "Graduation", ar: "التخرج")
        design.fieldValues["date"] = "2026-11-01"
        #expect(DesignEditing.validate(design).isEmpty)
        for (language, title) in [("en", "Graduation"), ("ar", "التخرج")] {
            let context = design.renderContext(date: Date(timeIntervalSince1970: 1_792_591_500), language: language, data: .sample())
            let resolver = BindingResolver(spec: design.spec, context: context)
            #expect(resolver.render("{{field.title}}") == title)
            #expect(resolver.render("{{days.date}}") == "11")
        }
    }

    @Test func invalidUserValuesAreRejected() throws {
        var trip = SavedDesign.new(from: try template("mono.countdown.trip"), language: "en")
        trip.fieldValues["date"] = "next week"
        trip.fieldValues["line1"] = "see www.example.com"
        let issues = DesignEditing.validate(trip)
        #expect(issues.contains { $0.path == "fields.date" })
        #expect(issues.contains { $0.path == "fields.line1" })

        var zone = SavedDesign.new(from: try template("mono.date.dayZone"), language: "en")
        zone.fieldValues["zone"] = "Mars/Base"
        #expect(DesignEditing.validate(zone).contains { $0.path == "fields.zone" })
        zone.fieldValues["zone"] = "Asia/Tokyo"
        #expect(DesignEditing.validate(zone).isEmpty)
        zone.fieldValues["zone"] = ""
        #expect(DesignEditing.validate(zone).isEmpty)
    }

    @Test func urlFieldsAcceptOnlyWebLinks() throws {
        var music = SavedDesign.new(from: try template("mono.music.card"), language: "en")
        music.fieldValues["url"] = "https://example.com/song"
        #expect(DesignEditing.validate(music).isEmpty)
        for bad in ["javascript:alert(1)", "file:///etc/passwd", "example.com", "https://"] {
            music.fieldValues["url"] = .plain(bad)
            #expect(DesignEditing.validate(music).contains { $0.path == "fields.url" }, "accepted \(bad)")
        }
    }

    @Test func iconsShortcutsNamesAndColors() throws {
        var tiles = SavedDesign.new(from: try template("mono.tiles.pills2"), language: "en")
        tiles.fieldValues["icon1"] = "airplane"
        tiles.fieldValues["shortcut1"] = "Airplane Mode"
        tiles.colors["accent"] = "#0A84FF"
        #expect(DesignEditing.validate(tiles).isEmpty)
        tiles.fieldValues["icon1"] = "applelogo"
        tiles.fieldValues["shortcut1"] = "shortcuts://run"
        tiles.colors["accent"] = "blue"
        tiles.colors["line"] = "#000000"   // muted is editable since M6.1; line isn't
        tiles.name = "   "
        let paths = Set(DesignEditing.validate(tiles).map(\.path))
        #expect(paths.isSuperset(of: ["fields.icon1", "fields.shortcut1", "colors.accent", "colors.line", "name"]))
    }

    @Test func unknownFieldsAreReported() throws {
        var design = SavedDesign.new(from: try template("mono.clock.analog"), language: "en")
        design.fieldValues["ghost"] = "x"
        #expect(DesignEditing.validate(design).contains { $0.path == "fields.ghost" })
    }

    @Test func accentOverrideReachesTheRenderedSpec() throws {
        var design = SavedDesign.new(from: try template("mono.countdown.red"), language: "en")
        design.colors["accent"] = "#0A84FF"
        let resolved = design.spec.resolvingTokens(theme: design.theme, overrides: design.colors)
        #expect(resolved.background.color == "#0A84FF")
        // An invalid override is ignored by rendering (and reported by validation).
        let ignored = design.spec.resolvingTokens(theme: nil, overrides: ["accent": "nope"])
        #expect(ignored.background.color == "#E2231A")
    }

    @Test func datesKeepTimeOnlyWhenTheDefaultHasOne() throws {
        let trip = try template("mono.countdown.trip")
        let countdown = try template("mono.countdown.red")
        let date = Date(timeIntervalSince1970: 1_792_591_500)
        let utc = TimeZone(identifier: "UTC") ?? .current
        let countdownDate = try #require(countdown.field("date"))
        let tripDate = try #require(trip.field("date"))
        let tripLine = try #require(trip.field("line1"))
        #expect(DesignEditing.dateValue(date, for: countdownDate, timeZone: utc) == "2026-10-21")
        #expect(DesignEditing.dateValue(date, for: tripDate, timeZone: utc) == "2026-10-21T14:05:00Z")
        #expect(DesignEditing.isBilingual(tripLine))
        #expect(!DesignEditing.isBilingual(tripDate))
    }

    // MARK: Photos

    @Test func photosAreCroppedToTheWidgetPixelSize() throws {
        let design = SavedDesign.new(from: try template("mono.photo.square"), language: "en")
        let slot = try #require(design.imageLayer)
        let photo = try #require(solid(width: 4000, height: 3000, gray: 0.5))
        let prepared = try #require(ImageProcessing.prepare(photo, frame: slot.frame, layer: slot.layer))
        #expect(prepared.width == 510 && prepared.height == 510)
    }

    @Test func longestSideIsCapped() {
        let size = ImageProcessing.pixelSize(for: Frame(x: 0, y: 0, w: 364, h: 382))
        #expect(max(size.width, size.height) == CGFloat(ImageProcessing.maxSide))
    }

    @Test func halftoneIsAppliedForDotPortrait() throws {
        let design = SavedDesign.new(from: try template("mono.photo.halftone"), language: "en")
        let slot = try #require(design.imageLayer)
        #expect(slot.layer.filter == .halftone)
        let darkPhoto = try #require(solid(width: 600, height: 600, gray: 0.1))
        let lightPhoto = try #require(solid(width: 600, height: 600, gray: 0.95))
        let dark = try #require(ImageProcessing.prepare(darkPhoto, frame: slot.frame, layer: slot.layer))
        let light = try #require(ImageProcessing.prepare(lightPhoto, frame: slot.frame, layer: slot.layer))
        #expect(darkShare(dark) > 0.6)
        #expect(darkShare(light) < 0.1)
    }

    @Test func monoMakesGray() throws {
        let context = CGContext(data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
        let red = try #require(context?.makeImage())
        let gray = try #require(ImageProcessing.mono(red))
        // Equal channels = gray. (The exact level depends on color management, so only a range.)
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            let check = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            check?.draw(gray, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        #expect(abs(Int(pixel[0]) - Int(pixel[1])) <= 2 && abs(Int(pixel[1]) - Int(pixel[2])) <= 2, "\(pixel)")
        #expect((25...140).contains(Int(pixel[0])), "\(pixel)")
    }
}
