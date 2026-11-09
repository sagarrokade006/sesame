import CryptoKit
import Foundation
import LocalAuthentication
import Observation
import OpenDirectory
import SesameCore

struct SecuritySettings: Codable, Equatable {
    var usesTurnChallenge = false
    var requiresAttention = true
    var scansWhenLocking = false
    var trustHours = TrustWindow.defaultHours
    var matchRule = MatchRule()
}

/// Everything sensitive lives in one encrypted file, including settings, so nothing can be weakened from outside.
struct VaultContents: Codable {
    var profiles: [FaceProfile] = []
    var sealedPassword: Data?
    var activity = ActivityHistory()
    var passwordHealth = PasswordHealth()
    var settings = SecuritySettings()
}

enum VaultError: LocalizedError {
    case keyMissing
    case unreadable
    case keychain(OSStatus)
    case locked
    case wrongPassword

    var errorDescription: String? {
        switch self {
        case .keyMissing: return "Sesame's key is missing, so your saved data can't be opened. Nothing was changed."
        case .unreadable: return "Sesame's saved data couldn't be read. Nothing was changed."
        case .keychain(let status): return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
        case .locked: return "Unlock Sesame first."
        case .wrongPassword: return "That isn't your Mac password."
        }
    }
}

private enum VaultKeychain {
    static let service = "com.sagarrokade.sesame.vault-key"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "vault",
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
        SecItemDelete(sharedQuery as CFDictionary)
    }

    /// Builds distributed outside Xcode don't carry the entitlement the protected Keychain needs, so they use the
    /// regular login Keychain and ask for Touch ID or the Mac password themselves before reading the key.
    private static var sharedQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "vault-shared",
        ]
    }

    static func loadOrCreateWithoutEntitlement(mayCreate: Bool) throws -> SymmetricKey {
        var query = sharedQuery
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound else { throw VaultError.keychain(status) }
        guard mayCreate else { throw VaultError.keyMissing }

        let key = SymmetricKey(size: .bits256)
        var attributes = sharedQuery
        attributes[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        let added = SecItemAdd(attributes as CFDictionary, nil)
        guard added == errSecSuccess else { throw VaultError.keychain(added) }
        return key
    }

    /// Prompts for Touch ID or the Mac password. A brand-new key is read back so creating one also requires approval.
    static func loadOrCreate(reason: String, mayCreate: Bool) throws -> SymmetricKey {
        do {
            return try read(reason: reason)
        } catch VaultError.keychain(errSecItemNotFound) {
            guard mayCreate else { throw VaultError.keyMissing }
        }

        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, &accessError
        ) else { throw VaultError.keychain(errSecParam) }

        var attributes = baseQuery
        attributes[kSecAttrAccessControl as String] = access
        attributes[kSecValueData as String] = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
        return try read(reason: reason)
    }

    private static func read(reason: String) throws -> SymmetricKey {
        let context = LAContext()
        context.localizedReason = reason
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { throw VaultError.keychain(status) }
        return SymmetricKey(data: data)
    }
}

@MainActor
@Observable
final class Vault {
    private(set) var contents = VaultContents()
    private(set) var isOpen = false
    private(set) var trust: TrustWindow?
    private(set) var hasRecentApproval = false

    @ObservationIgnored private var key: SymmetricKey?
    @ObservationIgnored private var approvalExpiry: Task<Void, Never>?

    private static let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("Sesame", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("vault.sesame")
    }()

    private var fileExists: Bool { FileManager.default.fileExists(atPath: Self.fileURL.path) }

    func open() async throws {
        let mayCreate = !fileExists
        let opened: SymmetricKey
        do {
            opened = try await Task.detached(priority: .userInitiated) {
                try VaultKeychain.loadOrCreate(reason: "open Sesame", mayCreate: mayCreate)
            }.value
        } catch VaultError.keychain(errSecMissingEntitlement) {
            guard (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "open Sesame")) == true else {
                throw VaultError.keychain(errSecUserCanceled)
            }
            opened = try await Task.detached(priority: .userInitiated) {
                try VaultKeychain.loadOrCreateWithoutEntitlement(mayCreate: mayCreate)
            }.value
        }

        var loaded = VaultContents()
        if fileExists {
            guard let sealed = try? Data(contentsOf: Self.fileURL),
                  let box = try? AES.GCM.SealedBox(combined: sealed),
                  let plain = try? AES.GCM.open(box, using: opened),
                  let decoded = try? JSONDecoder().decode(VaultContents.self, from: plain)
            else { throw VaultError.unreadable }
            loaded = decoded
        }
        key = opened
        contents = loaded
        isOpen = true
        trust = TrustWindow(grantedAt: Date(), hours: loaded.settings.trustHours)
        persist()
    }

    func close() {
        key = nil
        contents = VaultContents()
        isOpen = false
        trust = nil
    }

    var isTrusted: Bool { isOpen && trust?.isValid(at: Date()) == true }

    func closeIfExpired() {
        if isOpen, !isTrusted { close() }
    }

    func update(_ change: (inout VaultContents) -> Void) {
        guard isOpen else { return }
        change(&contents)
        persist()
    }

    /// Like Face ID asking for the passcode: an open vault isn't enough to weaken security. Lasts two minutes.
    func requireApproval(_ reason: String) async -> Bool {
        if hasRecentApproval { return true }
        guard (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) == true else {
            return false
        }
        hasRecentApproval = true
        approvalExpiry?.cancel()
        approvalExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled else { return }
            self?.hasRecentApproval = false
        }
        return true
    }

    var hasPassword: Bool { contents.sealedPassword != nil }

    func savePassword(_ password: String) async throws {
        guard let key else { throw VaultError.locked }
        let check = await Task.detached(priority: .userInitiated) { MacPassword.check(password) }.value
        guard check != .rejected else { throw VaultError.wrongPassword }
        let sealed = try AES.GCM.seal(Data(password.utf8), using: key).combined
        update {
            $0.sealedPassword = sealed
            $0.passwordHealth = PasswordHealth()
            $0.passwordHealth.record(check, at: Date())
        }
    }

    /// Plaintext is yours to wipe with `resetBytes` as soon as it has been used.
    func openPassword() throws -> Data {
        guard let key, let sealed = contents.sealedPassword else { throw VaultError.locked }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key)
    }

    /// Each wrong check counts as a failed login, so this only runs when there's a reason to.
    func recheckPassword() async {
        guard var bytes = try? openPassword() else { return }
        let password = String(data: bytes, encoding: .utf8) ?? ""
        bytes.resetBytes(in: 0..<bytes.count)
        let check = await Task.detached(priority: .userInitiated) { MacPassword.check(password) }.value
        update { $0.passwordHealth.record(check, at: Date()) }
    }

    func eraseEverything() {
        close()
        try? FileManager.default.removeItem(at: Self.fileURL)
        VaultKeychain.delete()
    }

    private func persist() {
        guard let key,
              let plain = try? JSONEncoder().encode(contents),
              let sealed = try? AES.GCM.seal(plain, using: key).combined
        else { return }
        try? sealed.write(to: Self.fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.fileURL.path)
    }
}

enum MacPassword {
    nonisolated static func check(_ password: String) -> PasswordCheck {
        do {
            let node = try ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication))
            let record = try node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
            try record.verifyPassword(password)
            return .accepted
        } catch {
            return PasswordCheck.from(openDirectoryCode: (error as NSError).code)
        }
    }
}
