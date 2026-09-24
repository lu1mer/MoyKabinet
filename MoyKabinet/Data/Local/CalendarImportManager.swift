import Foundation
import EventKit
import Combine

@MainActor
final class CalendarImportManager: ObservableObject {
    @Published private(set) var authorization: EKAuthorizationStatus
    @Published private(set) var calendars: [EKCalendar] = []
    @Published private(set) var enabled: Bool
    @Published private(set) var selectedCalendarIDs: Set<String>
    @Published private(set) var busy = false
    @Published private(set) var lastImport: Date?
    @Published var message: String?

    private let eventStore: EKEventStore
    private let defaults: UserDefaults
    private let enabledKey = "calendarImport.enabled"
    private let calendarIDsKey = "calendarImport.calendarIDs"

    init(eventStore: EKEventStore = EKEventStore(), defaults: UserDefaults = .standard) {
        self.eventStore = eventStore
        self.defaults = defaults
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        if testing && ProcessInfo.processInfo.arguments.contains("--reset-ui-data") {
            defaults.removeObject(forKey: "calendarImport.enabled")
            defaults.removeObject(forKey: "calendarImport.calendarIDs")
        }
        authorization = EKEventStore.authorizationStatus(for: .event)
        enabled = testing ? false : defaults.bool(forKey: "calendarImport.enabled")
        selectedCalendarIDs = testing ? [] : Set(defaults.stringArray(forKey: "calendarImport.calendarIDs") ?? [])
        reloadCalendars()
    }

    var hasFullAccess: Bool { authorization == .fullAccess }

    func connect(store: CabinetStore) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            authorization = EKEventStore.authorizationStatus(for: .event)
            guard granted, hasFullAccess else {
                message = "Разрешите полный доступ к календарю в настройках iPhone."
                return
            }
            reloadCalendars()
            if selectedCalendarIDs.isEmpty { selectedCalendarIDs = Set(calendars.map(\.calendarIdentifier)) }
            enabled = true
            savePreferences()
            await refresh(store, manageBusy: false)
        } catch {
            message = "Не удалось подключить календарь: \(error.localizedDescription)"
        }
    }

    func setEnabled(_ value: Bool) {
        enabled = value && hasFullAccess
        savePreferences()
    }

    func setCalendar(_ id: String, selected: Bool) {
        if selected { selectedCalendarIDs.insert(id) } else { selectedCalendarIDs.remove(id) }
        savePreferences()
    }

    func refresh(_ store: CabinetStore, manageBusy: Bool = true) async {
        guard enabled else { return }
        authorization = EKEventStore.authorizationStatus(for: .event)
        guard hasFullAccess else {
            enabled = false
            savePreferences()
            message = "Доступ к календарю отключён в настройках iPhone."
            return
        }
        guard !busy || !manageBusy else { return }
        if manageBusy { busy = true }
        defer { if manageBusy { busy = false } }

        reloadCalendars()
        let selected = calendars.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        guard !selected.isEmpty else {
            message = "Выберите хотя бы один календарь."
            return
        }
        let start = Date.now.addingTimeInterval(-6 * 3600)
        let end = Calendar.current.date(byAdding: .day, value: 90, to: .now) ?? .now.addingTimeInterval(90 * 86400)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: selected)
        let snapshots = eventStore.events(matching: predicate).compactMap { event -> CalendarEventSnapshot? in
            guard event.status != .canceled, !event.isAllDay else { return nil }
            let duration = event.endDate.timeIntervalSince(event.startDate)
            guard duration > 0, duration <= 8 * 3600 else { return nil }
            let roundedMinutes = max(15, Int(ceil(duration / 900)) * 15)
            let base = event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? UUID().uuidString
            let identifier = "\(base)#\(Int(event.startDate.timeIntervalSince1970))"
            return CalendarEventSnapshot(
                externalID: identifier,
                calendarID: event.calendar.calendarIdentifier,
                calendarName: event.calendar.title,
                title: event.title ?? "Событие календаря",
                start: event.startDate,
                minutes: roundedMinutes
            )
        }
        let owner = store.data.settings.professionPreset.calendarOwnerTitle
        if let result = store.importCalendarEvents(snapshots, ownerTitle: owner) {
            lastImport = .now
            if result.skippedConflicts > 0 {
                message = "Добавлено: \(result.imported). Пропущено пересечений: \(result.skippedConflicts)."
            } else {
                message = result.imported == 0 ? "Календарь синхронизирован. Новых событий нет." : "События календаря добавлены: \(result.imported)."
            }
        }
    }

    func disconnect(removeImported: Bool, store: CabinetStore) {
        enabled = false
        savePreferences()
        if removeImported { _ = store.removeFutureCalendarEvents() }
        message = removeImported ? "Календарь отключён, будущие импортированные события удалены." : "Автоимпорт календаря выключен."
    }

    func reloadCalendars() {
        authorization = EKEventStore.authorizationStatus(for: .event)
        guard authorization == .fullAccess else { calendars = []; return }
        calendars = eventStore.calendars(for: .event).sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        let available = Set(calendars.map(\.calendarIdentifier))
        selectedCalendarIDs.formIntersection(available)
    }

    private func savePreferences() {
        defaults.set(enabled, forKey: enabledKey)
        defaults.set(Array(selectedCalendarIDs), forKey: calendarIDsKey)
    }
}
