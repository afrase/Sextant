import AppKit
import Foundation
import SextantApplication
import SextantDomain
import SwiftUI
import Testing

@testable import SextantUI

/// The key inspector's text fields in a real offscreen window (nothing captured from the screen): what a typed value
/// that isn't stored yet does when the key changes under it, and what the term row shows at its edges (ADR 0041).
@MainActor @Suite(.serialized)
struct TapDanceSliceTests {
    /// A window that counts as key, so focus moves as in the app.
    final class KeyWindow: NSWindow {
        override var isKeyWindow: Bool { true }
        override var canBecomeKey: Bool { true }
    }

    func host(_ model: LayoutWindowModel) -> NSWindow {
        let window = KeyWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 320, height: 1400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: InspectorColumn(model: model).frame(width: 320, height: 1400))
        settle(window)
        return window
    }

    func settle(_ window: NSWindow) {
        for _ in 0..<10 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }

    func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { views($0) } }
    /// The label field first, the term field last.
    func fields(_ window: NSWindow) -> [NSTextField] {
        views(window.contentView ?? NSView()).compactMap { $0 as? NSTextField }.filter(\.isEditable)
    }
    func steppers(_ window: NSWindow) -> [NSStepper] { views(window.contentView ?? NSView()).compactMap { $0 as? NSStepper } }

    /// Types into a field without pressing Return, as a user does before clicking elsewhere.
    func type(_ text: String, into field: NSTextField?, in window: NSWindow) throws {
        let field = try #require(field)
        window.makeFirstResponder(field)
        settle(window)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
        settle(window)
    }

    func keysWithTerms(_ layout: KeyboardLayout) -> Int { layout.layers.reduce(0) { $0 + $1.keys.count { $0.tappingTerm != nil } } }

    /// A button click leaves the field focused, so the row goes with its draft when the key stops using a term; the
    /// draft was for ⏎, not for the transparent key (and so for every transparent key).
    @Test func aTypedTermStaysOffAKeyMadeTransparent() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.setTappingTerm(250, layer: 0, index: 24)
        session.select(key: 24)
        let window = host(model)
        defer { window.close() }
        try type("300", into: fields(window).last, in: window)
        session.makeTransparent()
        settle(window)
        window.makeFirstResponder(nil)
        settle(window)
        #expect(session.layout.key(layer: 0, index: 24) == .transparent)
        #expect(keysWithTerms(session.layout) == 0)
    }

    /// A drag swaps ⏎ away and selects where it landed: the draft lands on neither the key now in its place nor ⏎.
    /// Nor does a label typed for ⏎.
    @Test(arguments: [false, true])
    func aDraftStaysOffAKeySwappedIntoItsPlace(label: Bool) async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.setTappingTerm(250, layer: 0, index: 24)
        session.select(key: 24)
        let window = host(model)
        defer { window.close() }
        try type(label ? "AB" : "300", into: label ? fields(window).first : fields(window).last, in: window)
        session.swapKeys(24, 30)
        session.select(key: 30)
        settle(window)
        window.makeFirstResponder(nil)
        settle(window)
        let moved = try #require(session.layout.key(layer: 0, index: 24))
        #expect(moved.tappingTerm == nil && moved.customLabel == nil)
        #expect(session.layout.key(layer: 0, index: 30)?.tappingTerm == 250)
    }

    /// Moving the selection to another key commits a draft onto the key it was typed for.
    @Test(arguments: [false, true])
    func aDraftCommitsWhenTheSelectionMoves(label: Bool) async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.setTappingTerm(250, layer: 0, index: 24)
        session.select(key: 24)
        let window = host(model)
        defer { window.close() }
        try type(label ? "AB" : "300", into: label ? fields(window).first : fields(window).last, in: window)
        session.select(key: 30)
        settle(window)
        let key = try #require(session.layout.key(layer: 0, index: 24))
        #expect(label ? key.customLabel == "AB" : key.tappingTerm == 300)
    }

    /// The stepper steps through the global term: the value is stored as Global, but the field and stepper stay.
    @Test func theStepperStepsThroughTheGlobalTerm() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.setTappingTerm(210, layer: 0, index: 24)
        session.select(key: 24)
        let window = host(model)
        defer { window.close() }
        for expected in [nil, 190] as [Int?] {
            let stepper = try #require(steppers(window).first)
            stepper.integerValue = -1
            stepper.sendAction(stepper.action, to: stepper.target)
            settle(window)
            #expect(session.layout.key(layer: 0, index: 24)?.tappingTerm == expected)
        }
        #expect(fields(window).last?.stringValue == "190")
    }

    /// A typed value beyond the range, when the term is already at its bound, stores nothing new; the field shows the
    /// stored value, not the typed one.
    @Test func aTypedValueBeyondTheBoundShowsTheStoredOne() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.setTappingTerm(1000, layer: 0, index: 24)
        session.select(key: 24)
        let window = host(model)
        defer { window.close() }
        try type("5000", into: fields(window).last, in: window)
        (fields(window).last?.currentEditor() as? NSTextView)?.insertNewline(nil)
        settle(window)
        #expect(session.layout.key(layer: 0, index: 24)?.tappingTerm == 1000)
        #expect(fields(window).last?.stringValue == "1000")
    }

    /// "Prefer tap in tap-and-hold dances" never shows, apart from the MVP's core-section filter that slice 2.3 drops.
    @Test func theDancesTapActionSettingNeverShows() throws {
        let layout = try KeyboardLayout(oryxJSON: try #require(userLayoutData))
        let tapping = try #require(FirmwareSettings.sections(for: layout).first { $0.id == "tapping" })
        #expect(!tapping.settings.isEmpty && !tapping.settings.contains { $0.id == "dancesTapAction" })
    }
}
