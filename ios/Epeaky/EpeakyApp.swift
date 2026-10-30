import SwiftUI
import UserNotifications

@main
struct EpeakyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if let den = state.current, state.agreed {
                    DenView(den: den, state: state).id(state.loads)
                } else {
                    StartView(state: state)
                }
            }
            .background(Color("Background").ignoresSafeArea())
            .preferredColorScheme(.dark)
            // An invite link to gen-epeaky (universal link), or epeaky://open?url=<a den's link>.
            .onOpenURL { state.open(url: $0) }
            .alert("Open \(state.asked?.host ?? "this den")?", isPresented: Binding(get: { state.asked != nil }, set: { if !$0 { state.answer(false, for: state.asked) } }), presenting: state.asked) { link in
                Button("Cancel", role: .cancel) { state.answer(false, for: link) }
                Button("Open") { state.answer(true, for: link) }
            } message: { _ in
                Text(state.agreed ? "A link asks to open this den. Its host sees this device in it." : "A link asks to open this den. Its host sees this device in it. Opening it agrees to the terms: no objectionable content or abusive behaviour.")
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in Push.shared.got(token: deviceToken.hex) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in Push.shared.got(token: nil) }
    }

    /// With the den open in front, its own page shows what came; a push for another den shows.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let den = notification.request.content.userInfo["den"] as? String
        let showing = await MainActor.run { AppState.shared.current?.origin.absoluteString }
        return den != nil && den == showing ? [] : [.banner, .sound]
    }

    /// A tapped notification opens its den, at its room.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let den = (info["den"] as? String) ?? (info["s"] as? String).flatMap { PushStore.find(id: $0)?.origin }
        let room = info["room"] as? String
        await MainActor.run { if let den { AppState.shared.openFromPush(origin: den, room: room) } }
    }
}
