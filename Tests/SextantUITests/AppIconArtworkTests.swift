import AppKit
import SwiftUI
import Testing

@testable import SextantUI

/// The icon keeps the macOS grid at every detail tier: a transparent margin around an opaque body, at exactly the pixel
/// size it is drawn for (scripts/icon ships it as AppIcon.icns).
@MainActor
struct AppIconArtworkTests {
    @Test(arguments: [16, 32, 64, 1024])
    func transparentOutsideTheBodyOpaqueInside(pixels: Int) throws {
        let renderer = ImageRenderer(content: AppIconArtwork(pixels: CGFloat(pixels)))
        renderer.scale = CGFloat(pixels) / 1024
        let rep = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        #expect(rep.pixelsWide == pixels && rep.pixelsHigh == pixels)
        #expect(rep.colorAt(x: 0, y: 0)?.alphaComponent == 0)
        #expect(rep.colorAt(x: pixels / 2, y: pixels / 2)?.alphaComponent == 1)
    }
}
