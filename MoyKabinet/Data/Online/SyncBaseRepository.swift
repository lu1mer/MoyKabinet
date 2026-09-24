import Foundation

struct SyncBaseRepository {
    let file: URL

    func load() throws -> CabinetData {
        guard let bytes = try? Data(contentsOf: file), let base = try? JSONDecoder().decode(CabinetData.self, from: bytes) else {
            throw DataIssue.invalid("Нет базы синхронизации. Сохраните копию и загрузите данные сервера.")
        }
        return try base.validated()
    }

    func save(_ state: CabinetData) throws {
        try JSONEncoder().encode(state).write(to: file, options: [.atomic, .completeFileProtection])
    }

    func clear() { try? FileManager.default.removeItem(at: file) }
}
