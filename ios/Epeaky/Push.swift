import Foundation
import UIKit
import UserNotifications

/// This phone's push address for a den: Apple's token, made into a web push
/// address at Epeaky's relay, with a key of the phone's own for the den to
/// encrypt to. The den's page asks for it through the bridge.
@MainActor
final class Push {
    static let shared = Push()

    private var token: String?
    private var waiting: [CheckedContinuation<String?, Never>] = []

    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    func got(token: String?) {
        if let token { self.token = token }
        let w = waiting
        waiting = []
        for c in w { c.resume(returning: token) }
    }

    /// The address for `origin` ({endpoint, p256dh, auth}), or nil when notifications are off for the app.
    func subscribe(origin: String) async throws -> [String: String]? {
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else { return nil }
        guard let token = await deviceToken() else { throw Failure(errorDescription: "This phone got no push address from Apple. Notifications work while the app is open.") }
        var sub = PushStore.find(origin: origin)
        if sub == nil || sub!.token != token {
            let endpoint = try await register(token: token)
            let keys = sub?.keys ?? WebPush.newKeys()
            sub = PushSub(origin: origin, endpoint: endpoint, token: token, key: keys.privateKey.rawRepresentation, auth: keys.auth)
            guard PushStore.save(sub!) else { throw Failure(errorDescription: "This phone could not keep its push key.") }
        }
        guard let s = sub, let keys = s.keys else { return nil }
        return ["endpoint": s.endpoint, "p256dh": keys.publicKey.base64url, "auth": s.auth.base64url]
    }

    /// No more pushes from `origin`: the address the den should drop.
    func unsubscribe(origin: String) -> [String: String]? {
        guard let s = PushStore.find(origin: origin) else { return nil }
        PushStore.remove(origin: origin)
        return ["endpoint": s.endpoint]
    }

    private func deviceToken() async -> String? {
        if let token { return token }
        UIApplication.shared.registerForRemoteNotifications()
        return await withCheckedContinuation { c in
            waiting.append(c)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                if self.token == nil, !self.waiting.isEmpty { self.got(token: nil) }
            }
        }
    }

    private func register(token: String) async throws -> String {
        var req = URLRequest(url: Epeaky.relay.appendingPathComponent("register"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["token": token, "env": Epeaky.pushEnvironment])
        let (data, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 200,
              let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let endpoint = j["endpoint"] as? String, endpoint.hasPrefix(Epeaky.relay.absoluteString + "/w/") else {
            throw Failure(errorDescription: "Epeaky's push relay did not answer. Notifications work while the app is open.")
        }
        return endpoint
    }
}
