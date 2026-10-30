import CryptoKit
import Foundation

/// Opens a den's push on the phone: RFC 8291 (aes128gcm, one record). The
/// relay and Apple carry it sealed; only the key this phone made opens it.
enum WebPush {
    struct Keys {
        let privateKey: P256.KeyAgreement.PrivateKey
        let auth: Data
        var publicKey: Data { privateKey.publicKey.x963Representation }
    }

    static func newKeys() -> Keys {
        var auth = Data(count: 16)
        _ = auth.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        return Keys(privateKey: P256.KeyAgreement.PrivateKey(), auth: auth)
    }

    /// The push's words, or nil if this key does not open it.
    static func open(_ sealed: Data, keys: Keys) -> Data? {
        let body = Data(sealed)
        // salt (16) | record size (4) | key id length (1) | the sender's key (65) | record
        guard body.count > 21 + 65 + 16, body[20] == 65 else { return nil }
        let salt = body.subdata(in: 0..<16)
        let senderKey = body.subdata(in: 21..<86)
        let record = body.subdata(in: 86..<body.count)
        guard let sender = try? P256.KeyAgreement.PublicKey(x963Representation: senderKey),
              let shared = try? keys.privateKey.sharedSecretFromKeyAgreement(with: sender) else { return nil }
        let info = Data("WebPush: info".utf8) + Data([0]) + keys.publicKey + senderKey
        let ikm = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: keys.auth, sharedInfo: info, outputByteCount: 32)
        let cek = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: Data("Content-Encoding: aes128gcm".utf8) + Data([0]), outputByteCount: 16)
        let nonce = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: salt, info: Data("Content-Encoding: nonce".utf8) + Data([0]), outputByteCount: 12)
        guard let n = try? AES.GCM.Nonce(data: nonce.withUnsafeBytes { Data($0) }),
              let box = try? AES.GCM.SealedBox(nonce: n, ciphertext: record.dropLast(16), tag: record.suffix(16)),
              var plain = try? AES.GCM.open(box, using: cek) else { return nil }
        // Padding: zeros, after the last record's delimiter (2).
        while plain.last == 0 { plain.removeLast() }
        guard plain.last == 2 else { return nil }
        plain.removeLast()
        return plain
    }
}

extension Data {
    init?(base64url s: String) {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        self.init(base64Encoded: b)
    }

    var base64url: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
