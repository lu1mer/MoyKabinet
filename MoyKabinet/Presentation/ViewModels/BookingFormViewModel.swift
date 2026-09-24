import Foundation
import Combine

/// Owns a booking draft. Nothing reaches the repository until the user confirms it.
@MainActor
final class BookingFormViewModel: ObservableObject {
    @Published var start: Date
    @Published var clientID: UUID?
    @Published var serviceID: UUID?
    @Published var serviceName = ""
    @Published var minutes = 60
    @Published var priceText = ""
    @Published var note = ""
    @Published var recurrence: RecurrencePattern = .none
    @Published var repeatCount = 8
    @Published private(set) var data = CabinetData()

    let editing: Appointment?
    private var configured = false

    init(date: Date, editing: Appointment? = nil, clientID: UUID? = nil) {
        self.editing = editing
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"), editing == nil {
            let calendar = Calendar.current
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
            start = calendar.date(byAdding: .hour, value: 10, to: tomorrow) ?? tomorrow
        } else {
            start = date
        }
        self.clientID = editing?.clientID ?? clientID
        if let editing {
            serviceName = editing.serviceName
            minutes = editing.minutes
            priceText = String(editing.price)
            note = editing.note ?? ""
        }
    }

    func configure(with data: CabinetData) {
        self.data = data
        guard !configured else { return }
        configured = true
        if editing == nil, let first = activeServices.first {
            select(first)
            if abs(start.timeIntervalSinceNow) < 90,
               let slot = BookingRules.nextAvailableSlot(startingAt: start, profile: data.settings,
                                                         appointments: data.appointments, minutes: first.minutes) {
                start = slot
            }
        }
    }

    func update(data: CabinetData) {
        guard self.data != data else { return }
        self.data = data
    }

    var clients: [Client] {
        data.clients.filter { $0.archived != true || $0.id == clientID }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var recentClients: [Client] {
        let lastVisit = Dictionary(grouping: data.appointments, by: \.clientID)
            .mapValues { $0.map(\.start).max() ?? .distantPast }
        return clients.sorted {
            let lhs = lastVisit[$0.id] ?? .distantPast
            let rhs = lastVisit[$1.id] ?? .distantPast
            if lhs == rhs { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return lhs > rhs
        }
    }

    var activeServices: [Service] { data.services.filter { $0.archived != true } }
    var selectedClient: Client? { clients.first { $0.id == clientID } }

    var conflict: Bool {
        !conflictingSeriesStarts.isEmpty
    }

    private var bookingCalendar: Calendar {
        var value = Calendar.current
        value.timeZone = TimeZone(identifier: data.settings.timezone) ?? .current
        return value
    }

    var seriesStarts: [Date] {
        guard editing == nil, recurrence != .none else { return [start] }
        return (0..<repeatCount).compactMap {
            bookingCalendar.date(byAdding: .weekOfYear, value: $0 * recurrence.weekInterval, to: start)
        }
    }

    var conflictingSeriesStarts: [Date] {
        let existing = data.appointments.filter { $0.id != editing?.id }
        return seriesStarts.filter { BookingRules.overlaps(start: $0, minutes: minutes, appointments: existing) }
    }

    var canSave: Bool {
        clientID != nil && !serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (15...480).contains(minutes) && (0...1_000_000).contains(Int(priceText) ?? -1) && !conflict
    }

    var suggestedSlot: Date? {
        BookingRules.nextSlot(on: start, profile: data.settings,
                              appointments: data.appointments.filter { $0.id != editing?.id }, minutes: minutes)
    }

    func select(_ service: Service) {
        serviceID = service.id
        serviceName = service.name
        minutes = service.minutes
        priceText = String(service.price)
    }

    func setDay(_ day: Date, calendar: Calendar) {
        let time = calendar.dateComponents([.hour, .minute], from: start)
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = time.hour
        parts.minute = time.minute
        if let value = calendar.date(from: parts) { start = value }
    }

    func availableSlots(calendar: Calendar, limit: Int = 6, now: Date = .now) -> [Date] {
        let profile = data.settings
        guard profile.weekdays.contains(calendar.component(.weekday, from: start)) else { return [] }
        let day = calendar.startOfDay(for: start)
        guard var cursor = calendar.date(byAdding: .hour, value: profile.openingHour, to: day),
              let close = calendar.date(byAdding: .hour, value: profile.closingHour, to: day) else { return [] }
        var result: [Date] = []
        let appointments = data.appointments.filter { $0.id != editing?.id }
        while cursor.addingTimeInterval(Double(minutes) * 60) <= close && result.count < limit {
            if cursor >= now && !BookingRules.overlaps(start: cursor, minutes: minutes, appointments: appointments) {
                result.append(cursor)
            }
            cursor = cursor.addingTimeInterval(15 * 60)
        }
        return result
    }

    func appointment() -> Appointment? {
        appointments().first
    }

    func appointments() -> [Appointment] {
        guard canSave, let clientID, let price = Int(priceText) else { return [] }
        let repeated = editing == nil && recurrence != .none
        let seriesID = repeated ? UUID() : editing?.recurrenceSeriesID
        return seriesStarts.enumerated().map { index, date in
            Appointment(id: editing?.id ?? UUID(), clientID: clientID, serviceName: serviceName,
                        start: date, minutes: minutes, price: price,
                        status: editing?.status ?? .planned, note: note,
                        recurrenceSeriesID: seriesID,
                        recurrenceIndex: repeated ? index : editing?.recurrenceIndex)
        }
    }
}
