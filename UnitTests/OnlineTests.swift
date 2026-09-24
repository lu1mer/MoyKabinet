import XCTest
@testable import MoyKabinet

final class OnlineTests: XCTestCase {
    @MainActor func testNativeServerRoundTrip() async throws {
        let root = "http://127.0.0.1:8787"
        var health = URLRequest(url: URL(string: root + "/health")!); health.timeoutInterval = 2
        guard (try? await URLSession.shared.data(for: health)) != nil else { throw XCTSkip("Запустите ASP.NET Core сервер на 127.0.0.1:8787 для интеграционного теста.") }
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CabinetStore(file: file), online = OnlineManager(testing: true)
        let client = Client(name: "Тест синхронизации", phone: "", notes: "Локально")
        XCTAssertTrue(store.saveClient(client))
        var profile = store.data.settings; profile.weekdays = [1,2,3,4,5,6,7]; profile.timezone = "Europe/Moscow"
        XCTAssertTrue(store.saveProfile(profile))
        await online.create(server: root, store: store)
        if online.credentials == nil, online.message?.contains("Нужен вход") == true {
            throw XCTSkip("Продовый сервер требует авторизованную интеграционную сессию.")
        }
        XCTAssertNotNil(online.credentials, online.message ?? "Не создан кабинет")
        guard let credentials = online.credentials else { return }
        var edited = client; edited.notes = "После синхронизации"
        XCTAssertTrue(store.saveClient(edited))
        await online.sync(store)
        XCTAssertFalse(online.failed, online.message ?? "Ошибка синхронизации")
        var owner = URLRequest(url: URL(string: root + "/api/cabinets/\(credentials.id)/state")!)
        owner.setValue("Bearer \(credentials.ownerKey)", forHTTPHeaderField: "Authorization")
        let (bytes, _) = try await URLSession.shared.data(for: owner)
        let remote = try JSONDecoder().decode(ServerReply.self, from: bytes)
        XCTAssertEqual(remote.state.clients.first?.notes, edited.notes)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(identifier: "Europe/Moscow")
        let url = root + "/api/public/\(credentials.id)/slots?service=\(store.activeServices[0].id.uuidString)&date=\(formatter.string(from: tomorrow))"
        let (slotsData, _) = try await URLSession.shared.data(from: URL(string: url)!)
        struct Slot: Decodable { var start: Double }
        struct Slots: Decodable { var slots: [Slot] }
        let slots = try JSONDecoder().decode(Slots.self, from: slotsData)
        XCTAssertFalse(slots.slots.isEmpty)
        if let slot = slots.slots.first {
            var request = URLRequest(url: URL(string: root + "/api/public/\(credentials.id)/book")!)
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["serviceID":store.activeServices[0].id.uuidString,"start":slot.start,"name":"Онлайн-клиент","phone":"+7 000 000-00-00","consent":true,"requestID":UUID().uuidString])
            let (_, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 201)
            await online.sync(store)
            XCTAssertFalse(online.failed, online.message ?? "Ошибка загрузки")
            XCTAssertEqual(store.data.appointments.count, 1)
            XCTAssertTrue(store.data.clients.contains { $0.name == "Онлайн-клиент" })
        }
        await online.deleteRemote()
        XCTAssertNil(online.credentials)
    }
}
