import CryptoKit
import XCTest
@testable import Epeaky

final class DenLinkTests: XCTestCase {
    func testAddressesAndInviteLinks() {
        XCTAssertEqual(DenLink("gen-epeaky.zyn-network.com")?.origin.absoluteString, "https://gen-epeaky.zyn-network.com")
        XCTAssertEqual(DenLink(" https://Chat.Example.org/some/path?q=1 ")?.origin.absoluteString, "https://chat.example.org")
        let invite = DenLink("https://chat.example.org/#invite=\(String(repeating: "ab", count: 32))")
        XCTAssertEqual(invite?.fragment, "invite=\(String(repeating: "ab", count: 32))")
        XCTAssertEqual(invite?.url.absoluteString, "https://chat.example.org/#invite=\(String(repeating: "ab", count: 32))")
        XCTAssertNil(DenLink("https://chat.example.org/#room=general")?.fragment, "only an invite is kept from a link")
        XCTAssertEqual(DenLink("https://chat.example.org:8443")?.origin.absoluteString, "https://chat.example.org:8443")
    }

    func testRefused() {
        XCTAssertNil(DenLink("http://chat.example.org"), "https only")
        XCTAssertNil(DenLink("localhost"), "no dotless names")
        XCTAssertNil(DenLink("http://localhost:4000"), "a dev den only in a debug build, when asked")
        XCTAssertNotNil(DenLink("http://localhost:4000", allowLocal: true))
        XCTAssertNil(DenLink("javascript:alert(1)"))
        XCTAssertNil(DenLink("https://exa mple.org"))
        XCTAssertNil(DenLink(""))
    }

    func testOrigin() {
        let d = DenLink("https://chat.example.org")!
        XCTAssertTrue(d.isOrigin(scheme: "https", host: "chat.example.org", port: 0))
        XCTAssertTrue(d.isOrigin(scheme: "https", host: "chat.example.org", port: 443))
        XCTAssertFalse(d.isOrigin(scheme: "https", host: "chat.example.org.evil.example", port: 0))
        XCTAssertFalse(d.isOrigin(scheme: "http", host: "chat.example.org", port: 0))
        XCTAssertFalse(d.isOrigin(scheme: "https", host: "chat.example.org", port: 8443))
    }
}

/// A push sealed by the den's own Den.Push.encrypt (mix run, 30 Oct 2026).
enum DenPush {
    static let priv = Data(base64url: "sEWbaFyxGomUqx4XZ6rCI-KI37_4Ft8z6VlNkl5-rII")!
    static let pub = Data(base64url: "BNRu5vEl6rHCNcCivVm-JDxAx6t1tLzrkpJrrRw2Ih2jxuRXFehnQKtcI9sspPoIpp6s11ZO_HjXocwuzT85Nao")!
    static let auth = Data(base64url: "ipW6X2LPccPkaNdge9MNSQ")!
    static let body = Data(base64url: "woLpOqAGMuAxztWRzPId0gAAEABBBMIGmwL3mLjiB1ZlhDu7TZbxrIV1PtYuBYl2V_iznV15iopv2-67Xoo26iZPlfDEFQT5nlb1K76l1ohPG90MgWCm88q2chEwNOPgmM9CIHeae3ynRf-xcy2XscujXP__1cGe8COyquSqyzaugyJBgKWO-gBdQ8aVByST1EAprP099Si1L8usrwIP30PiGQ4eRJpyqlFDO8WfBSL5XAOtsCIppa3fdGi8MI7poT9cuvj_ixq2KEuU8g")!
    static let words = #"{"title":"Builders","body":"New message in a private room","tag":"p-00112233445566778899aabbccddeeff"}"#
}

final class WebPushTests: XCTestCase {
    func testOpensWhatTheDenSealed() throws {
        let key = try P256.KeyAgreement.PrivateKey(rawRepresentation: DenPush.priv)
        XCTAssertEqual(key.publicKey.x963Representation, DenPush.pub)
        let plain = WebPush.open(DenPush.body, keys: .init(privateKey: key, auth: DenPush.auth))
        XCTAssertEqual(plain.map { String(decoding: $0, as: UTF8.self) }, DenPush.words)
    }

    func testAnotherKeyOrAChangedPushOpensNothing() throws {
        let key = try P256.KeyAgreement.PrivateKey(rawRepresentation: DenPush.priv)
        XCTAssertNil(WebPush.open(DenPush.body, keys: WebPush.newKeys()))
        XCTAssertNil(WebPush.open(DenPush.body, keys: .init(privateKey: key, auth: Data(count: 16))))
        var changed = DenPush.body
        changed[changed.count - 20] ^= 1
        XCTAssertNil(WebPush.open(changed, keys: .init(privateKey: key, auth: DenPush.auth)))
        XCTAssertNil(WebPush.open(Data(count: 40), keys: .init(privateKey: key, auth: DenPush.auth)))
    }

    func testTheNotificationShowsTheDensWords() {
        let sub = PushSub(origin: "https://chat.example.org", endpoint: "https://push.epeaky.zyn-network.com/w/abc123", token: "ab", key: DenPush.priv, auth: DenPush.auth)
        let info: [AnyHashable: Any] = ["s": "abc123", "w": DenPush.body.base64EncodedString()]
        let shown = PushContent.opened(info) { $0 == sub.id ? sub : nil }
        XCTAssertEqual(shown, .init(title: "Builders", body: "New message in a private room", den: "https://chat.example.org", room: "p-00112233445566778899aabbccddeeff"))
        XCTAssertNil(PushContent.opened(["s": "other", "w": DenPush.body.base64EncodedString()]) { $0 == sub.id ? sub : nil }, "an address this phone does not have")
    }
}

@MainActor
final class LinkFromElsewhereTests: XCTestCase {
    func testADenNotOpenedBeforeWaitsForAYes() {
        let s = AppState.shared
        s.open(url: URL(string: "epeaky://open?url=https%3A%2F%2Fnew-den.example.org")!)
        XCTAssertEqual(s.asked?.host, "new-den.example.org", "asked, not opened")
        XCTAssertNotEqual(s.current?.host, "new-den.example.org")
        let shown = s.asked
        s.open(url: URL(string: "epeaky://open?url=https%3A%2F%2Fother.example.org")!)
        XCTAssertEqual(s.asked, shown, "a second link while one waits does not replace it")
        s.answer(true, for: DenLink("other.example.org"))
        XCTAssertEqual(s.asked, shown, "a yes counts only for the den it was asked about")
        s.answer(false, for: shown)
        XCTAssertNil(s.asked)
        XCTAssertNotEqual(s.current?.host, "new-den.example.org", "no means not opened")
        s.open(url: URL(string: "epeaky://open?url=https%3A%2F%2Fnew-den.example.org")!)
        s.answer(true, for: s.asked)
        XCTAssertEqual(s.current?.host, "new-den.example.org")
        s.open(url: URL(string: "https://new-den.example.org/#invite=\(String(repeating: "cd", count: 32))")!)
        XCTAssertNil(s.asked, "a den opened before opens straight away")
        XCTAssertEqual(s.current?.fragment, "invite=\(String(repeating: "cd", count: 32))")
        s.forget(DenLink(origin: URL(string: "https://new-den.example.org")!))
        s.switchDen()
    }
}
