import Foundation
import Combine

@MainActor
final class CabinetStore: ObservableObject {
    @Published private(set) var data = CabinetData()
    @Published var error: String?
    @Published var notice: String?
    @Published private(set) var loaded = true
    private let repository: any CabinetRepository
    private let commands = CabinetCommands()
    private let notifications: any NotificationScheduling
    private var canSave = true
    var activeClients: [Client] { data.clients.filter { $0.archived != true }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var activeServices: [Service] { data.services.filter { $0.archived != true } }
    var calendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; c.locale = Locale(identifier: "ru_RU"); c.timeZone = TimeZone(identifier: data.settings.timezone) ?? .current; return c }

    init(file: URL? = nil, repository: (any CabinetRepository)? = nil, notifications: (any NotificationScheduling)? = nil) {
        #if DEBUG
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let location = testing ? URL.documentsDirectory.appending(path: "ui-testing-cabinet.json") : (file ?? URL.documentsDirectory.appending(path: "cabinet.json"))
        if testing && ProcessInfo.processInfo.arguments.contains("--reset-ui-data") { try? FileManager.default.removeItem(at: location) }
        #else
        let location = file ?? URL.documentsDirectory.appending(path: "cabinet.json")
        #endif
        self.repository = repository ?? FileCabinetRepository(file: location)
        self.notifications = notifications ?? LocalNotificationScheduler()
        do { if let state = try self.repository.load() { data = state } }
        catch { canSave = false; loaded = false; self.error = "Не удалось открыть данные. Исходный файл сохранён. Восстановите резервную копию в разделе «Кабинет»." }
    }

