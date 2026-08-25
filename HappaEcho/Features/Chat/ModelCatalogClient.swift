import Foundation

struct ModelCatalogClient {
    enum Error: LocalizedError {
        case invalidEndpoint
        case missingAPIKey
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: "无法从 Chat Completions 地址解析模型列表地址"
            case .missingAPIKey: "请先保存 API Key"
            case .invalidResponse: "模型列表响应无效"
            case .httpStatus(let code): "获取模型列表失败（HTTP \(code)）"
            }
        }
    }

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    static func modelsURL(for endpoint: URL) throws -> URL {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        let segments = endpoint.pathComponents
        guard let v1Index = segments.lastIndex(of: "v1"), v1Index > 0 else { throw Error.invalidEndpoint }
        components?.path = "/" + segments[1...v1Index].joined(separator: "/") + "/models"
        components?.query = nil
        guard let url = components?.url else { throw Error.invalidEndpoint }
        return url
    }

    func fetchModels(endpoint: URL, apiKey: String) async throws -> [String] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Error.missingAPIKey }
        var request = URLRequest(url: try Self.modelsURL(for: endpoint))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Error.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw Error.httpStatus(http.statusCode) }
        let payload = try JSONDecoder().decode(Response.self, from: data)
        return Array(Set(payload.data.map(\.id).filter { !$0.isEmpty })).sorted()
    }

    private struct Response: Decodable { let data: [Model]; struct Model: Decodable { let id: String } }
}
