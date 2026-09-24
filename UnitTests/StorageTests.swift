import XCTest
@testable import MoyKabinet

final class StorageTests: XCTestCase {
    @MainActor func testPersistenceAndRecovery() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "cabinet.json")
        let store = CabinetStore(file: file)
        let client = Client(name: "Клиент", phone: "", notes: "Заметка", telegram: "@client_test", email: "client@example.com", link: "example.com")
        XCTAssertTrue(store.saveClient(client))
        let reloaded = CabinetStore(file: file)
        XCTAssertEqual(reloaded.client(client.id)?.notes, "Заметка")
        XCTAssertEqual(reloaded.client(client.id)?.telegram, "@client_test")
        let backup = try store.exportData()
        XCTAssertTrue(store.deleteClient(client.id))
        XCTAssertTrue(store.restore(backup))
        XCTAssertEqual(store.client(client.id)?.name, "Клиент")
    }
    @MainActor func testConflictDoesNotMutateStoredData() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CabinetStore(file: file)
        let client = Client(name: "Клиент", phone: "", notes: "")
        XCTAssertTrue(store.saveClient(client))
        let service = store.activeServices[0], start = Date.now.addingTimeInterval(86400)
        XCTAssertTrue(store.book(clientID: client.id, service: service, start: start))
        let before = try Data(contentsOf: file)
        XCTAssertFalse(store.book(clientID: client.id, service: service, start: start.addingTimeInterval(60)))
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(store.data.appointments.count, 1)
    }
    @MainActor func testArchiveAndServiceSnapshot() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CabinetStore(file: file)
        let client = Client(name: "Клиент", phone: "", notes: "")
        XCTAssertTrue(store.saveClient(client))
        var service = store.activeServices[0]
        XCTAssertTrue(store.book(clientID: client.id, service: service, start: .now.addingTimeInterval(86400)))
        XCTAssertFalse(store.archiveClient(client))
        let original = service.price
        service.price += 1000
        XCTAssertTrue(store.saveService(service))
        XCTAssertEqual(store.data.appointments[0].price, original)
        XCTAssertTrue(store.setStatus(store.data.appointments[0].id, .cancelled))
        XCTAssertTrue(store.archiveClient(client))
        XCTAssertTrue(store.activeClients.isEmpty)
        XCTAssertEqual(store.data.appointments.count, 1)
    }
    @MainActor func testCorruptFileRemainsUntilExplicitRestore() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let broken = Data("broken".utf8); try broken.write(to: file)
        let store = CabinetStore(file: file)
        XCTAssertFalse(store.loaded)
        XCTAssertFalse(store.saveClient(Client(name: "Клиент", phone: "", notes: "")))
        XCTAssertEqual(try Data(contentsOf: file), broken)
        XCTAssertTrue(store.restore(try JSONEncoder().encode(CabinetData())))
        XCTAssertTrue(store.loaded)
    }
    @MainActor func testRescheduleExcludesSelfAndPreservesIdentity() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CabinetStore(file: file)
        let c = Client(name: "Клиент", phone: "", notes: "")
        XCTAssertTrue(store.saveClient(c))
        XCTAssertTrue(store.book(clientID: c.id, service: store.activeServices[0], start: .now))
        var a = store.data.appointments[0]
        a.start = a.start.addingTimeInterval(1800)
        XCTAssertTrue(store.saveVisit(a))
        XCTAssertEqual(store.data.appointments.count, 1)
        XCTAssertEqual(store.data.appointments[0].id, a.id)
    }

    @MainActor func testCalendarImportIsRepeatableAndSkipsConflicts() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CabinetStore(file: file)
        let client = Client(name: "Клиент", phone: "", notes: "")
        XCTAssertTrue(store.saveClient(client))
        let start = Date.now.addingTimeInterval(86_400)
        XCTAssertTrue(store.book(clientID: client.id, service: store.activeServices[0], start: start))

        let events = [
            CalendarEventSnapshot(externalID: "busy", calendarID: "main", calendarName: "Личный", title: "Пересечение", start: start, minutes: 60),
            CalendarEventSnapshot(externalID: "free", calendarID: "main", calendarName: "Личный", title: "Встреча", start: start.addingTimeInterval(10_800), minutes: 45)
        ]
        let first = store.importCalendarEvents(events, ownerTitle: "Календарь")
        XCTAssertEqual(first, CalendarImportResult(imported: 1, skippedConflicts: 1))
        let importedID = store.data.appointments.first { $0.calendarEventID == "free" }?.id

        let second = store.importCalendarEvents(events, ownerTitle: "Календарь")
        XCTAssertEqual(second, CalendarImportResult(imported: 1, skippedConflicts: 1))
        XCTAssertEqual(store.data.appointments.filter { $0.calendarEventID != nil }.count, 1)
        XCTAssertEqual(store.data.appointments.first { $0.calendarEventID == "free" }?.id, importedID)
    }

    @MainActor func testAppearancePresetKeepsDataAndAddsTutorFormats() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CabinetStore(file: file)
        XCTAssertTrue(store.applyAppearance(profession: .tutor, theme: .graphite))
        XCTAssertEqual(store.data.settings.professionPreset, .tutor)
        XCTAssertEqual(store.data.settings.selectedTheme, .graphite)
        XCTAssertTrue(store.activeServices.contains { $0.name == "Индивидуальное занятие" })
    }

    @MainActor func testRecurringSeriesSavesAtomicallyAndCanBeCancelledFromOneLesson() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CabinetStore(file: file)
        let client = Client(name: "Ученик", phone: "", notes: "")
        XCTAssertTrue(store.saveClient(client))
        let seriesID = UUID()
        let first = Date.now.addingTimeInterval(172_800)
        let visits = (0..<4).map { index in
            Appointment(clientID: client.id, serviceName: "Занятие", start: first.addingTimeInterval(Double(index) * 7 * 86_400), minutes: 60, price: 1500, recurrenceSeriesID: seriesID, recurrenceIndex: index)
        }
        XCTAssertTrue(store.saveVisits(visits))
        XCTAssertEqual(store.data.appointments.filter { $0.recurrenceSeriesID == seriesID }.count, 4)
        XCTAssertTrue(store.cancelSeries(seriesID, from: visits[2].start))
        XCTAssertEqual(store.data.appointments.filter { $0.recurrenceSeriesID == seriesID && $0.status == .cancelled }.count, 2)
    }

    @MainActor func testRecurringSeriesConflictDoesNotSavePartialData() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CabinetStore(file: file)
        let client = Client(name: "Ученик", phone: "", notes: "")
        XCTAssertTrue(store.saveClient(client))
        let first = Date.now.addingTimeInterval(172_800)
        XCTAssertTrue(store.book(clientID: client.id, service: store.activeServices[0], start: first.addingTimeInterval(7 * 86_400)))
        let before = store.data.appointments.count
        let series = (0..<3).map { index in
            Appointment(clientID: client.id, serviceName: "Занятие", start: first.addingTimeInterval(Double(index) * 7 * 86_400), minutes: 60, price: 1500, recurrenceSeriesID: UUID(), recurrenceIndex: index)
        }
        XCTAssertFalse(store.saveVisits(series))
        XCTAssertEqual(store.data.appointments.count, before)
    }
}
