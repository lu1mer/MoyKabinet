import Foundation

enum CabinetMerge {
    static func combine(base: CabinetData, local: CabinetData, remote: CabinetData) throws -> CabinetData {
        func field<T: Equatable>(_ b: T, _ l: T, _ r: T) throws -> T {
            if l == b { return r }
            if r == b || l == r { return l }
            throw DataIssue.invalid("Одни и те же данные изменились на двух устройствах. Локальная версия сохранена. Сохраните копию и выберите версию сервера в онлайн-настройках.")
        }
        func items<T: Identifiable & Equatable>(_ b: [T], _ l: [T], _ r: [T]) throws -> [T] where T.ID == UUID {
            let bm = Dictionary(uniqueKeysWithValues: b.map { ($0.id, $0) })
            let lm = Dictionary(uniqueKeysWithValues: l.map { ($0.id, $0) })
            let rm = Dictionary(uniqueKeysWithValues: r.map { ($0.id, $0) })
            return try Set(bm.keys).union(lm.keys).union(rm.keys).sorted { $0.uuidString < $1.uuidString }.compactMap { try field(bm[$0], lm[$0], rm[$0]) }
        }
        return try CabinetData(clients: items(base.clients, local.clients, remote.clients), services: items(base.services, local.services, remote.services), appointments: items(base.appointments, local.appointments, remote.appointments), profile: field(base.settings, local.settings, remote.settings), schemaVersion: 2).validated()
    }
}
