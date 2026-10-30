import CryptoKit
import Foundation
import Security

/// A den's push address on this phone: the relay's address, the APNs token it
/// was made for, and the key that opens the den's pushes. Kept in the
/// keychain the app and its notification extension share, one item a den.
struct PushSub: Codable, Equatable {
    let origin: String
    var endpoint: String
    var token: String
    let key: Data
    let auth: Data

    /// The relay's id for the address (the last part of its path), which comes with each push.
    var id: String { URL(string: endpoint)?.lastPathComponent ?? "" }
    var keys: WebPush.Keys? {
        (try? P256.KeyAgreement.PrivateKey(rawRepresentation: key)).map { WebPush.Keys(privateKey: $0, auth: auth) }
    }
}

enum PushStore {
    static let service = "io.infinityteam.epeaky.push"

    static func all() -> [PushSub] {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnData as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let items = out as? [Data] else { return [] }
        return items.compactMap { try? JSONDecoder().decode(PushSub.self, from: $0) }
    }

    static func find(origin: String) -> PushSub? { all().first { $0.origin == origin } }
    static func find(id: String) -> PushSub? { all().first { $0.id == id } }

    @discardableResult
    static func save(_ sub: PushSub) -> Bool {
        remove(origin: sub.origin)
        guard let data = try? JSONEncoder().encode(sub) else { return false }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: sub.origin,
            kSecValueData as String: data,
            // The extension opens pushes while the phone is locked, after its first unlock.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func remove(origin: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: origin]
        SecItemDelete(q as CFDictionary)
    }
}

/// What a push from a den says, opened with the key of the address it came to.
enum PushContent {
    struct Shown: Equatable { let title: String; let body: String; let den: String; let room: String? }

    static func opened(_ info: [AnyHashable: Any], subs: (String) -> PushSub? = PushStore.find(id:)) -> Shown? {
        guard let id = info["s"] as? String, let w = info["w"] as? String, let sealed = Data(base64Encoded: w),
              let sub = subs(id), let keys = sub.keys, let plain = WebPush.open(sealed, keys: keys),
              let j = try? JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let title = j["title"] as? String, let body = j["body"] as? String else { return nil }
        let tag = (j["tag"] as? String).flatMap { $0.range(of: #"^[A-Za-z0-9_-]{1,80}$"#, options: .regularExpression) != nil ? $0 : nil }
        return Shown(title: String(title.prefix(80)), body: String(body.prefix(200)), den: sub.origin, room: tag)
    }
}
