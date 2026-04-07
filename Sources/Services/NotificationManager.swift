import Foundation
import UserNotifications
import AppKit

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self
    }

    func requestAuthorizationIfNeeded(completion: ((Bool) -> Void)? = nil) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else {
                DispatchQueue.main.async { completion?(false) }
                return
            }

            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { completion?(true) }
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    DispatchQueue.main.async { completion?(granted) }
                }
            case .denied:
                DispatchQueue.main.async {
                    completion?(false)
                    self.showPermissionDeniedAlert()
                }
            @unknown default:
                DispatchQueue.main.async { completion?(false) }
            }
        }
    }

    func showEjected(_ volumeName: String) {
        show(title: "Volume Ejected", body: "\(volumeName) was ejected.")
    }

    func showEjectFailed(_ volumeName: String, details: String) {
        show(title: "Eject Failed", body: "\(volumeName) could not be ejected. \(details)")
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    private func show(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request) { [weak self] error in
            guard let self, let error else { return }
            // UNErrorCodeNotificationsNotAllowed (1) means permission was denied —
            // not an actionable error, so don't bother the user with an alert.
            let nsError = error as NSError
            if nsError.domain == UNErrorDomain && nsError.code == 1 { return }
            DispatchQueue.main.async {
                self.showDeliveryFailedAlert(details: error.localizedDescription)
            }
        }
    }

    private func showPermissionDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Notifications Disabled"
        alert.informativeText = "Enable notifications for MenuBarFS in System Settings > Notifications to receive connect and eject updates."
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func showDeliveryFailedAlert(details: String) {
        let alert = NSAlert()
        alert.messageText = "Notification Delivery Failed"
        alert.informativeText = details
        alert.alertStyle = .warning
        alert.runModal()
    }
}