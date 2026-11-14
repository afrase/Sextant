// Checks a Sparkle EdDSA signature against a public key (ADR 0070), so a release is never signed with a key the
// shipped apps don't trust. Used by scripts/appcast.
//   swift scripts/verify-update-signature.swift <public key, base64> <signature, base64> <file>
import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4 else {
    FileHandle.standardError.write(Data("usage: verify-update-signature <public key> <signature> <file>\n".utf8))
    exit(2)
}
guard let raw = Data(base64Encoded: args[1]), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else {
    FileHandle.standardError.write(Data("SUPublicEDKey isn't a base64 Ed25519 public key.\n".utf8))
    exit(1)
}
guard let signature = Data(base64Encoded: args[2]), let file = FileManager.default.contents(atPath: args[3]) else {
    FileHandle.standardError.write(Data("Couldn't read the signature or the file.\n".utf8))
    exit(1)
}
guard key.isValidSignature(signature, for: file) else {
    FileHandle.standardError.write(
        Data("The signature doesn't match SUPublicEDKey: SPARKLE_ED_PRIVATE_KEY isn't the key the apps trust.\n".utf8))
    exit(1)
}
