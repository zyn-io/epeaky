import Foundation

/// What the app and its notification extension share.
enum Epeaky {
    /// The public den, opened by default.
    static let defaultDen = URL(string: "https://gen-epeaky.zyn-network.com")!
    /// Epeaky's push relay: web push from a den, to Apple's push service.
    static let relay = URL(string: "https://push.epeaky.zyn-network.com")!
    static let terms = URL(string: "https://epeaky.zyn-network.com/terms")!
    static let appGroup = "group.io.infinityteam.epeaky"
    /// Dens whose passkeys this app may use (its associated domains).
    static let passkeyHosts: Set<String> = ["gen-epeaky.zyn-network.com"]
    #if DEBUG
    static let pushEnvironment = "sandbox"
    #else
    static let pushEnvironment = "production"
    #endif
}

/// A den's address, or an invite link to one, as someone typed or pasted it.
struct DenLink: Equatable, Hashable, Codable {
    /// scheme://host[:port], no path.
    let origin: URL
    /// "invite=…" from an invite link, else nil.
    let fragment: String?

    /// https only; http only for this Mac's own dev den, in a debug build.
    init?(_ text: String, allowLocal: Bool = false) {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.contains("://") { t = "https://" + t }
        guard let c = URLComponents(string: t), let host = c.host?.lowercased(), !host.isEmpty,
              host.range(of: #"^[a-z0-9.-]+$"#, options: .regularExpression) != nil else { return nil }
        let local = host == "localhost" || host == "127.0.0.1"
        guard local ? allowLocal && (c.scheme == "http" || c.scheme == "https") : c.scheme == "https" && host.contains(".") else { return nil }
        var o = URLComponents()
        o.scheme = c.scheme
        o.host = host
        o.port = c.port
        guard let origin = o.url else { return nil }
        self.origin = origin
        let invite = c.fragment.flatMap { $0.range(of: #"^invite=[0-9A-Za-z_-]{16,128}$"#, options: .regularExpression) != nil ? $0 : nil }
        self.fragment = invite
    }

    init(origin: URL, fragment: String? = nil) {
        self.origin = origin
        self.fragment = fragment
    }

    /// What the web view opens.
    var url: URL { URL(string: origin.absoluteString + "/" + (fragment.map { "#" + $0 } ?? ""))! }
    var host: String { origin.host ?? "" }

    /// Whether `origin` (as WebKit gives a frame's) is this den's.
    func isOrigin(scheme: String?, host: String?, port: Int?) -> Bool {
        let defaultPort = origin.scheme == "https" ? 443 : 80
        let mine = origin.port ?? defaultPort
        let theirs = (port ?? 0) == 0 ? defaultPort : port!
        return scheme == origin.scheme && host?.lowercased() == origin.host && theirs == mine
    }
}
