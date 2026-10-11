import Foundation
import SextantApplication
import SextantDomain

/// Generates Oryx-equivalent QMK source for ZSA boards (research 02 §4). Skeleton; the build slice implements it.
public struct QMKGenerator: FirmwareGenerator {
    public init() {}

    public func generate(_ layout: KeyboardLayout, identity: FirmwareIdentity) throws(GeneratorError) -> GeneratedSource {
        throw .unsupported("The generator isn't built yet.", nil)
    }
}
