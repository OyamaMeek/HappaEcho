import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    enum ConnectionState: Equatable { case idle, testing, success(String), failure(String) }
    enum ModelLoadingState: Equatable { case idle, loading, failure(String) }

    var endpoint = ""
    var modelID = ""
    var selectedModelIDs: [String] = []
    var supportsVision = true
    var maxImageBytes = ""
    var maxRequestBodyBytes = ""
    var systemPrompt = ""
    var notionEnabled = false
    var notionDatabaseID = ""
    var chatAPIKey = ""
    var notionToken = ""
    var chatKeyPresent = false
    var notionTokenPresent = false
    var connectionState: ConnectionState = .idle
    var modelLoadingState: ModelLoadingState = .idle
    var availableModels: [String] = []

    private let repository: SettingsRepository
    private let modelCatalog: ModelCatalogClient

    init(repository: SettingsRepository = .init(), modelCatalog: ModelCatalogClient = .init()) {
        self.repository = repository
        self.modelCatalog = modelCatalog
    }

    func load(from settings: AppSettings) {
        endpoint = settings.endpoint
        modelID = settings.modelID
        selectedModelIDs = settings.selectedModelIDs.isEmpty ? [settings.modelID] : settings.selectedModelIDs
        supportsVision = settings.supportsVision
        maxImageBytes = settings.maxImageBytes.map(String.init) ?? ""
        maxRequestBodyBytes = settings.maxRequestBodyBytes.map(String.init) ?? ""
        systemPrompt = settings.systemPrompt ?? ""
        notionEnabled = settings.notionEnabled
        notionDatabaseID = settings.notionDatabaseID ?? ""
        chatKeyPresent = (try? repository.loadChatAPIKey())?.isEmpty == false
        notionTokenPresent = (try? repository.loadNotionToken())?.isEmpty == false
    }

    func validationError() -> String? {
        guard let url = URL(string: endpoint), url.scheme == "https", url.host != nil else { return "请输入有效的 HTTPS 接口地址" }
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "请选择模型" }
        if !maxImageBytes.isEmpty && Int(maxImageBytes) == nil { return "单图上限必须是整数" }
        if !maxRequestBodyBytes.isEmpty && Int(maxRequestBodyBytes) == nil { return "请求体上限必须是整数" }
        if notionEnabled && notionDatabaseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写 Notion 数据库 ID" }
        return nil
    }

    func save(to settings: AppSettings) throws {
        if let error = validationError() { throw SettingsValidationError.invalid(error) }
        settings.endpoint = endpoint
        settings.modelID = modelID
        settings.selectedModelIDs = Array(Set(selectedModelIDs + [modelID])).sorted()
        settings.supportsVision = supportsVision
        settings.maxImageBytes = Int(maxImageBytes)
        settings.maxRequestBodyBytes = Int(maxRequestBodyBytes)
        settings.systemPrompt = systemPrompt.nilIfBlank
        settings.notionEnabled = notionEnabled
        settings.notionDatabaseID = notionDatabaseID.nilIfBlank
        if !chatAPIKey.isEmpty { try repository.saveChatAPIKey(chatAPIKey); chatKeyPresent = true; chatAPIKey = "" }
        if !notionToken.isEmpty { try repository.saveNotionToken(notionToken); notionTokenPresent = true; notionToken = "" }
    }

    func fetchModels() async {
        guard let endpointURL = URL(string: endpoint) else { modelLoadingState = .failure("请输入有效的 Chat Completions 接口地址"); return }
        let apiKey = chatAPIKey.isEmpty ? (try? repository.loadChatAPIKey()) ?? "" : chatAPIKey
        guard !apiKey.isEmpty else { modelLoadingState = .failure("请先填写 API Key"); return }
        modelLoadingState = .loading
        do {
            availableModels = try await modelCatalog.fetchModels(endpoint: endpointURL, apiKey: apiKey)
            modelLoadingState = .idle
        } catch {
            modelLoadingState = .failure(error.localizedDescription)
        }
    }

    func toggleModel(_ id: String) {
        if let index = selectedModelIDs.firstIndex(of: id) { selectedModelIDs.remove(at: index) }
        else { selectedModelIDs.append(id); selectedModelIDs.sort() }
        if !selectedModelIDs.contains(modelID) { modelID = selectedModelIDs.first ?? "" }
    }

    func testNotionConnection() async {
        guard notionEnabled, !notionDatabaseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { connectionState = .failure("请先启用并填写 Notion 数据库 ID"); return }
        guard let token = try? repository.loadNotionToken(), !token.isEmpty else { connectionState = .failure("请先保存 Notion Token"); return }
        connectionState = .testing
        do { _ = try await NotionClient(configuration: .init(baseURL: URL(string: "https://api.notion.com/v1/")!, token: token)).listBlocks(pageID: notionDatabaseID, cursor: nil); connectionState = .success("连接成功") }
        catch let error as NotionError { connectionState = .failure(error.userMessage) }
        catch { connectionState = .failure(error.localizedDescription) }
    }
}

enum SettingsValidationError: LocalizedError { case invalid(String); var errorDescription: String? { if case let .invalid(value) = self { value } else { nil } } }
private extension String { var nilIfBlank: String? { let value = trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? nil : value } }
private extension NotionError { var userMessage: String { switch self { case .unauthorized, .forbidden: "Notion 身份验证失败"; case .notFound: "未找到 Notion 资源"; default: "Notion 连接失败" } } }
