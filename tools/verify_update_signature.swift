import CryptoKit
import Foundation

// Confirms a release file's signature matches the public key shipped inside the app, using the same check users'
// copies perform. Usage: swift tools/verify_update_signature.swift <file> <base64 signature>

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let plistData = FileManager.default.contents(atPath: "Config/Info.plist"),
      let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
      let publicText = plist["SUPublicEDKey"] as? String,
      let publicData = Data(base64Encoded: publicText),
      let signature = Data(base64Encoded: arguments[2]),
      let file = FileManager.default.contents(atPath: arguments[1])
else {
    print("Missing the file, signature, or public key.")
    exit(1)
}

let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicData)
guard publicKey.isValidSignature(signature, for: file) else {
    print("Signature doesn't match the app's public key.")
    exit(1)
}
print("Signature verified.")
