import Foundation

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case rose
    case graphite
    case indigo

    var id: String { rawValue }
    var title: String {
        switch self {
        case .rose: "Розе"
        case .graphite: "Графит"
        case .indigo: "Индиго"
        }
    }
    var subtitle: String {
        switch self {
        case .rose: "Мягкий и яркий"
        case .graphite: "Строгий и контрастный"
        case .indigo: "Спокойный и интеллектуальный"
        }
    }
}

enum ProfessionPreset: String, Codable, CaseIterable, Identifiable {
    case beauty
    case tutor
    case universal

    var id: String { rawValue }
    var title: String {
        switch self {
        case .beauty: "Бьюти"
        case .tutor: "Репетитор"
        case .universal: "Универсальный"
        }
    }
    var icon: String {
        switch self {
        case .beauty: "sparkles"
        case .tutor: "graduationcap.fill"
        case .universal: "briefcase.fill"
        }
    }
    var specialty: String {
        switch self {
        case .beauty: "Бьюти-мастер"
        case .tutor: "Репетитор"
        case .universal: "Частный специалист"
        }
    }
    var clientTitle: String { self == .tutor ? "Ученик" : "Клиент" }
    var clientsTitle: String { self == .tutor ? "Ученики" : "Клиенты" }
    var serviceTitle: String { self == .tutor ? "Формат" : "Услуга" }
    var servicesTitle: String { self == .tutor ? "Форматы занятий" : "Услуги" }
    var appointmentTitle: String {
        switch self {
        case .beauty: "Запись"
        case .tutor: "Занятие"
        case .universal: "Встреча"
        }
    }
    var appointmentsTitle: String {
        switch self {
        case .beauty: "Записи"
        case .tutor: "Занятия"
        case .universal: "Встречи"
        }
    }
    var newAppointmentTitle: String {
        switch self {
        case .beauty: "Новая запись"
        case .tutor: "Новое занятие"
        case .universal: "Новая встреча"
        }
    }
    var calendarOwnerTitle: String { self == .tutor ? "Личный календарь" : "Календарь" }
    var starterServices: [(name: String, minutes: Int, price: Int)] {
        switch self {
        case .beauty:
            [("Маникюр с покрытием", 90, 2500), ("Педикюр", 90, 3000), ("Снятие покрытия", 30, 500)]
        case .tutor:
            [("Индивидуальное занятие", 60, 1500), ("Подготовка к экзамену", 90, 2200), ("Разбор домашней работы", 45, 1200)]
        case .universal:
            [("Консультация", 60, 2000), ("Онлайн-встреча", 45, 1500), ("Расширенная сессия", 90, 3000)]
        }
    }
}

struct Client: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var phone: String
    var notes: String
    var archived: Bool? = false
    var photos: [Data]? = []
    var telegram: String? = nil
    var email: String? = nil
    var link: String? = nil
}

struct Service: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var minutes: Int
    var price: Int
    var archived: Bool? = false
}

struct Appointment: Identifiable, Codable, Equatable {
    var id = UUID()
    var clientID: UUID
    var serviceName: String
    var start: Date
    var minutes: Int
    var price: Int
    var status: VisitStatus = .planned
    var note: String? = ""
    var calendarEventID: String? = nil
    var calendarID: String? = nil
    var calendarName: String? = nil
    var recurrenceSeriesID: UUID? = nil
    var recurrenceIndex: Int? = nil
    var end: Date { start.addingTimeInterval(Double(minutes) * 60) }
}

enum RecurrencePattern: String, CaseIterable, Identifiable {
    case none
    case weekly
    case biweekly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "Не повторять"
        case .weekly: "Каждую неделю"
        case .biweekly: "Раз в две недели"
        }
    }
    var weekInterval: Int { self == .biweekly ? 2 : 1 }
}

struct CalendarEventSnapshot: Equatable {
    var externalID: String
    var calendarID: String
    var calendarName: String
    var title: String
    var start: Date
    var minutes: Int
}

struct CalendarImportResult: Equatable {
    var imported: Int
    var skippedConflicts: Int
}

enum VisitStatus: String, Codable, CaseIterable {
    case planned = "Запланировано"
    case paid = "Оплачено"
    case cancelled = "Отменено"
}

struct Profile: Codable, Equatable {
    var name = "Мой кабинет"
    var specialty = "Бьюти-мастер"
    var openingHour = 9
    var closingHour = 19
    var weekdays = [2, 3, 4, 5, 6]
    var timezone = TimeZone.current.identifier
    var reminders = false
    var profession: ProfessionPreset? = .beauty
    var appTheme: AppTheme? = .rose

    var professionPreset: ProfessionPreset { profession ?? .beauty }
    var selectedTheme: AppTheme { appTheme ?? .rose }
}

struct CabinetData: Codable, Equatable {
    var clients: [Client] = []
    var services: [Service] = [
        Service(name: "Маникюр с покрытием", minutes: 90, price: 2500),
        Service(name: "Педикюр", minutes: 90, price: 3000),
        Service(name: "Снятие покрытия", minutes: 30, price: 500)
    ]
    var appointments: [Appointment] = []
    var profile: Profile? = Profile()
    var schemaVersion: Int? = 4
    var settings: Profile { profile ?? Profile() }
}

enum DataIssue: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        if case let .invalid(message) = self { return message }
        return nil
    }
}
