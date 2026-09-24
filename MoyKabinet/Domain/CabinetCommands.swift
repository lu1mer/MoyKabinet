import Foundation

/// Business operations on an immutable snapshot. The caller persists the returned state atomically.
struct CabinetCommands {
    func saving(_ client: Client, in data: CabinetData) -> CabinetData {
        var next = data
        if let index = next.clients.firstIndex(where: { $0.id == client.id }) { next.clients[index] = client }
        else { next.clients.append(client) }
        return next
    }

    func archiving(_ client: Client, in data: CabinetData, now: Date = .now) throws -> CabinetData {
        if client.archived != true && data.appointments.contains(where: { $0.clientID == client.id && $0.status == .planned && $0.end > now }) {
            throw DataIssue.invalid("У клиента есть предстоящие записи. Сначала отмените или завершите их.")
        }
        var edited = client
        edited.archived = !(client.archived ?? false)
        return saving(edited, in: data)
    }

    func deletingClient(_ id: UUID, in data: CabinetData) -> CabinetData {
        var next = data
        next.clients.removeAll { $0.id == id }
        next.appointments.removeAll { $0.clientID == id }
        return next
    }

    func saving(_ service: Service, in data: CabinetData) -> CabinetData {
        var next = data
        if let index = next.services.firstIndex(where: { $0.id == service.id }) { next.services[index] = service }
        else { next.services.append(service) }
        return next
    }

    func saving(_ visit: Appointment, in data: CabinetData) throws -> CabinetData {
        guard data.clients.contains(where: { $0.id == visit.clientID }) else { throw DataIssue.invalid("Выберите клиента.") }
        guard visit.status == .cancelled || !BookingRules.overlaps(start: visit.start, minutes: visit.minutes, appointments: data.appointments, excluding: visit.id) else {
            throw DataIssue.invalid("Это время уже занято. Выберите другое время.")
        }
        var next = data
        if let index = next.appointments.firstIndex(where: { $0.id == visit.id }) { next.appointments[index] = visit }
        else { next.appointments.append(visit) }
        return next
    }

    func settingStatus(_ id: UUID, to status: VisitStatus, in data: CabinetData) throws -> CabinetData? {
        guard var visit = data.appointments.first(where: { $0.id == id }) else { return nil }
        visit.status = status
        return try saving(visit, in: data)
    }
}
