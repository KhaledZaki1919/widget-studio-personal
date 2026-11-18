import SwiftUI

/// Draws a spec to an image with the real renderer, at the family's canvas size, for the AI
/// self-review round and the AI eval job (ADR-019). Uses sample data, like gallery previews,
/// so bindings show realistic values; live texts are frozen.
public enum SpecSnapshot {
    /// `accented`: the Tinted/Clear home screen variant (ADR-023), drawn without the background,
    /// which iOS replaces in that mode. `background: false` leaves it out in normal mode too.
    @MainActor
    public static func render(_ spec: WidgetSpec, colors: [String: String] = [:], language: String = "en",
                              date: Date = .now, scale: CGFloat = 3, userImage: CGImage? = nil, accented: Bool = false,
                              background: Bool = true, overrides: [String: String] = [:]) -> CGImage? {
        var context = RenderContext(date: date, language: language, data: .sample(now: date), userImage: userImage)
        context.tokenOverrides = colors
        context.overrides = overrides
        context.freezesLiveText = true
        let canvas = spec.family.canvas
        let view = SpecView(spec: spec, context: context, drawsBackground: background && !accented)
            // ImageRenderer can't draw `Link` and paints a yellow "unsupported" sign instead (AI
            // eval run 5); buttons are invisible anyway.
            .environment(\.specActionButton) { _, _ in AnyView(Color.clear) }
            .environment(\.specAccented, accented)
            .frame(width: canvas.width, height: canvas.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    /// How iOS shows a widget on a Tinted home screen, approximately: every pixel in one light tint,
    /// keeping only its opacity, over a blue glass backdrop. Used by the accented snapshot tests to
    /// show what the user sees (a solid fill turns into a solid block).
    public static func tinted(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: info) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let backdrop: (Double, Double, Double) = (0.29, 0.45, 0.66)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            pixels[index] = UInt8((backdrop.0 * (1 - alpha) + 0.95 * alpha) * 255)
            pixels[index + 1] = UInt8((backdrop.1 * (1 - alpha) + 0.97 * alpha) * 255)
            pixels[index + 2] = UInt8((backdrop.2 * (1 - alpha) + 1.0 * alpha) * 255)
            pixels[index + 3] = 255
        }
        return context.makeImage()
    }

    /// Share of pixels that are nearly opaque (0…1): what turns into solid white when tinted.
    public static func opaqueShare(_ image: CGImage) -> Double {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return 1 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var opaque = 0
        for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] > 230 { opaque += 1 }
        return Double(opaque) / Double(max(width * height, 1))
    }
}
