import SwiftUI
import SwiftData

struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showingModelPicker = false

    private var appVersion: String {
        let bundle = Bundle.main
        let marketing = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(marketing) (\(build))"
    }

    private var buildTime: String {
        Bundle.main.object(forInfoDictionaryKey: "HappaEchoBuildTime") as? String ?? "-"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("API") {
                    TextField("Chat Completions 接口", text: $viewModel.endpoint)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField(viewModel.chatKeyPresent ? "API Key（已保存，留空保持不变）" : "API Key", text: $viewModel.chatAPIKey)
                    Button("从上游获取模型") { showingModelPicker = true; Task { await viewModel.fetchModels() } }
                    modelPickerSummary
                    Picker("默认模型", selection: $viewModel.modelID) {
                        if viewModel.selectedModelIDs.isEmpty { Text("请先添加模型").tag("") }
                        ForEach(viewModel.selectedModelIDs, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("支持图片输入", isOn: $viewModel.supportsVision)
                    TextField("单图上限（字节，可选）", text: $viewModel.maxImageBytes).keyboardType(.numberPad)
                    TextField("总请求上限（字节，可选）", text: $viewModel.maxRequestBodyBytes).keyboardType(.numberPad)
                    TextField("系统提示词（可选）", text: $viewModel.systemPrompt, axis: .vertical)
                }
                Section("Notion") {
                    Toggle("启用 Notion 备份", isOn: $viewModel.notionEnabled)
                    TextField("数据库 ID", text: $viewModel.notionDatabaseID)
                    SecureField(viewModel.notionTokenPresent ? "Token（已保存，留空保持不变）" : "Notion Token", text: $viewModel.notionToken)
                    Button("测试 Notion 连接") { Task { await viewModel.testNotionConnection() } }
                        .disabled(viewModel.connectionState == .testing)
                    connectionStatus
                }
                Section("关于") {
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("编译时间", value: buildTime)
                    Text("本地对话优先，Notion 仅作单向备份。")
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { try? viewModel.save(to: settings); dismiss() }
                }
            }
            .sheet(isPresented: $showingModelPicker) { modelPickerSheet }
            .onAppear { viewModel.load(from: settings) }
        }
    }

    @ViewBuilder private var modelPickerSummary: some View {
        switch viewModel.modelLoadingState {
        case .idle:
            Text(viewModel.selectedModelIDs.isEmpty ? "未添加模型" : "已添加 \(viewModel.selectedModelIDs.count) 个模型")
                .font(.footnote).foregroundStyle(.secondary)
        case .loading: ProgressView("正在获取模型")
        case .failure(let message): Text(message).font(.footnote).foregroundStyle(.red)
        }
    }

    private var modelPickerSheet: some View {
        NavigationStack {
            Group {
                switch viewModel.modelLoadingState {
                case .loading: ProgressView("正在从上游获取模型")
                case .failure(let message): ContentUnavailableView("无法获取模型", systemImage: "exclamationmark.triangle", description: Text(message))
                case .idle:
                    if viewModel.availableModels.isEmpty {
                        ContentUnavailableView("没有可用模型", systemImage: "cube")
                    } else {
                        List(viewModel.availableModels, id: \.self) { model in
                            Button { viewModel.toggleModel(model) } label: {
                                HStack { Text(model); Spacer(); if viewModel.selectedModelIDs.contains(model) { Image(systemName: "checkmark").foregroundStyle(.tint) } }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("添加模型")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { showingModelPicker = false } }
                ToolbarItem(placement: .topBarTrailing) { Button { Task { await viewModel.fetchModels() } } label: { Image(systemName: "arrow.clockwise") } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private var connectionStatus: some View {
        switch viewModel.connectionState {
        case .idle: EmptyView()
        case .testing: ProgressView("正在测试")
        case .success(let text): Text(text).foregroundStyle(.green)
        case .failure(let text): Text(text).foregroundStyle(.red)
        }
    }
}
