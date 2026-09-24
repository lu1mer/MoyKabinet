import Foundation

@MainActor
protocol NotificationScheduling {
    func requestAuthorization() async throws -> Bool
    func schedule(appointments: [Appointment], enabled: Bool)
}
