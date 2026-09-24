import Foundation

struct CabinetViewModel {
    let data: CabinetData
    let calendar: Calendar

    var activeClientCount: Int { data.clients.filter { $0.archived != true }.count }

    var monthlyPaid: Int {
        data.appointments.filter { $0.status == .paid && calendar.isDate($0.start, equalTo: .now, toGranularity: .month) }
            .reduce(0) { $0 + $1.price }
    }

    func services(showArchived: Bool) -> [Service] {
        data.services.filter { showArchived || $0.archived != true }
    }
}
