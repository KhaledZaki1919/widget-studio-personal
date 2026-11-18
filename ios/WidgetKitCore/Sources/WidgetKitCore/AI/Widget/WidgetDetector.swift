import CoreGraphics
import Foundation
#if canImport(Vision)
import Vision
#endif

/// The outline of a widget's card in an image (ADR-024). iOS widgets are always rounded
/// rectangles, so a circle or capsule card is drawn inside the widget (`Background.cardShape`),
/// and `none` is a design floating on the wallpaper with no card at all.
public enum WidgetCardShape: String, Codable, Sendable, CaseIterable {
    case roundedRect, circle, capsule, none
}

/// One widget found in a picked image.
public struct DetectedWidget: Sendable, Equatable {
    /// In image pixels, origin at the top left.
    public var rect: CGRect
    public var shape: WidgetCardShape

    public init(rect: CGRect, shape: WidgetCardShape) {
        self.rect = rect
        self.shape = shape
    }

    /// Wide → medium; as wide as most of the image (a large widget on a home screen) → large;
    /// else small. Small and large have nearly the same shape, so the width decides.
    public func suggestedSize(imageWidth: Int) -> SizeChoice {
        guard rect.height > 0 else { return .auto }
        let aspect = rect.width / rect.height
        if aspect > 1.5 { return .medium }
        if shape != .circle, rect.width > 0.6 * CGFloat(imageWidth), aspect > 0.75 { return .large }
        return .small
    }
}

/// Finds the widget(s) in a screenshot or design (ADR-024), so only the card goes to the AI:
/// 1. contours (Vision, light-on-dark and dark-on-light) give closed shapes, classified by how
///    much of their bounding box they fill and their aspect: rounded rectangle and squircle,
///    circle, capsule;
/// 2. rectangle detection (Vision) adds rounded rectangles the contours missed;
/// 3. overlapping candidates are merged, shapes inside another candidate (a pill in a card) and
///    shapes touching the image edge (the wallpaper, a tightly cropped card) are dropped;
/// 4. with no card at all, objectness saliency gives the floating content, padded.
/// Results are in reading order. Empty means "use the whole image".
public enum WidgetDetector {
    /// Candidates smaller than this share of the image are details, not widgets.
    static let minimumArea = 0.015
    static let floatingPadding = 0.08

    public static func detect(_ image: CGImage) -> [DetectedWidget] {
        #if canImport(Vision)
        let size = CGSize(width: image.width, height: image.height)
        guard let pixels = RGBA(image) else { return [] }
        // Salient objects count only when every corner reaches solid card color (not a column of icons).
        let salient = salientCandidates(image, size: size).filter { cornerRadius(of: $0.rect, in: pixels) != nil }
        // Rectangle and saliency boxes can be off a little: grow or trim each to the card's edges.
        // Contours are exact and stay as traced (a wallpaper blob must not grow into a card).
        let boxes = (rectangleCandidates(image, size: size) + salient).map {
            DetectedWidget(rect: refined($0.rect, in: pixels, size: size), shape: $0.shape)
        }
        var candidates = contourCandidates(image, size: size) + boxes
        candidates = candidates.filter { candidate in
            let share = candidate.rect.width * candidate.rect.height / (size.width * size.height)
            guard share >= minimumArea, !touchesEdge(candidate.rect, size: size) else { return false }
            // A soft gradient can look like a rectangle (eval 2026-11-02: a square around a round card).
            return hasEdge(candidate.rect, in: pixels)
        }
        var kept: [DetectedWidget] = []
        for candidate in candidates.sorted(by: { area($0.rect) > area($1.rect) }) {
            if let index = kept.firstIndex(where: { sameBox($0.rect, candidate.rect) }) {
                // Same card seen twice: keep the bigger box, take a contour's shape over a rectangle's.
                if kept[index].shape == .roundedRect, candidate.shape != .roundedRect { kept[index].shape = candidate.shape }
                continue
            }
            if kept.contains(where: { inside(candidate.rect, $0.rect) > 0.9 }) { continue }
            kept.append(candidate)
        }
        // Rectangle detection can't tell a pill from a card: measure the corners in the pixels.
        if kept.contains(where: { $0.shape == .roundedRect }) {
            kept = kept.map { widget in
                guard widget.shape == .roundedRect, let radius = cornerRadius(of: widget.rect, in: pixels) else { return widget }
                let short = min(widget.rect.width, widget.rect.height)
                guard radius >= 0.4 * short else { return widget }
                let aspect = widget.rect.width / max(widget.rect.height, 1)
                return DetectedWidget(rect: widget.rect, shape: aspect > 0.85 && aspect < 1.18 ? .circle : .capsule)
            }
        }
        if kept.isEmpty, let floating = floatingContent(image, size: size) { kept = [floating] }
        return readingOrder(kept)
        #else
        return []
        #endif
    }

