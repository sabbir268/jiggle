import UserNotifications

/// "Session ended" notification for timed sessions. Permission is requested when the first timed session starts.
@MainActor
final class SessionNotifier {
    private var requestedAuthorization = false

    func requestAuthorizationIfNeeded() {
        guard !requestedAuthorization else { return }
        requestedAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sessionEnded() {
        let content = UNMutableNotificationContent()
        content.title = "Jiggle session ended"
        content.body = "Your Mac can sleep normally again."
        let request = UNNotificationRequest(identifier: "jiggle.session-ended", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
