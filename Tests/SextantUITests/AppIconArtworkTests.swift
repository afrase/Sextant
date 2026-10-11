import AppKit
import SwiftUI
import Testing

@testable import SextantUI

/// The icon keeps the macOS grid: a transparent margin around an opaque body (scripts/icon ships it as AppIcon.icns).
@MainActor
struct AppIconArtworkTests {
    @Test(arguments: [false, true])
    func transparentOutsideTheBodyOpaqueInside(small: Bool) throws {
        let renderer = ImageRenderer(content: AppIconArtwork(small: small))
        renderer.scale = 1
        let rep = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        #expect(rep.pixelsWide == 1024 && rep.pixelsHigh == 1024)
        #expect(rep.colorAt(x: 4, y: 4)?.alphaComponent == 0)
        #expect(rep.colorAt(x: 512, y: 512)?.alphaComponent == 1)
    }
}
