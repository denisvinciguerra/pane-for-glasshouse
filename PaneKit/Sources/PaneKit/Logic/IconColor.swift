import CoreGraphics
import Foundation
import ImageIO

/// An sRGB colour, each component from 0 to 1: the plain background an app icon is drawn on,
/// which a pinned tile takes on around the icon.
public struct IconColor: Equatable, Sendable {
    public let red, green, blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    /// The pixel two in from the icon's top left corner; `nil` for data that is not an image, or
    /// an edge more than half transparent.
    public init?(edgeOf data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // Rows run from the top in memory.
        let i = (min(2, height - 1) * width + min(2, width - 1)) * 4
        let alpha = Double(pixels[i + 3]) / 255
        guard alpha >= 0.5 else { return nil }
        self.init(red: Double(pixels[i]) / 255 / alpha, green: Double(pixels[i + 1]) / 255 / alpha,
                  blue: Double(pixels[i + 2]) / 255 / alpha)
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// A contrast ratio under 1.5 against `background`: a tile of this colour needs its edge drawn.
    public func blends(into background: IconColor) -> Bool {
        let (a, b) = (luminance + 0.05, background.luminance + 0.05)
        return max(a, b) / min(a, b) < 1.5
    }
}