    // MARK: Geometry

    static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }

    /// The same card found twice: intersection over union above 0.7 (a ring inside a pill is not
    /// the pill, eval 2026-11-02).
    /// Also when one box lies inside the other and is at least 60 % of its size: a contour traced
    /// a little inside the edge.
    static func sameBox(_ a: CGRect, _ b: CGRect) -> Bool {
        let common = a.intersection(b)
        guard !common.isNull else { return false }
        let union = area(a) + area(b) - area(common)
        if union > 0, area(common) / union > 0.7 { return true }
        let (small, big) = area(a) < area(b) ? (a, b) : (b, a)
        return inside(small, big) > 0.9 && area(big) > 0 && area(small) / area(big) >= 0.6
    }

    /// Share of `inner` inside `outer`.
    static func inside(_ inner: CGRect, _ outer: CGRect) -> CGFloat {
        let common = inner.intersection(outer)
        guard !common.isNull, area(inner) > 0 else { return 0 }
        return area(common) / area(inner)
    }

    static func touchesEdge(_ rect: CGRect, size: CGSize) -> Bool {
        let margin = max(2, 0.004 * max(size.width, size.height))
        return rect.minX <= margin || rect.minY <= margin || rect.maxX >= size.width - margin || rect.maxY >= size.height - margin
    }

    /// Rows top to bottom (a row: vertical centers within half the smaller height), then left to right.
    static func readingOrder(_ widgets: [DetectedWidget]) -> [DetectedWidget] {
        widgets.sorted { a, b in
            if abs(a.rect.midY - b.rect.midY) < min(a.rect.height, b.rect.height) / 2 { return a.rect.minX < b.rect.minX }
            return a.rect.midY < b.rect.midY
        }
    }

    /// From how much of its box a closed shape fills and its aspect.
    /// The corner radius the missing area implies, r = √((1 − fill)·w·h / (4 − π)), against the
    /// short side: about half for circles and capsules, about a quarter for widget squircles.
    static func classify(fill: CGFloat, aspect: CGFloat) -> WidgetCardShape? {
        guard fill >= 0.72, aspect >= 0.2, aspect <= 5 else { return nil }
        let width = max(aspect, 1)
        let height = max(1 / aspect, 1)
        let radius = sqrt(max(0, 1 - fill) * width * height / (4 - .pi))
        let round = radius >= 0.4 * min(width, height)
        if !round { return .roundedRect }
        return aspect > 0.85 && aspect < 1.18 ? .circle : .capsule
    }

    // MARK: Vision

    #if canImport(Vision)
    static func contourCandidates(_ image: CGImage, size: CGSize) -> [DetectedWidget] {
        var found: [DetectedWidget] = []
        for darkOnLight in [true, false] {
            let request = VNDetectContoursRequest()
            request.contrastAdjustment = 1.5
            request.detectsDarkOnLight = darkOnLight
            request.maximumImageDimension = 512
            guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil,
                  let observation = request.results?.first else { continue }
            // Top-level shapes and their direct children (a card inside a lighter frame).
            let contours = observation.topLevelContours + observation.topLevelContours.flatMap(\.childContours)
            for contour in contours where contour.pointCount >= 8 {
                let points = contour.normalizedPoints.map { CGPoint(x: CGFloat($0.x) * size.width, y: (1 - CGFloat($0.y)) * size.height) }
                guard let box = bounds(points), box.width > 0, box.height > 0 else { continue }
                let fill = polygonArea(points) / area(box)
                if let shape = classify(fill: fill, aspect: box.width / box.height) {
                    found.append(DetectedWidget(rect: box, shape: shape))
                }
            }
        }
        return found
    }

    static func rectangleCandidates(_ image: CGImage, size: CGSize) -> [DetectedWidget] {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.25
        request.maximumAspectRatio = 1
        request.minimumSize = 0.1
        request.minimumConfidence = 0.6
        request.quadratureTolerance = 20
        request.maximumObservations = 12
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil else { return [] }
        return (request.results ?? []).map { DetectedWidget(rect: pixels($0.boundingBox, size: size), shape: .roundedRect) }
    }

    /// Floating designs are mostly text: the union of Vision's text boxes and the salient objects
    /// (a big handwritten number may only be salient), padded.
    /// Salient objects as card candidates: a card that blends into the wallpaper on one side has
    /// no closed contour and may escape rectangle detection (eval 2026-11-02, a dark pill on a dark
    /// gradient). The edge and corner checks decide whether each is a card and its shape.
    static func salientCandidates(_ image: CGImage, size: CGSize) -> [DetectedWidget] {
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil else { return [] }
        let objects: [VNRectangleObservation] = request.results?.first?.salientObjects ?? []
        return objects.map { DetectedWidget(rect: pixels($0.boundingBox, size: size), shape: .roundedRect) }
    }

    static func floatingContent(_ image: CGImage, size: CGSize) -> DetectedWidget? {
        let saliency = VNGenerateObjectnessBasedSaliencyImageRequest()
        let text = VNDetectTextRectanglesRequest()
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([saliency, text])) != nil else { return nil }
        let salient: [CGRect] = (saliency.results?.first?.salientObjects ?? []).map { $0.boundingBox }
        let texts: [CGRect] = (text.results ?? []).map { $0.boundingBox }
        let boxes = salient + texts
        guard !boxes.isEmpty else { return nil }
        let union = boxes.map { pixels($0, size: size) }.reduce(CGRect.null) { $0.union($1) }
        let pad = floatingPadding * max(union.width, union.height)
        let padded = union.insetBy(dx: -pad, dy: -pad).intersection(CGRect(origin: .zero, size: size))
        // Content covering nearly everything is the widget itself: use the whole image.
        guard area(padded) < 0.9 * size.width * size.height else { return nil }
        return DetectedWidget(rect: padded.integral, shape: .none)
    }
    #endif

    /// Vision's normalized box (origin bottom left) in pixels (origin top left).
    static func pixels(_ box: CGRect, size: CGSize) -> CGRect {
        CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height, width: box.width * size.width, height: box.height * size.height)
    }

    static func bounds(_ points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    /// Shoelace formula.
    static func polygonArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 2 else { return 0 }
        var sum: CGFloat = 0
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    // MARK: Pixels

    /// An image as 8-bit RGBA, top row first.
    struct RGBA {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init?(_ image: CGImage) {
            width = image.width
            height = image.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            bytes = buffer
        }

        func color(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            let cx = min(max(x, 0), width - 1)
            let cy = min(max(y, 0), height - 1)
            let index = (cy * width + cx) * 4
            return (Double(bytes[index]) / 255, Double(bytes[index + 1]) / 255, Double(bytes[index + 2]) / 255)
        }
    }

    /// A real card edge: just inside the middle of at least three sides the color differs from
    /// just outside (a card, a pill or a circle all touch the middle of their box's sides).
    /// The inside is sampled at 4 % and 12 % of the short side, since a detected box can overshoot
    /// the card a little (a pill's round ends, eval 2026-11-02).
    static func hasEdge(_ rect: CGRect, in pixels: RGBA) -> Bool {
        let short = min(rect.width, rect.height)
        let out = max(3, 0.03 * short)
        // Per side: the outward direction and the point in the middle of the side.
        let sides: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.midX, y: rect.minY), 0, -1), (CGPoint(x: rect.midX, y: rect.maxY), 0, 1),
            (CGPoint(x: rect.minX, y: rect.midY), -1, 0), (CGPoint(x: rect.maxX, y: rect.midY), 1, 0),
        ]
        func differs(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Bool {
            abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2) > 0.15
        }
        let differing = sides.filter { point, dx, dy in
            let outside = pixels.color(Int(point.x + dx * out), Int(point.y + dy * out))
            return [0.04, 0.12].contains { depth in
                let inside = pixels.color(Int(point.x - dx * max(3, depth * short)), Int(point.y - dy * max(3, depth * short)))
                return differs(inside, outside)
            }
        }
        return differing.count >= 3
    }

    /// The card's color: on the left and right sides, the first inside sample (4 % or 12 % deep)
    /// that differs from just outside, so a box overshooting the card doesn't sample the wallpaper.
    static func cardColors(of rect: CGRect, in pixels: RGBA) -> [(Double, Double, Double)] {
        let short = min(rect.width, rect.height)
        let midY = Int(rect.midY)
        let out = Int(max(3, 0.03 * short))
        var colors: [(Double, Double, Double)] = []
        for (edge, direction) in [(Int(rect.minX), 1), (Int(rect.maxX), -1)] {
            let outside = pixels.color(edge - direction * out, midY)
            for depth in [0.04, 0.12] {
                let inside = pixels.color(edge + direction * Int(max(3, depth * short)), midY)
                if abs(inside.0 - outside.0) + abs(inside.1 - outside.1) + abs(inside.2 - outside.2) > 0.15 {
                    colors.append(inside)
                    break
                }
            }
        }
        return colors
    }

    /// The box grown or trimmed to the card (eval 2026-11-02: half a pill from saliency, a box
    /// overshooting a pill's ends): from just inside each side's middle (first moving inward to the
    /// card's color if needed), walk outward until `gap` pixels in a row aren't the card's color,
    /// so text on the card doesn't stop the walk. Unchanged when the walk looks wrong.
    static func refined(_ rect: CGRect, in pixels: RGBA, size: CGSize) -> CGRect {
        let colors = cardColors(of: rect, in: pixels)
        guard !colors.isEmpty else { return rect }
        let short = min(rect.width, rect.height)
        let gap = max(6, Int(0.15 * short))
        let inset = Int(max(3, 0.04 * short))
        func isCard(_ x: Int, _ y: Int) -> Bool {
            let c = pixels.color(x, y)
            return colors.contains { abs($0.0 - c.0) + abs($0.1 - c.1) + abs($0.2 - c.2) < 0.18 }
        }
        /// `point(t)` is the pixel at position t on the scan line; returns the last card position.
        func edge(from start: Int, step: Int, limit: Int, _ point: (Int) -> (Int, Int)) -> Int {
            var position = start
            var moved = 0
            while !isCard(point(position).0, point(position).1), moved < Int(0.15 * short) {
                position -= step
                moved += 1
            }
            var last = position
            while position != limit, abs(position - last) < gap {
                position += step
                if isCard(point(position).0, point(position).1) { last = position }
            }
            return last
        }
        let midX = Int(rect.midX)
        let midY = Int(rect.midY)
        let left = edge(from: Int(rect.minX) + inset, step: -1, limit: 0) { ($0, midY) }
        let right = edge(from: Int(rect.maxX) - inset, step: 1, limit: pixels.width - 1) { ($0, midY) }
        let top = edge(from: Int(rect.minY) + inset, step: -1, limit: 0) { (midX, $0) }
        let bottom = edge(from: Int(rect.maxY) - inset, step: 1, limit: pixels.height - 1) { (midX, $0) }
        let grown = CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
        guard grown.width >= 0.5 * rect.width, grown.height >= 0.5 * rect.height, !touchesEdge(grown, size: size) else { return rect }
        return grown
    }

    /// The corner radius of the card in `rect`, from how far each corner's diagonal runs before
    /// it reaches the card's color (sampled just inside the middle of the left and right edges):
    /// a corner of radius r leaves r(√2 − 1) along the diagonal. The median of the four corners.
    static func cornerRadius(of rect: CGRect, in pixels: RGBA) -> CGFloat? {
        let card = cardColors(of: rect, in: pixels)
        guard !card.isEmpty else { return nil }
        func matches(_ c: (Double, Double, Double)) -> Bool {
            card.contains { abs($0.0 - c.0) + abs($0.1 - c.1) + abs($0.2 - c.2) < 0.18 }
        }
        let limit = Int(min(rect.width, rect.height) / 2)
        var distances: [CGFloat] = []
        for (startX, startY, stepX, stepY) in [(rect.minX, rect.minY, 1, 1), (rect.maxX - 1, rect.minY, -1, 1),
                                                (rect.minX, rect.maxY - 1, 1, -1), (rect.maxX - 1, rect.maxY - 1, -1, -1)] {
            var step = 0
            while step < limit, !matches(pixels.color(Int(startX) + step * stepX, Int(startY) + step * stepY)) { step += 1 }
            guard step < limit else { return nil }   // never reached the card: not a solid card
            distances.append(CGFloat(step) * 2.0.squareRoot())
        }
        let median = distances.sorted()[distances.count / 2]
        return median / (2.0.squareRoot() - 1)
    }

    // MARK: Crop and colors

    /// The part of the image the AI sees: the widget's box, inside the image.
    public static func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clipped = rect.integral.intersection(bounds)
        guard !clipped.isNull, clipped.width >= 8, clipped.height >= 8 else { return nil }
        return image.cropping(to: clipped)
    }

    /// The wallpaper's main color: the most common color (quantized) in a ring just outside
    /// `rect`, or along the image's edge when the ring has no room. For the area outside a
    /// circle or capsule card and for floating designs, editable in the editor.
    public static func wallpaperColor(_ image: CGImage, around rect: CGRect) -> String? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let ring = max(4, Int(0.04 * Double(max(rect.width, rect.height))))
        let outer = rect.insetBy(dx: CGFloat(-ring), dy: CGFloat(-ring))
        var counts: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        func add(_ x: Int, _ y: Int) {
            let index = (y * width + x) * 4
            let (r, g, b) = (Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            let entry = counts[key] ?? (0, 0, 0, 0)
            counts[key] = (entry.count + 1, entry.r + r, entry.g + g, entry.b + b)
        }
        let step = max(1, max(width, height) / 400)
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let point = CGPoint(x: x, y: y)
                let inRing = outer.contains(point) && !rect.contains(point)
                let onEdge = x < step * 2 || y < step * 2 || x >= width - step * 2 || y >= height - step * 2
                if inRing || onEdge { add(x, y) }
            }
        }
        guard let best = counts.values.max(by: { $0.count < $1.count }), best.count > 0 else { return nil }
        return String(format: "#%02X%02X%02X", best.r / best.count, best.g / best.count, best.b / best.count)
    }
}
