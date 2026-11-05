import Foundation

enum PlugState: String {
    case on, off, unavailable, unknown

    var label: String {
        switch self {
        case .on: return "开启"
        case .off: return "关闭"
        case .unavailable: return "不可用"
        case .unknown: return "未知"
        }
    }
}

struct HAError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Minimal Home Assistant REST API client.
struct HomeAssistantClient {
    let baseURL: String
    let token: String
    let entityID: String

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    private var domain: String {
        entityID.split(separator: ".").first.map(String.init) ?? "switch"
    }

    private func validate() throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed), url.scheme != nil else { throw HAError(message: "HA 地址无效") }
        guard !token.isEmpty else { throw HAError(message: "未设置 HA Token") }
        guard entityID.contains(".") else { throw HAError(message: "未设置插座 Entity ID") }
        return url
    }

    private func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HAError(message: "无效响应") }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw HAError(message: "HTTP \(http.statusCode) \(body)")
        }
        return data
    }

    func setPower(_ on: Bool) async throws {
        let base = try validate()
        var request = URLRequest(url: base.appendingPathComponent("api/services/\(domain)/turn_\(on ? "on" : "off")"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["entity_id": entityID])
        _ = try await send(request)
    }

    func state() async throws -> PlugState {
        let base = try validate()
        let request = URLRequest(url: base.appendingPathComponent("api/states/\(entityID)"))
        let data = try await send(request)
        struct Resp: Decodable { let state: String }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        return PlugState(rawValue: resp.state) ?? .unknown
    }
}
