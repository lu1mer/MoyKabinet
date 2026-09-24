import Foundation
import Combine

@MainActor
final class OnlineManager: ObservableObject {
    @Published private(set) var credentials: OnlineCredentials?
    @Published private(set) var busy = false
    @Published var message: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var failed = false
    private var scheduled: Task<Void, Never>?
    private let base: SyncBaseRepository
    private let api: OnlineAPIClient
    private let credentialRepository: any OnlineCredentialRepository
    init(testing: Bool = ProcessInfo.processInfo.arguments.contains("--ui-testing"), api: OnlineAPIClient = OnlineAPIClient(), credentialRepository: (any OnlineCredentialRepository)? = nil) {
        self.api = api
        self.credentialRepository = credentialRepository ?? (testing ? MemoryCredentialRepository() : KeychainCredentialRepository())
        credentials = self.credentialRepository.read()
        let baseURL = testing ? FileManager.default.temporaryDirectory.appending(path: "online-test-\(UUID()).json") : URL.documentsDirectory.appending(path: "online-base.json")
        base = SyncBaseRepository(file: baseURL)
    }
    private func saveCredentials(_ value: OnlineCredentials?) throws {
        try credentialRepository.write(value)
        credentials = value
    }
    var publicURL: URL? { guard let c = credentials else { return nil }; return URL(string: "\(c.server)/book?cabinet=\(c.id)") }
    func create(server: String, store: CabinetStore, accessToken: String? = nil) async {
        guard !busy, credentials == nil else { return }; busy = true; defer { busy = false }
        do {
            let address = try api.normalize(server)
            var snapshot = store.data; snapshot.profile = snapshot.settings; snapshot.schemaVersion = 2
            let reply: ServerReply = try await api.request(address, path: "/api/cabinets", method: "POST", token: accessToken, body: JSONEncoder().encode(["state": snapshot]))
            guard let id = reply.id, let key = reply.ownerKey else { throw DataIssue.invalid("Сервер не выдал ключ кабинета.") }
            let c = OnlineCredentials(server: address, id: id, ownerKey: key)
            try saveCredentials(c)
            try base.save(reply.state)
            lastSync = .now; failed = false; message = "Онлайн-запись включена. Поделитесь ссылкой с клиентами."
            if store.data != snapshot { schedule(store) }
        } catch { failed = true; message = error.localizedDescription }
    }
    func connect(server: String, id: String, key: String, store: CabinetStore) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            guard store.data.clients.isEmpty && store.data.appointments.isEmpty else { throw DataIssue.invalid("Для подключения другого кабинета сохраните резервную копию и очистите локальные данные. Текущий кабинет останется без изменений.") }
            let c = OnlineCredentials(server: try api.normalize(server), id: id.trimmingCharacters(in: .whitespacesAndNewlines), ownerKey: key.trimmingCharacters(in: .whitespacesAndNewlines))
            guard c.id.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil else { throw DataIssue.invalid("Проверьте идентификатор кабинета.") }
            let reply: ServerReply = try await api.request(c.server, path: "/api/cabinets/\(c.id)/state", token: c.ownerKey)
            _ = try reply.state.validated()
            try saveCredentials(c)
            guard store.commit(reply.state, restoring: true) else { throw DataIssue.invalid("Не удалось сохранить данные на iPhone.") }
            try base.save(reply.state); lastSync = .now; failed = false; message = "Кабинет подключён."
        } catch { failed = true; message = error.localizedDescription }
    }
    func schedule(_ store: CabinetStore) {
        guard credentials != nil else { return }
        scheduled?.cancel()
        scheduled = Task {
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            await sync(store)
        }
    }
    func sync(_ store: CabinetStore) async {
        guard let c = credentials, !busy else { return }; busy = true; defer { busy = false }
        do {
            guard store.loaded else { throw DataIssue.invalid("Сначала восстановите локальные данные.") }
            let remote: ServerReply = try await api.request(c.server, path: "/api/cabinets/\(c.id)/state", token: c.ownerKey)
            _ = try remote.state.validated()
            let baseState = try base.load()
            let local = store.data
            let merged = try CabinetMerge.combine(base: baseState, local: local, remote: remote.state)
            struct Update: Encodable { var state: CabinetData; var revision: Int }
            let result: ServerReply
            if merged == remote.state { result = remote }
            else { result = try await api.request(c.server, path: "/api/cabinets/\(c.id)/state", method: "PUT", token: c.ownerKey, body: JSONEncoder().encode(Update(state: merged, revision: remote.revision))) }
            let latest = try CabinetMerge.combine(base: local, local: store.data, remote: result.state)
            guard store.commit(latest) else { throw DataIssue.invalid("Не удалось сохранить синхронизацию на iPhone.") }
            try base.save(result.state); lastSync = .now; failed = false; message = nil
        } catch { failed = true; message = error.localizedDescription }
    }
    func useServer(_ store: CabinetStore) async {
        guard let c = credentials, !busy else { return }; busy = true; defer { busy = false }
        do {
            let reply: ServerReply = try await api.request(c.server, path: "/api/cabinets/\(c.id)/state", token: c.ownerKey)
            guard store.commit(reply.state, restoring: true) else { return }
            try base.save(reply.state); lastSync = .now; failed = false; message = "Загружена версия сервера."
        } catch { failed = true; message = error.localizedDescription }
    }
    func disconnect() {
        scheduled?.cancel()
        try? saveCredentials(nil); base.clear()
        credentials = nil; lastSync = nil; message = nil; failed = false
    }
    func deleteRemote() async {
        guard let c = credentials, !busy else { return }; busy = true; defer { busy = false }
        do {
            struct Deleted: Decodable { var deleted: Bool }
            let _: Deleted = try await api.request(c.server, path: "/api/cabinets/\(c.id)", method: "DELETE", token: c.ownerKey)
            disconnect(); message = "Онлайн-кабинет удалён. Данные на iPhone сохранены."
        } catch { failed = true; message = error.localizedDescription }
    }
}
