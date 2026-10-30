import Foundation
import SwiftUI

/// Which den is open, the dens opened before, and whether the terms were agreed.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var current: DenLink?
    @Published private(set) var dens: [DenLink]
    @Published private(set) var agreed: Bool
    /// Bumped to load the den's page again (a push opening a room).
    @Published private(set) var loads = 0
    @Published var error: String?
    /// A den a link from elsewhere asks to open, waiting for its person's yes.
    @Published var asked: DenLink?

    private let store = UserDefaults.standard

    private init() {
        #if DEBUG
        // UI tests start from nothing.
        if ProcessInfo.processInfo.arguments.contains("-reset") {
            for k in ["agreed", "dens", "current"] { store.removeObject(forKey: k) }
        }
        #endif
        agreed = store.bool(forKey: "agreed")
        dens = (store.data(forKey: "dens")).flatMap { try? JSONDecoder().decode([DenLink].self, from: $0) } ?? []
        current = (store.data(forKey: "current")).flatMap { try? JSONDecoder().decode(DenLink.self, from: $0) }
    }

    func agree() {
        agreed = true
        store.set(true, forKey: "agreed")
    }

    /// Opens what someone typed or pasted: a den's address or an invite link.
    func open(text: String) {
        #if DEBUG
        let link = DenLink(text, allowLocal: true)
        #else
        let link = DenLink(text)
        #endif
        guard let link else { error = "That is not a den's address or an invite link."; return }
        open(link)
    }

    func open(_ link: DenLink) {
        error = nil
        let kept = DenLink(origin: link.origin)
        dens.removeAll { $0 == kept }
        dens.insert(kept, at: 0)
        current = link
        loads += 1
        save()
    }

    /// A universal link or epeaky://open?url=…, from anywhere: a den not
    /// opened before waits for its person's yes (`asked`).
    func open(url: URL) {
        var text = url.absoluteString
        if url.scheme == "epeaky" {
            guard let inner = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value else { return }
            text = inner
        }
        #if DEBUG
        let link = DenLink(text, allowLocal: true)
        #else
        let link = DenLink(text)
        #endif
        guard let link else { return }
        if agreed && dens.contains(where: { $0.origin == link.origin }) { open(link) }
        // One question at a time: a link that comes while one waits is dropped.
        else if asked == nil { asked = link }
    }

    /// The answer to the question shown for `link`, and only for it.
    func answer(_ yes: Bool, for link: DenLink?) {
        guard let link, link == asked else { return }
        asked = nil
        if yes { agree(); open(link) }
    }

    func openFromPush(origin: String, room: String?) {
        guard let o = URL(string: origin) else { return }
        let safe = room.flatMap { $0.range(of: #"^[A-Za-z0-9_-]{1,80}$"#, options: .regularExpression) != nil ? $0 : nil }
        open(DenLink(origin: o, fragment: safe.map { "room=" + $0 }))
    }

    /// Back to the start screen, to open another den.
    func switchDen() {
        current = nil
        save()
    }

    func forget(_ link: DenLink) {
        dens.removeAll { $0.origin == link.origin }
        save()
    }

    private func save() {
        store.set(try? JSONEncoder().encode(dens), forKey: "dens")
        store.set(try? JSONEncoder().encode(current.map { DenLink(origin: $0.origin) }), forKey: "current")
    }
}
