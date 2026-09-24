import Foundation

struct OnlineAPIClient {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func normalize(_ string: String) throws -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed), let host = url.host, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else { throw DataIssue.invalid("Укажите адрес сервера без пути, например https://booking.example.com.") }
        guard url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(host)) else { throw DataIssue.invalid("Для онлайн-кабинета нужен защищённый адрес HTTPS.") }
        return trimmed
    }

    func request<T: Decodable>(_ server: String, path: String, method: String = "GET", token: String? = nil, body: Data? = nil) async throws -> T {
        guard let url = URL(string: server + path) else { throw DataIssue.invalid("Некорректный адрес сервера.") }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw DataIssue.invalid("Сервер не ответил.") }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"]
            throw DataIssue.invalid(message ?? "Сервер временно недоступен (\(response.statusCode)).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
