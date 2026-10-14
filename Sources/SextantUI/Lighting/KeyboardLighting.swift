import Foundation
import Observation
import SextantApplication
import SextantDomain

extension LayoutWindowModel {
    /// This window's layer shows on the keyboard (the Lighting inspector's switch, Keyboard ▸ Preview Lighting on Keyboard;
    /// ADR 0051). Off at every launch. Turning it on shows the Lighting lens; leaving it, opening another layout or
    /// closing the window turns it off.
    var previewsLighting: Bool {
        get { lightingPreview?.isHeld(by: self) == true }
        set {
            guard let lightingPreview, let session else { return }
            guard newValue else { return lightingPreview.release(for: self) }
            // A refused claim changes nothing: the switch is disabled with the reason.
            guard (try? lightingPreview.claim(for: self, title: session.layout.title)) != nil else { return }
            lens = .lighting
            destination = .layer(session.selection.layer)
        }
    }

    /// Why this window can't preview lighting now; nil when it can or does. Without a live session there is no keyboard.
    var lightingPreviewRefusal: LightingPreviewRefusal? {
        guard let lightingPreview else { return .noKeyboard }
        return lightingPreview.refusal(for: self)
    }

    /// Why the preview that is on here shows nothing on the keyboard: the keyboard's state (unplugged, flash mode, held by
    /// another app), or Live View still connecting. Nil while it shows or is off.
    var lightingPreviewPause: String? {
        guard previewsLighting, live?.canSend != true else { return nil }
        return lightingPreview?.keyboardRefusal?.localizedDescription
            ?? String(localized: "Waiting for Live View to connect to the keyboard.")
    }

    /// The shown layer's LED colors while this window previews them on the Lighting lens's board; nil otherwise.
    var keyboardLightingFrame: [HexColor?]? {
        guard previewsLighting, lens == .lighting, page == nil, let session else { return nil }
        let layer = session.selection.layer
        return (0..<BoardDefinition.voyager.keyCount).map { session.layout.ledColor(layer: layer, index: $0) }
    }

    /// Sends the shown layer's lighting to the keyboard for the window's lifetime while the preview is on: after each
    /// change to the layout (a rename too, for other windows' "Previewing in …") and each layer change; the preview sends
    /// only what changed. Leaving the Lighting lens or its board ends the preview, and so does the window going away.
    func feedKeyboardLighting() async {
        guard let lightingPreview else { return }
        for await frame in Observations({ self.keyboardLightingFrame }) {
            if let frame, let title = session?.layout.title {
                lightingPreview.show(frame, for: self, title: title)
            } else {
                lightingPreview.release(for: self)
            }
        }
        lightingPreview.release(for: self)
    }
}
