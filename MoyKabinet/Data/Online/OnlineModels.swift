import Foundation

struct ServerReply: Codable {
    var id: String?
    var ownerKey: String?
    var revision: Int
    var state: CabinetData
}
struct OnlineCredentials: Codable {
    var server: String
    var id: String
    var ownerKey: String
}