    @discardableResult
    func commit(_ next: CabinetData, restoring: Bool = false) -> Bool {
        guard canSave || restoring else { error = "Восстановите данные из резервной копии."; return false }
        do {
            var checked = try next.validated()
            checked.schemaVersion = 4; checked.profile = checked.settings
            try repository.save(checked)
            if data != checked { data = checked }; canSave = true; loaded = true
            scheduleReminders()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func client(_ id: UUID) -> Client? { data.clients.first { $0.id == id } }
    func visits(on date: Date) -> [Appointment] {
        data.appointments.filter { calendar.isDate($0.start, inSameDayAs: date) }.sorted { $0.start < $1.start }
    }
    func saveClient(_ client: Client) -> Bool {
        commit(commands.saving(client, in: data))
    }
    func archiveClient(_ client: Client) -> Bool {
        do { return commit(try commands.archiving(client, in: data)) }
        catch { self.error = error.localizedDescription; return false }
    }
    func deleteClient(_ id: UUID) -> Bool {
        commit(commands.deletingClient(id, in: data))
    }
    func saveService(_ service: Service) -> Bool {
        commit(commands.saving(service, in: data))
    }
    func addService(_ service: Service) -> Bool { saveService(service) }
    func saveVisit(_ visit: Appointment) -> Bool {
        do { return commit(try commands.saving(visit, in: data)) }
        catch { self.error = error.localizedDescription; return false }
    }
    func saveVisits(_ visits: [Appointment]) -> Bool {
        do {
            var next = data
            for visit in visits { next = try commands.saving(visit, in: next) }
            return commit(next)
        } catch { self.error = error.localizedDescription; return false }
    }
    func book(clientID: UUID, service: Service, start: Date) -> Bool {
        saveVisit(Appointment(clientID: clientID, serviceName: service.name, start: start, minutes: service.minutes, price: service.price))
    }
    @discardableResult func setStatus(_ id: UUID, _ status: VisitStatus) -> Bool {
        do {
            guard let next = try commands.settingStatus(id, to: status, in: data) else { return false }
            return commit(next)
        } catch { self.error = error.localizedDescription; return false }
    }
    func cancelSeries(_ seriesID: UUID, from start: Date) -> Bool {
        var next = data
        var changed = false
        for index in next.appointments.indices where next.appointments[index].recurrenceSeriesID == seriesID && next.appointments[index].start >= start {
            next.appointments[index].status = .cancelled
            changed = true
        }
        return changed && commit(next)
    }
    func saveProfile(_ profile: Profile) -> Bool { var next = data; next.profile = profile; return commit(next) }
    func applyAppearance(profession: ProfessionPreset, theme: AppTheme) -> Bool {
        var next = data
        var profile = next.settings
        let previous = profile.professionPreset
        profile.profession = profession
        profile.appTheme = theme
        if profile.specialty.isEmpty || profile.specialty == previous.specialty { profile.specialty = profession.specialty }
        next.profile = profile

        let originalNames = Set(ProfessionPreset.beauty.starterServices.map(\.name))
        let currentNames = Set(next.services.filter { $0.archived != true }.map(\.name))
        if next.appointments.isEmpty && currentNames == originalNames {
            next.services = profession.starterServices.map { Service(name: $0.name, minutes: $0.minutes, price: $0.price) }
        } else {
            let known = Set(next.services.map { $0.name.lowercased() })
            for template in profession.starterServices where !known.contains(template.name.lowercased()) {
                next.services.append(Service(name: template.name, minutes: template.minutes, price: template.price))
            }
        }
        return commit(next)
    }

    func importCalendarEvents(_ events: [CalendarEventSnapshot], ownerTitle: String, now: Date = .now) -> CalendarImportResult? {
        let calendarClientID = UUID(uuidString: "CA1E0000-0000-4000-8000-000000000001")!
        var next = data
        var previousByEvent: [String: Appointment] = [:]
        for visit in next.appointments {
            if let eventID = visit.calendarEventID { previousByEvent[eventID] = visit }
        }
        next.appointments.removeAll { $0.calendarEventID != nil && $0.end >= now }

        if !events.isEmpty && !next.clients.contains(where: { $0.id == calendarClientID }) {
            next.clients.append(Client(id: calendarClientID, name: ownerTitle, phone: "", notes: "Служебная карточка событий системного календаря.", archived: true))
        }

        var imported = 0
        var skipped = 0
        for event in events.sorted(by: { $0.start < $1.start }) {
            guard event.start.addingTimeInterval(Double(event.minutes) * 60) > now else { continue }
            let visit = Appointment(
                id: previousByEvent[event.externalID]?.id ?? UUID(),
                clientID: calendarClientID,
                serviceName: String((event.title.isEmpty ? "Событие календаря" : event.title).prefix(200)),
                start: event.start,
                minutes: min(480, max(15, event.minutes)),
                price: 0,
                status: .planned,
                note: "Импортировано из «\(event.calendarName)»",
                calendarEventID: String(event.externalID.prefix(1000)),
                calendarID: String(event.calendarID.prefix(1000)),
                calendarName: String(event.calendarName.prefix(500))
            )
            if BookingRules.overlaps(start: visit.start, minutes: visit.minutes, appointments: next.appointments, excluding: visit.id) {
                skipped += 1
            } else {
                next.appointments.append(visit)
                imported += 1
            }
        }
        guard commit(next) else { return nil }
        return CalendarImportResult(imported: imported, skippedConflicts: skipped)
    }

    func removeFutureCalendarEvents(now: Date = .now) -> Bool {
        var next = data
        next.appointments.removeAll { $0.calendarEventID != nil && $0.end >= now }
        return commit(next)
    }
    func restore(_ bytes: Data) -> Bool {
        guard bytes.count <= 50_000_000 else { error = "Резервная копия слишком большая (максимум 50 МБ)."; return false }
        do { return commit(try JSONDecoder().decode(CabinetData.self, from: bytes), restoring: true) }
        catch { self.error = "Не удалось прочитать копию: \(error.localizedDescription)"; return false }
    }
    func exportData() throws -> Data {
        guard loaded else { return try repository.rawData() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(data)
    }
    func deleteAll() -> Bool { commit(CabinetData(), restoring: true) }
    func setReminders(_ enabled: Bool) async {
        if enabled {
            do {
                let granted = try await notifications.requestAuthorization()
                guard granted else { error = "Уведомления выключены в настройках iPhone. Разрешите их для напоминаний."; return }
            } catch { self.error = "Не удалось включить уведомления."; return }
        }
        var p = data.settings; p.reminders = enabled; _ = saveProfile(p)
    }
    func scheduleReminders() {
        notifications.schedule(appointments: data.appointments, enabled: data.settings.reminders)
    }
    func addDemo() {
        guard data.clients.isEmpty && data.appointments.isEmpty else { return }
        var next = data
        next.clients = [
            Client(name: "Анна Смирнова", phone: "", notes: "Молочные оттенки, мягкий квадрат."),
            Client(name: "Мария Иванова", phone: "", notes: "Предпочитает короткую длину."),
            Client(name: "София Ким", phone: "", notes: "Любит лаконичный дизайн.")
        ]
        let day = calendar.startOfDay(for: .now)
        next.appointments = [
            Appointment(clientID: next.clients[0].id, serviceName: "Маникюр с покрытием", start: day.addingTimeInterval(10 * 3600), minutes: 90, price: 2500, status: .paid),
            Appointment(clientID: next.clients[1].id, serviceName: "Педикюр", start: day.addingTimeInterval(13 * 3600), minutes: 90, price: 3000),
            Appointment(clientID: next.clients[2].id, serviceName: "Маникюр с покрытием", start: day.addingTimeInterval(16 * 3600), minutes: 90, price: 2500)
        ]
        _ = commit(next)
    }
}
