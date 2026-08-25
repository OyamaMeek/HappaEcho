import SwiftUI
import SwiftData
struct SettingsView: View {
 @Bindable var viewModel: SettingsViewModel; @Bindable var settings: AppSettings; @Environment(\.dismiss) private var dismiss
 var body: some View { NavigationStack { Form {
  Section("API") { TextField("Chat Completions 接口", text: $viewModel.endpoint).textInputAutocapitalization(.never).keyboardType(.URL); TextField("模型", text: $viewModel.modelID); Toggle("支持图片输入", isOn: $viewModel.supportsVision); TextField("单图上限（字节，可选）", text: $viewModel.maxImageBytes).keyboardType(.numberPad); TextField("总请求上限（字节，可选）", text: $viewModel.maxRequestBodyBytes).keyboardType(.numberPad); SecureField(viewModel.chatKeyPresent ? "API Key（已保存，留空保持不变）" : "API Key", text: $viewModel.chatAPIKey); TextField("系统提示词（可选）", text: $viewModel.systemPrompt, axis: .vertical) }
  Section("Notion") { Toggle("启用 Notion 备份", isOn: $viewModel.notionEnabled); TextField("数据库 ID", text: $viewModel.notionDatabaseID); SecureField(viewModel.notionTokenPresent ? "Token（已保存，留空保持不变）" : "Notion Token", text: $viewModel.notionToken); Button("测试 Notion 连接") { Task { await viewModel.testNotionConnection() } }.disabled(viewModel.connectionState == .testing); connectionStatus }
  Section("关于") { LabeledContent("HappaEcho", value: "iOS 17+"); Text("本地对话优先，Notion 仅作单向备份。") }
 }.navigationTitle("设置").toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存") { try? viewModel.save(to: settings); dismiss() } } } }.onAppear { viewModel.load(from: settings) } }
 @ViewBuilder private var connectionStatus: some View { switch viewModel.connectionState { case .idle: EmptyView(); case .testing: ProgressView("正在测试"); case .success(let text): Text(text).foregroundStyle(.green); case .failure(let text): Text(text).foregroundStyle(.red) } }
}
