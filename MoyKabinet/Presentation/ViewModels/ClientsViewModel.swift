import Foundation

struct ClientsViewModel {
    let data: CabinetData
    let query: String
    let showArchived: Bool

    var clients: [Client] {
        data.clients.filter {
            ($0.archived == true) == showArchived &&
            (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.phone.contains(query))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func completedVisits(for client: Client) -> Int {
        data.appointments.filter { $0.clientID == client.id && $0.status == .paid }.count
    }
}
