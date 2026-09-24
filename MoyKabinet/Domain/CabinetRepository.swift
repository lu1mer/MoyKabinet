import Foundation

/// Persistence boundary. Domain operations never depend on a file format or storage location.
protocol CabinetRepository {
    func load() throws -> CabinetData?
    func save(_ state: CabinetData) throws
    func rawData() throws -> Data
}
