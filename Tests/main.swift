import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ title: String) {
    guard condition() else { fatalError("FAILED: \(title)") }
    checks += 1
    print("PASS: \(title)")
}
let start = Date(timeIntervalSince1970: 1_800_000_000)
let client = Client(name: "Тест", phone: "", notes: "Пожелания")
var visit = Appointment(clientID: client.id, serviceName: "Услуга", start: start, minutes: 60, price: 2500)
check(BookingRules.overlaps(start: start, minutes: 60, appointments: [visit]), "Same slot is blocked")
check(BookingRules.overlaps(start: start.addingTimeInterval(-1800), minutes: 60, appointments: [visit]), "Partial overlap before is blocked")
check(BookingRules.overlaps(start: start.addingTimeInterval(1800), minutes: 60, appointments: [visit]), "Partial overlap after is blocked")
check(BookingRules.overlaps(start: start.addingTimeInterval(-1800), minutes: 120, appointments: [visit]), "Containing interval is blocked")
check(BookingRules.overlaps(start: start.addingTimeInterval(600), minutes: 15, appointments: [visit]), "Contained interval is blocked")
check(!BookingRules.overlaps(start: start.addingTimeInterval(3600), minutes: 60, appointments: [visit]), "Adjacent following visit is allowed")
check(!BookingRules.overlaps(start: start.addingTimeInterval(-3600), minutes: 60, appointments: [visit]), "Adjacent previous visit is allowed")
visit.status = .paid
check(BookingRules.overlaps(start: start, minutes: 60, appointments: [visit]), "Paid visit still occupies time")
visit.status = .cancelled
check(!BookingRules.overlaps(start: start, minutes: 60, appointments: [visit]), "Cancelled visit releases time")
check(!BookingRules.overlaps(start: start, minutes: 60, appointments: []), "Empty schedule accepts a visit")
let model = CabinetData(clients: [client], appointments: [visit])
let decoded = try JSONDecoder().decode(CabinetData.self, from: JSONEncoder().encode(model))
check(decoded.clients.first == client, "Client fields survive JSON round trip")
check(decoded.appointments.first?.status == .cancelled && decoded.appointments.first?.start == start && decoded.appointments.first?.price == 2500, "Visit status, price and date survive JSON round trip")
print("\(checks) checks passed")

func rejects(_ title: String, _ action: () throws -> Void) {
    do { try action(); fatalError("FAILED: \(title)") }
    catch { checks += 1; print("PASS: \(title)") }
}
visit.status = .planned
check(!BookingRules.overlaps(start: start, minutes: 60, appointments: [visit], excluding: visit.id), "Editing excludes original visit")
var validModel = CabinetData(clients: [client], appointments: [visit])
_ = try validModel.validated()
var broken = validModel
broken.appointments[0].clientID = UUID()
rejects("Orphan appointment is rejected") { _ = try broken.validated() }
broken = validModel; broken.appointments.append(Appointment(clientID: client.id, serviceName: "Пересечение", start: start.addingTimeInterval(60), minutes: 60, price: 100))
rejects("Imported overlapping appointments are rejected") { _ = try broken.validated() }
broken = validModel; broken.clients.append(client)
rejects("Duplicate client IDs are rejected") { _ = try broken.validated() }
broken = validModel; broken.schemaVersion = 999
rejects("Future schema version is rejected") { _ = try broken.validated() }
var local = validModel, remote = validModel
local.clients[0].notes = "Новая заметка"
remote.appointments[0].status = .paid
let merged = try CabinetMerge.combine(base: validModel, local: local, remote: remote)
check(merged.clients[0].notes == "Новая заметка" && merged.appointments[0].status == .paid, "Independent local and remote changes merge")
remote.clients[0].notes = "Другая заметка"
rejects("Conflicting edits are never silently overwritten") { _ = try CabinetMerge.combine(base: validModel, local: local, remote: remote) }
local = validModel; remote = validModel
local.clients.removeAll(); local.appointments.removeAll()
let deleted = try CabinetMerge.combine(base: validModel, local: local, remote: remote)
check(deleted.clients.isEmpty && deleted.appointments.isEmpty, "Uncontested deletions propagate")
remote.appointments[0].price = 3000
rejects("Delete versus edit is a conflict") { _ = try CabinetMerge.combine(base: validModel, local: local, remote: remote) }
local = validModel; remote = validModel
local.appointments.removeAll(); remote.appointments.removeAll()
local.appointments.append(Appointment(clientID: client.id, serviceName: "Локально", start: start, minutes: 60, price: 100))
remote.appointments.append(Appointment(clientID: client.id, serviceName: "Онлайн", start: start.addingTimeInterval(1800), minutes: 60, price: 100))
rejects("Simultaneous overlapping bookings cannot merge") { _ = try CabinetMerge.combine(base: validModel, local: local, remote: remote) }
var p = Profile(); p.weekdays = [1,2,3,4,5,6,7]; p.timezone = "Europe/Moscow"; p.openingHour = 9; p.closingHour = 19
let candidate = BookingRules.nextSlot(on: start, profile: p, appointments: [], minutes: 60, now: start.addingTimeInterval(-86400))
check(candidate != nil, "Working day offers available slot")
p.weekdays = []
check(BookingRules.nextSlot(on: start, profile: p, appointments: [], now: start.addingTimeInterval(-86400)) == nil, "Nonworking day has no suggested slots")
var allDays = Profile(); allDays.weekdays = [1,2,3,4,5,6,7]; allDays.timezone = "Europe/Moscow"; allDays.openingHour = 9; allDays.closingHour = 10
var testCalendar = Calendar.current; testCalendar.timeZone = TimeZone(identifier: allDays.timezone)!
let firstOpening = testCalendar.date(byAdding: .hour, value: 9, to: testCalendar.startOfDay(for: start))!
let occupied = Appointment(clientID: client.id, serviceName: "Услуга", start: firstOpening, minutes: 60, price: 100)
let followingOpening = BookingRules.nextAvailableSlot(startingAt: firstOpening, profile: allDays, appointments: [occupied], minutes: 60, now: firstOpening.addingTimeInterval(-1))
check(followingOpening.map { testCalendar.isDate($0, inSameDayAs: testCalendar.date(byAdding: .day, value: 1, to: firstOpening)!) } == true, "Quick booking skips a full day")
print("TOTAL: \(checks) checks passed")
