// Verifies public inputs only. Private keys never enter this process.
import CryptoKit
import Foundation

func fail() -> Never {
    FileHandle.standardError.write(Data("The archive signature does not match the bundled public key.\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
if arguments.count != 4 { fail() }
guard let publicKeyData = Data(base64Encoded: arguments[2]), publicKeyData.count == 32,
      publicKeyData.base64EncodedString() == arguments[2],
      let signature = Data(base64Encoded: arguments[3]), signature.count == 64,
      signature.base64EncodedString() == arguments[3] else { fail() }
do {
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
    if !publicKey.isValidSignature(signature, for: archive) { fail() }
} catch {
    fail()
}
