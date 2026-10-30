import UserNotifications

/// Opens a den's push on the phone and shows the den's own words: its name
/// and which room ("a private room" for one). If it cannot, the relay's
/// "New message" stays.
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        if let shown = PushContent.opened(request.content.userInfo) {
            content.title = shown.title
            content.body = shown.body
            content.userInfo["den"] = shown.den
            if let room = shown.room {
                content.userInfo["room"] = room
                content.threadIdentifier = room
            }
        }
        contentHandler(content)
    }

    override func serviceExtensionTimeWillExpire() {}
}
