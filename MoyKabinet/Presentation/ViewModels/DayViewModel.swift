import Foundation

/// Read model for the day screen. Rebuilt from the current snapshot when the store publishes a change.
struct DayViewModel {
    let data: CabinetData
    let calendar: Calendar
    let date: Date

    var visits: [Appointment] {
        data.appointments.filter { calendar.isDate($0.start, inSameDayAs: date) }.sorted { $0.start < $1.start }
    }

    var nextSlot: Date? {
        let minutes = data.services.first(where: { $0.archived != true })?.minutes ?? 60
        return BookingRules.nextSlot(on: date, profile: data.settings, appointments: data.appointments, minutes: minutes)
    }

    func clientName(for visit: Appointment) -> String {
        data.clients.first(where: { $0.id == visit.clientID })?.name ?? "Клиент"
    }
}
