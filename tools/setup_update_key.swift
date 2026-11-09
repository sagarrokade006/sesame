import CryptoKit
import Foundation
import Security

// Run once, from the repo root:  swift tools/setup_update_key.swift
//
// Creates the key that proves updates really come from you. The private half goes in your login Keychain and in the
// repo's GitHub Actions secrets, and is never printed. The public half is written to Config/Info.plist.

let repository = "sagarrokade006/sesame"
let plistPath = "Config/Info.plist"

func stop(_ message: String) -> Never {
    print("Stopped: \(message)")
    exit(1)
}

guard FileManager.default.fileExists(atPath: plistPath) else { stop("Run this from the repo root.") }

let ghPaths = [NSHomeDirectory() + "/.local/bin/gh", "/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
guard let gh = ghPaths.first(where: FileManager.default.isExecutableFile(atPath:)) else { stop("GitHub CLI not found.") }

let lookup: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "Sesame update signing key",
    kSecAttrAccount as String: "sesame",
]
guard SecItemCopyMatching(lookup as CFDictionary, nil) == errSecItemNotFound else {
    stop("A signing key already exists. Replacing it would stop existing users from getting updates.")
}

let key = Curve25519.Signing.PrivateKey()
let privateKey = key.rawRepresentation.base64EncodedString()

var item = lookup
item[kSecValueData as String] = Data(privateKey.utf8)
let status = SecItemAdd(item as CFDictionary, nil)
guard status == errSecSuccess else { stop("Couldn't save to Keychain (\(status)).") }

let process = Process()
process.executableURL = URL(fileURLWithPath: gh)
process.arguments = ["secret", "set", "SPARKLE_PRIVATE_KEY", "-R", repository]
let input = Pipe()
process.standardInput = input
try process.run()
input.fileHandleForWriting.write(Data(privateKey.utf8))
input.fileHandleForWriting.closeFile()
process.waitUntilExit()
guard process.terminationStatus == 0 else { stop("Couldn't save the GitHub secret. The key is safe in your Keychain.") }

let url = URL(fileURLWithPath: plistPath)
guard var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any] else {
    stop("Couldn't read \(plistPath).")
}
plist["SUPublicEDKey"] = key.publicKey.rawRepresentation.base64EncodedString()
try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)

print("Done. Update signing is set up.")
