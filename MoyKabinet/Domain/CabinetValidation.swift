import Foundation

extension CabinetData {
    func validated() throws -> CabinetData {
        guard (schemaVersion ?? 1) <= 4 else { throw DataIssue.invalid("Эта копия создана более новой версией приложения.") }
        guard clients.count <= 50_000, appointments.count <= 200_000, services.count <= 1000,
              Set(clients.map(\.id)).count == clients.count,
              Set(services.map(\.id)).count == services.count,
              Set(appointments.map(\.id)).count == appointments.count else { throw DataIssue.invalid("Некорректная структура данных.") }
        let clientIDs = Set(clients.map(\.id))
        for c in clients {
            guard !c.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, c.name.count <= 200, c.notes.count <= 10_000,
                  (c.photos ?? []).count <= 8, (c.photos ?? []).allSatisfy({ $0.count <= 1_000_000 }),
                  (c.telegram?.count ?? 0) <= 200, (c.email?.count ?? 0) <= 320, (c.link?.count ?? 0) <= 1000 else { throw DataIssue.invalid("Проверьте имя, контакты, заметки и фотографии клиента.") }
        }
        for s in services {
            guard !s.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, s.name.count <= 200, (15...480).contains(s.minutes), (0...1_000_000).contains(s.price) else { throw DataIssue.invalid("Проверьте длительность и стоимость услуги.") }
        }
        for a in appointments {
            guard clientIDs.contains(a.clientID), (15...480).contains(a.minutes), (0...1_000_000).contains(a.price), !a.serviceName.isEmpty, a.start.timeIntervalSince1970.isFinite else { throw DataIssue.invalid("Одна из записей содержит некорректные данные.") }
            guard (a.calendarEventID?.count ?? 0) <= 1000, (a.calendarID?.count ?? 0) <= 1000, (a.calendarName?.count ?? 0) <= 500,
                  (a.recurrenceIndex ?? 0) >= 0 else { throw DataIssue.invalid("Некорректные данные календаря.") }
        }
        let active = appointments.filter { $0.status != .cancelled }.sorted { $0.start < $1.start }
        for (a, b) in zip(active, active.dropFirst()) where a.end > b.start { throw DataIssue.invalid("Записи пересекаются по времени.") }
        let p = settings
        guard !p.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, p.name.count <= 200, p.specialty.count <= 200, (0...23).contains(p.openingHour), (1...24).contains(p.closingHour), p.openingHour < p.closingHour,
              !p.weekdays.isEmpty, p.weekdays.allSatisfy({ (1...7).contains($0) }), TimeZone(identifier: p.timezone) != nil else { throw DataIssue.invalid("Проверьте рабочие часы и дни недели.") }
        return self
    }
}
