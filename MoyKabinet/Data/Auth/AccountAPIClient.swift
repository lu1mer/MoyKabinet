import Foundation

struct AccountCabinet: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let specialty: String?
}

struct AccountCabinetKey: Decodable {
    let id: String
    let ownerKey: String
}

struct AuthProviderAvailability: Decodable {
    let email: Bool?
    let apple: Bool
    let google: Bool
    let yandex: Bool

    func enabled(_ provider: AuthProvider) -> Bool {
        switch provider {
        case .email: return email == true
        case .apple: return apple
        case .google: return google
        case .yandex: return yandex
        }
    }
}

struct AccountAPIClient {
    let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func register(server: URL, email: String, password: String, displayName: String) async throws -> Bool {
        struct Reply: Decodable { let verificationRequired: Bool }
        let body = try JSONEncoder().encode(["email": email, "password": password, "displayName": displayName, "deviceName": "iPhone"])
        let data = try await publicRequest(server: server, path: "api/auth/register", body: body)
        return try JSONDecoder().decode(Reply.self, from: data).verificationRequired
    }

    func confirm(server: URL, email: String, code: String) async throws -> AuthSession {
        let body = try JSONEncoder().encode(["email": email, "code": code, "deviceName": "iPhone"])
        return try AuthAPIClient.decodeSession(await publicRequest(server: server, path: "api/auth/confirm", body: body), expectedProvider: .email)
    }

    func login(server: URL, email: String, password: String) async throws -> AuthSession {
        let body = try JSONEncoder().encode(["email": email, "password": password, "deviceName": "iPhone"])
        return try AuthAPIClient.decodeSession(await publicRequest(server: server, path: "api/auth/login", body: body), expectedProvider: .email)
    }

    func refresh(server: URL, refreshToken: String) async throws -> AuthSession {
        let body = try JSONEncoder().encode(["refreshToken": refreshToken, "deviceName": "iPhone"])
        return try AuthAPIClient.decodeSession(await publicRequest(server: server, path: "api/auth/refresh", body: body), expectedProvider: nil)
    }

    func requestPasswordReset(server: URL, email: String) async throws {
        let body = try JSONEncoder().encode(["email": email])
        _ = try await publicRequest(server: server, path: "api/auth/password/reset/request", body: body)
    }

    func resetPassword(server: URL, email: String, code: String, newPassword: String) async throws {
        let body = try JSONEncoder().encode(["email": email, "code": code, "newPassword": newPassword])
        _ = try await publicRequest(server: server, path: "api/auth/password/reset/confirm", body: body)
    }

    func availability(server: URL) async throws -> AuthProviderAvailability {
        var request = URLRequest(url: server.appendingPathComponent("api/auth/config"))
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw AuthError.serverUnavailable
            }
            guard let value = try? JSONDecoder().decode(AuthProviderAvailability.self, from: data) else {
                throw AuthError.invalidResponse
            }
            return value
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.serverUnavailable
        }
    }

    func cabinets(server: URL, accessToken: String) async throws -> [AccountCabinet] {
        struct Reply: Decodable { let cabinets: [AccountCabinet] }
        let reply: Reply = try await request(server: server, path: "api/auth/cabinets", method: "GET", token: accessToken)
        return reply.cabinets
    }

    func link(server: URL, accessToken: String, cabinetID: String, ownerKey: String) async throws {
        struct Reply: Decodable { let linked: Bool }
        let body = try JSONEncoder().encode(["cabinetID": cabinetID, "ownerKey": ownerKey])
        let reply: Reply = try await request(server: server, path: "api/auth/cabinets/link", method: "POST", token: accessToken, body: body)
        guard reply.linked else { throw AuthError.invalidResponse }
    }

    func issueKey(server: URL, accessToken: String, cabinetID: String) async throws -> AccountCabinetKey {
        guard cabinetID.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil else { throw AuthError.invalidResponse }
        return try await request(server: server, path: "api/auth/cabinets/\(cabinetID)/key", method: "POST", token: accessToken, body: Data("{}".utf8))
    }

    func logout(server: URL, accessToken: String) async throws {
        struct Reply: Decodable { let revoked: Bool }
        let reply: Reply = try await request(server: server, path: "api/auth/logout", method: "POST", token: accessToken, body: Data("{}".utf8))
        guard reply.revoked else { throw AuthError.invalidResponse }
    }

    func deleteAccount(server: URL, accessToken: String) async throws {
        struct Reply: Decodable { let deleted: Bool }
        let reply: Reply = try await request(server: server, path: "api/auth/me", method: "DELETE", token: accessToken)
        guard reply.deleted else { throw AuthError.invalidResponse }
    }

    private func request<T: Decodable>(server: URL, path: String, method: String, token: String, body: Data? = nil) async throws -> T {
        var request = URLRequest(url: server.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw AuthError.serverUnavailable }
            guard (200..<300).contains(response.statusCode) else {
                let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                throw AuthError.message(error ?? "Сервер отклонил запрос (\(response.statusCode)).")
            }
            do { return try JSONDecoder().decode(T.self, from: data) }
            catch { throw AuthError.invalidResponse }
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.serverUnavailable
        }
    }

    private func publicRequest(server: URL, path: String, body: Data) async throws -> Data {
        var request = URLRequest(url: server.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw AuthError.serverUnavailable }
            guard (200..<300).contains(response.statusCode) else {
                let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                if response.statusCode == 401 { throw AuthError.sessionExpired }
                throw AuthError.message(message ?? "Сервер отклонил запрос (\(response.statusCode)).")
            }
            return data
        } catch let error as AuthError { throw error }
        catch { throw AuthError.serverUnavailable }
    }
}
