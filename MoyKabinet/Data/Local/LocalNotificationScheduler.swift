import Foundation
import UserNotifications

struct LocalNotificationScheduler: NotificationScheduling {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func schedule(appointments: [Appointment], enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard enabled else { return }
        let upcoming = appointments.filter {
            $0.calendarEventID == nil && $0.status == .planned && $0.start.addingTimeInterval(-1800) > .now
        }
            .sorted { $0.start < $1.start }.prefix(60)
        for visit in upcoming {
            let content = UNMutableNotificationContent()
            content.title = "Скоро запись"
            content.body = "Через 30 минут начинается следующий визит."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, visit.start.addingTimeInterval(-1800).timeIntervalSinceNow), repeats: false)
            center.add(UNNotificationRequest(identifier: visit.id.uuidString, content: content, trigger: trigger))
        }
    }
}
