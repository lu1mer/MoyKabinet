import Foundation

enum BookingRules {
    static func overlaps(start: Date, minutes: Int, appointments: [Appointment], excluding id: UUID? = nil) -> Bool {
        let end = start.addingTimeInterval(Double(minutes) * 60)
        return appointments.contains { $0.id != id && $0.status != .cancelled && start < $0.end && end > $0.start }
    }

    static func nextSlot(on date: Date, profile: Profile, appointments: [Appointment], minutes: Int = 60, now: Date = .now) -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: profile.timezone) ?? .current
        guard profile.weekdays.contains(calendar.component(.weekday, from: date)) else { return nil }
        let day = calendar.startOfDay(for: date)
        guard var slot = calendar.date(byAdding: .hour, value: profile.openingHour, to: day),
              let close = calendar.date(byAdding: .hour, value: profile.closingHour, to: day) else { return nil }
        while slot.addingTimeInterval(Double(minutes) * 60) <= close {
            if slot >= now && !overlaps(start: slot, minutes: minutes, appointments: appointments) { return slot }
            slot = slot.addingTimeInterval(15 * 60)
        }
        return nil
    }

    /// Finds the first working slot across the following days. Used by quick
    /// booking so opening the form at the end of a day still gives a useful time.
    static func nextAvailableSlot(startingAt start: Date, profile: Profile, appointments: [Appointment], minutes: Int = 60, days: Int = 60, now: Date = .now) -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: profile.timezone) ?? .current
        let firstDay = calendar.startOfDay(for: start)
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { continue }
            let lowerBound = offset == 0 ? max(start, now) : now
            if let slot = nextSlot(on: day, profile: profile, appointments: appointments, minutes: minutes, now: lowerBound) {
                return slot
            }
        }
        return nil
    }
}
