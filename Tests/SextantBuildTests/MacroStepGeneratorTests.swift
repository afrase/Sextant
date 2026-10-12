import Foundation
import SextantApplication
import SextantDomain
import Testing

@testable import SextantBuild

/// Macro steps reach `SEND_STRING` as `SS_TAP(X_…)`; a code with no `X_` name would not compile, so the generator refuses
/// it on its key, as the live issue does (ADR 0042). Drafts aren't built.
@Suite(.enabled(if: QMKGeneratorGoldenTests.reference != nil, "needs SEXTANT_REFERENCE"))
struct MacroStepGeneratorTests {
    let identity = FirmwareIdentity(serial: "KlgM7/40xJ7M")

    func layout() throws -> KeyboardLayout {
        try KeyboardLayout(oryxJSON: Data(contentsOf: QMKGeneratorGoldenTests.example("voyager-XlrR4.json")))
    }

    @Test func refusesAStepSendStringCantType() throws {
        var layout = try layout()
        let first = try #require(layout.macros.first)
        layout.updateMacro(at: first.locator) { $0.steps[2] = MacroStep(code: "MO") }
        guard case let .key(ref) = first.locator else { throw CocoaError(.featureUnsupported) }
        let key = KeyRef(layer: ref.layer, index: ref.index)
        #expect(throws: GeneratorError.unsupported("“MO” as a macro step", key)) { try QMKGenerator().generate(layout, identity: identity) }
    }

    @Test func draftsAreNotBuilt() throws {
        let plain = try QMKGenerator().generate(layout(), identity: identity)
        var drafted = try layout()
        drafted.addMacroDraft(Macro(steps: [MacroStep(code: "QK_BOOT")]))
        #expect(try QMKGenerator().generate(drafted, identity: identity).files == plain.files)
    }
}
