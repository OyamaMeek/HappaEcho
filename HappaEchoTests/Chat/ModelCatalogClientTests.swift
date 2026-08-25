import XCTest
@testable import HappaEcho

final class ModelCatalogClientTests: XCTestCase {
    func testModelsURLReplacesChatCompletionsPath() throws {
        let endpoint = URL(string: "https://api.example.com/v1/chat/completions")!
        XCTAssertEqual(try ModelCatalogClient.modelsURL(for: endpoint).absoluteString, "https://api.example.com/v1/models")
    }

    func testFetchModelsUsesBearerAuthorizationAndDeduplicatesSortedIDs() async throws {
        let endpoint = URL(string: "https://models-\(UUID().uuidString).test/v1/chat/completions")!
        let modelsURL = try ModelCatalogClient.modelsURL(for: endpoint)
        StubURLProtocol.handlers[modelsURL] = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            return .init(chunks: [Data(#"{"data":[{"id":"zeta"},{"id":"alpha"},{"id":"zeta"}]}"#.utf8)])
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = ModelCatalogClient(session: URLSession(configuration: configuration))

        let models = try await client.fetchModels(endpoint: endpoint, apiKey: "test-key")

        XCTAssertEqual(models, ["alpha", "zeta"])
    }
}
