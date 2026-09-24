import Foundation

struct FileCabinetRepository: CabinetRepository {
    let file: URL

    func load() throws -> CabinetData? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(CabinetData.self, from: Data(contentsOf: file)).validated()
    }

    func save(_ state: CabinetData) throws {
        let encoded = try JSONEncoder().encode(state)
        guard encoded.count <= 50_000_000 else { throw DataIssue.invalid("Кабинет превышает 50 МБ. Удалите ненужные фотографии перед сохранением.") }
        try encoded.write(to: file, options: [.atomic, .completeFileProtection])
    }

    func rawData() throws -> Data { try Data(contentsOf: file) }
}
