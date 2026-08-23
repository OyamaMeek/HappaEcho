```markdown
# Agent 任务指令：液态玻璃风格 AI 对话应用（支持 Markdown & LaTeX + 设置 + Notion 备份）

## 项目概述
创建一个具有现代感的 iOS AI 对话应用，采用深色主题配合液态玻璃（Glassmorphism）视觉效果，集成 OpenAI Chat Completions API。**核心特性：完美渲染 Markdown 格式和 LaTeX 数学公式、可配置 API 设置、自动备份到 Notion**。

## 视觉设计规范

### 整体风格
- **主题**: 深色模式（Dark Theme）
- **视觉语言**: 液态玻璃效果（Glassmorphism）+ 毛玻璃模糊（Frosted Glass）
- **布局**: 双栏式设计（iPad）/ 层叠式导航（iPhone）
- **动画**: 流畅的过渡动画和微交互
- **排版**: 支持 Markdown 完整语法 + LaTeX 数学公式

### 色彩系统
```swift
// 背景层次
- 主背景: #1E222E (深邃蓝灰)
- 玻璃卡片背景: #2A2F3C (半透明，带模糊效果)
- 悬浮层背景: rgba(42, 47, 60, 0.7) + backdrop-filter: blur(20px)

// 强调色
- 主品牌色: #6B5FFF (紫罗兰)
- 渐变色: 紫色到蓝色的线性渐变
- 高光: 白色半透明 rgba(255, 255, 255, 0.1)
- 成功色: #4CAF50 (绿色 - 备份成功提示)
- 警告色: #FF9800 (橙色 - 警告提示)
- 错误色: #F44336 (红色 - 错误提示)

// 文字
- 主文字: #FFFFFF (纯白)
- 次要文字: #8B92A8 (灰蓝)
- 占位符: rgba(255, 255, 255, 0.3)

// Markdown 元素
- 代码块背景: #1A1E28
- 代码块边框: #3A3F4C
- 行内代码背景: rgba(107, 95, 255, 0.15)
- 引用块边框: #6B5FFF
- 链接颜色: #4A9EFF
- 表格边框: rgba(255, 255, 255, 0.1)
```

### 界面布局描述

#### 左侧边栏（宽度：320pt）

**顶部区域**（高度：80pt）
- App标识 "OpenCat" - 粗体 20pt，白色
- 右上角：圆形新建按钮（52x52pt）
  - 图标：编辑/新建符号
  - 背景：玻璃材质卡片
  - 轻微阴影和高光边框

**功能导航区**（紧随顶部）
仅保留 1 个功能卡片：
1. **新聊天** - 带紫色渐变背景高亮
   - 图标：消息气泡
   - 文字：白色粗体
   - 背景：紫色半透明玻璃效果
   - 高度：52pt

**历史对话列表**（可滚动区域）
- 分组标题 "昨天"、"本周"、"更早" - 12pt，灰色
- 对话条目：
  - 高度：44pt
  - 圆角：8pt
  - 文字：14pt白色
  - 右侧显示备份状态图标（已备份/未备份）
  - Hover状态：白色5%透明度背景
  - 选中状态：白色10%透明度背景 + 左侧紫色指示条

**底部固定区域**
两个按钮垂直排列：
1. **设置按钮**
   - 图标：齿轮 + "设置" 文字
   - 玻璃材质背景
   - 点击弹出设置面板

2. **备份状态指示**（可选显示）
   - 小型状态条
   - 显示最后备份时间
   - Notion 连接状态图标

#### 右侧对话区域

**顶部导航栏**（高度：64pt）
- 左侧：当前对话标题（可编辑）
- 右侧：操作按钮组
  - 手动备份按钮（云朵图标）
  - 更多选项（三点菜单）
- 背景：毛玻璃材质

**消息显示区域**（主体区域）
- 支持完整 Markdown + LaTeX 渲染
- 用户消息：蓝紫渐变玻璃效果（右对齐）
- AI消息：深灰玻璃卡片（左对齐）

**底部输入区域**
- 多行文本输入
- 附加/发送按钮

#### 设置面板（Sheet 弹出）

**设计规范**：
- 全屏半透明遮罩（黑色40%透明度）
- 从底部滑入的玻璃材质面板
- 圆角：顶部16pt
- 最大高度：屏幕的90%

**设置面板布局**：

```
┌─────────────────────────────────────┐
│  ⚙️ 设置                    [完成] │  ← 顶部栏
├─────────────────────────────────────┤
│                                     │
│  【API 配置】                        │
│  ┌─────────────────────────────┐   │
│  │ API 地址                     │   │
│  │ https://api.openai.com/v... │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ API Key                      │   │
│  │ sk-proj-...      [显示/隐藏] │   │
│  └─────────────────────────────┘   │
│                                     │
│  【模型配置】                        │
│  ┌─────────────────────────────┐   │
│  │ 默认模型                     │   │
│  │ GPT-3.5-turbo        ▼     │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 系统提示词（可选）            │   │
│  │ You are a helpful...         │   │
│  │                              │   │
│  └─────────────────────────────┘   │
│                                     │
│  【Notion 备份配置】                │
│  ┌─────────────────────────────┐   │
│  │ ⚪ 启用自动备份              │   │ ← Toggle
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ Notion Integration Token     │   │
│  │ secret_...       [显示/隐藏] │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ Notion Database ID           │   │
│  │ a1b2c3d4...                  │   │
│  └─────────────────────────────┘   │
│                                     │
│  备份策略：                          │
│  ◉ 每次对话后自动备份                │
│  ○ 仅手动备份                        │
│                                     │
│  [ 测试 Notion 连接 ]               │
│                                     │
│  最后备份：2024-01-15 14:30         │
│  状态：✅ 已连接                     │
│                                     │
│  【关于】                            │
│  版本：1.0.0                         │
│  [查看隐私政策]                      │
│                                     │
└─────────────────────────────────────┘
```

**设置项详细说明**：

1. **API 配置组**
   - API 地址输入框（默认：https://api.openai.com/v1/chat/completions）
   - API Key 输入框（密码类型，可切换显示/隐藏）
   - 保存按钮自动验证格式

2. **模型配置组**
   - 下拉选择器：GPT-4, GPT-3.5-turbo, GPT-4-turbo
   - 系统提示词多行文本框（可折叠展开）

3. **Notion 备份配置组**
   - 启用/禁用 Toggle 开关
   - Notion Integration Token（密码类型）
   - Notion Database ID（文本类型）
   - 备份策略选择（单选按钮）
   - 测试连接按钮（验证配置有效性）
   - 状态指示器（显示连接状态和最后备份时间）

4. **关于组**
   - 版本信息
   - 隐私政策链接

### Notion 备份功能设计

#### 备份触发机制
```swift
// 自动备份触发点
1. 用户发送消息后
2. 接收到 AI 回复后
3. 对话标题修改后
4. 用户手动点击备份按钮

// 备份策略
- 实时备份：每次消息后立即备份
- 批量备份：每5条消息备份一次
- 手动备份：仅通过按钮触发
```

#### Notion 数据结构

**数据库属性设计**（参考 CherryStudio）：
```json
{
  "Title": "对话标题",
  "Created": "2024-01-15T14:30:00",
  "Updated": "2024-01-15T15:45:00",
  "Model": "gpt-3.5-turbo",
  "MessageCount": 12,
  "Content": "完整对话内容（Markdown 格式）",
  "Tags": ["工作", "技术"],
  "Status": "已备份"
}
```

**Notion API 调用流程**：
```
1. 验证 Integration Token 和 Database ID
2. 创建或更新 Page
3. 将对话内容格式化为 Notion Blocks
4. 上传到指定 Database
5. 返回备份状态和 Page URL
```

#### 备份状态指示

**对话列表中的状态图标**：
- ✅ 已备份（绿色勾选）
- 🔄 备份中（旋转动画）
- ⚠️ 备份失败（黄色警告）
- ⭕ 未备份（灰色圆圈）

**备份详情弹窗**：
- 点击状态图标显示详情
- 显示备份时间、Notion Page 链接
- 失败时显示错误原因
- 提供重试按钮

## 技术栈

### 核心框架
- **语言**: Swift (最新稳定版)
- **UI框架**: SwiftUI
- **最低系统**: iOS 16.0+
- **数据持久化**: SwiftData
- **网络**: URLSession
- **安全存储**: Keychain（存储敏感信息）

### Markdown & LaTeX 渲染
- **Markdown**: `MarkdownUI` 库
- **LaTeX**: `LaTeXSwiftUI` 或 Web渲染方案
- **代码高亮**: `Splash` 或 `Highlightr`

### Notion 集成
- **Notion API**: 使用官方 REST API v1
- **端点**: https://api.notion.com/v1/
- **认证**: Bearer Token（Integration Token）

### 依赖管理
使用 Swift Package Manager (SPM)：
```swift
dependencies: [
    .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
    .package(url: "https://github.com/colinc86/LaTeXSwiftUI", from: "1.0.0"),
    .package(url: "https://github.com/JohnSundell/Splash", from: "0.16.0")
]
```

## 项目结构
```
OpenCatClone/
├── OpenCatCloneApp.swift
├── Models/
│   ├── Conversation.swift
│   ├── Message.swift
│   ├── AppSettings.swift              # ⭐ 应用设置模型
│   └── NotionBackup.swift             # ⭐ Notion 备份记录模型
├── Views/
│   ├── ContentView.swift
│   ├── SidebarView.swift
│   ├── ChatView.swift
│   ├── SettingsView.swift             # ⭐ 设置面板
│   └── Components/
│       ├── GlassmorphicCard.swift
│       ├── MessageBubbleView.swift
│       ├── MarkdownView.swift
│       ├── LaTeXView.swift
│       ├── CodeBlockView.swift
│       ├── InputBarView.swift
│       ├── GlassButton.swift
│       ├── BackupStatusBadge.swift    # ⭐ 备份状态标记
│       └── SettingsRow.swift          # ⭐ 设置行组件
├── ViewModels/
│   ├── ChatViewModel.swift
│   ├── SettingsViewModel.swift        # ⭐ 设置视图模型
│   └── NotionViewModel.swift          # ⭐ Notion 备份视图模型
├── Services/
│   ├── OpenAIService.swift
│   ├── NotionService.swift            # ⭐ Notion API 服务
│   ├── KeychainService.swift          # ⭐ Keychain 安全存储
│   └── MarkdownParser.swift
├── Renderers/
│   ├── MarkdownRenderer.swift
│   └── LaTeXRenderer.swift
└── Utils/
    ├── Constants.swift
    ├── GlassModifiers.swift
    ├── MarkdownStyler.swift
    ├── NotionFormatter.swift          # ⭐ Notion 内容格式化器
    └── Extensions.swift
```

## 数据模型定义

### Message Model
```swift
import Foundation
import SwiftData

@Model
class Message {
    @Attribute(.unique) var id: UUID
    var role: String  // "user" 或 "assistant"
    var content: String
    var timestamp: Date
  
    init(role: String, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}
```

### Conversation Model
```swift
import Foundation
import SwiftData

@Model
class Conversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var messages: [Message]
  
    // Notion 备份相关
    var notionPageId: String?          // Notion Page ID
    var lastBackupDate: Date?          // 最后备份时间
    var backupStatus: String           // "none", "success", "failed", "syncing"
    var backupError: String?           // 备份失败原因
  
    init(title: String = "新对话") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.messages = []
        self.backupStatus = "none"
    }
  
    // 更新时间戳
    func updateTimestamp() {
        self.updatedAt = Date()
    }
}
```

### AppSettings Model
```swift
import Foundation
import SwiftData

@Model
class AppSettings {
    @Attribute(.unique) var id: UUID
  
    // API 配置
    var apiEndpoint: String
    var apiModel: String
    var systemPrompt: String?
  
    // Notion 配置
    var notionEnabled: Bool
    var notionDatabaseId: String?
    var backupStrategy: String  // "auto", "manual"
  
    init() {
        self.id = UUID()
        self.apiEndpoint = "https://api.openai.com/v1/chat/completions"
        self.apiModel = "gpt-3.5-turbo"
        self.notionEnabled = false
        self.backupStrategy = "manual"
    }
}
```

## 核心服务实现

### KeychainService.swift（安全存储敏感信息）
```swift
import Foundation
import Security

class KeychainService {
    static let shared = KeychainService()
  
    private let serviceName = "com.opencat.app"
  
    enum KeychainKey: String {
        case apiKey = "api_key"
        case notionToken = "notion_integration_token"
    }
  
    // 保存到 Keychain
    func save(_ value: String, for key: KeychainKey) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
      
        // 删除旧值
        delete(key)
      
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
      
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
  
    // 从 Keychain 读取
    func read(_ key: KeychainKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
      
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
      
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
      
        return string
    }
  
    // 删除
    func delete(_ key: KeychainKey) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]
      
        SecItemDelete(query as CFDictionary)
    }
  
    // 清空所有
    func clearAll() {
        delete(.apiKey)
        delete(.notionToken)
    }
}
```

### OpenAIService.swift（支持动态配置）
```swift
import Foundation

class OpenAIService {
    private let keychainService = KeychainService.shared
  
    struct ChatMessage: Codable {
        let role: String
        let content: String
    }
  
    struct ChatRequest: Codable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double = 0.7
    }
  
    struct ChatResponse: Codable {
        let choices: [Choice]
      
        struct Choice: Codable {
            let message: ChatMessage
        }
    }
  
    func sendMessage(messages: [Message], settings: AppSettings) async throws -> String {
        // 从 Keychain 读取 API Key
        guard let apiKey = keychainService.read(.apiKey), !apiKey.isEmpty else {
            throw NSError(domain: "API Key 未配置", code: -1)
        }
      
        guard let url = URL(string: settings.apiEndpoint) else {
            throw NSError(domain: "无效的 API 地址", code: -2)
        }
      
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
      
        // 构建消息数组
        var chatMessages: [ChatMessage] = []
      
        // 添加系统提示词（如果有）
        if let systemPrompt = settings.systemPrompt, !systemPrompt.isEmpty {
            chatMessages.append(ChatMessage(role: "system", content: systemPrompt))
        }
      
        // 添加历史消息
        chatMessages += messages.map { ChatMessage(role: $0.role, content: $0.content) }
      
        let chatRequest = ChatRequest(model: settings.apiModel, messages: chatMessages)
        request.httpBody = try JSONEncoder().encode(chatRequest)
      
        let (data, response) = try await URLSession.shared.data(for: request)
      
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
      
        guard httpResponse.statusCode == 200 else {
            // 解析错误信息
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw NSError(domain: message, code: httpResponse.statusCode)
            }
            throw URLError(.badServerResponse)
        }
      
        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        return chatResponse.choices.first?.message.content ?? "无响应"
    }
}
```

### NotionService.swift（Notion API 集成）
```swift
import Foundation

class NotionService {
    private let keychainService = KeychainService.shared
    private let baseURL = "https://api.notion.com/v1"
    private let notionVersion = "2022-06-28"
  
    // MARK: - Data Structures
  
    struct NotionPage: Codable {
        let id: String
        let url: String
    }
  
    struct NotionError: Codable {
        let message: String
    }
  
    // MARK: - 测试连接
  
    func testConnection(databaseId: String) async throws -> Bool {
        guard let token = keychainService.read(.notionToken), !token.isEmpty else {
            throw NSError(domain: "Notion Token 未配置", code: -1)
        }
      
        guard let url = URL(string: "\(baseURL)/databases/\(databaseId)") else {
            throw NSError(domain: "无效的 Database ID", code: -2)
        }
      
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        request.timeoutInterval = 30
      
        let (_, response) = try await URLSession.shared.data(for: request)
      
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
      
        return httpResponse.statusCode == 200
    }
  
    // MARK: - 备份对话到 Notion
  
    func backupConversation(_ conversation: Conversation, databaseId: String) async throws -> String {
        guard let token = keychainService.read(.notionToken), !token.isEmpty else {
            throw NSError(domain: "Notion Token 未配置", code: -1)
        }
      
        let endpoint = conversation.notionPageId != nil ? "pages/\(conversation.notionPageId!)" : "pages"
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw NSError(domain: "无效的 API 地址", code: -2)
        }
      
        var request = URLRequest(url: url)
        request.httpMethod = conversation.notionPageId != nil ? "PATCH" : "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
      
        // 构建请求体
        let body = buildNotionPayload(conversation: conversation, databaseId: databaseId)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
      
        let (data, response) = try await URLSession.shared.data(for: request)
      
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
      
        guard httpResponse.statusCode == 200 else {
            // 解析错误信息
            if let errorJson = try? JSONDecoder().decode(NotionError.self, from: data) {
                throw NSError(domain: errorJson.message, code: httpResponse.statusCode)
            }
            throw URLError(.badServerResponse)
        }
      
        let pageResponse = try JSONDecoder().decode(NotionPage.self, from: data)
        return pageResponse.id
    }
  
    // MARK: - 构建 Notion Payload
  
    private func buildNotionPayload(conversation: Conversation, databaseId: String) -> [String: Any] {
        var payload: [String: Any] = [:]
      
        // 如果是新建页面，需要指定 parent
        if conversation.notionPageId == nil {
            payload["parent"] = [
                "database_id": databaseId
            ]
        }
      
        // 属性
        payload["properties"] = [
            "Title": [
                "title": [
                    [
                        "text": [
                            "content": conversation.title
                        ]
                    ]
                ]
            ],
            "Created": [
                "date": [
                    "start": ISO8601DateFormatter().string(from: conversation.createdAt)
                ]
            ],
            "Updated": [
                "date": [
                    "start": ISO8601DateFormatter().string(from: conversation.updatedAt)
                ]
            ],
            "MessageCount": [
                "number": conversation.messages.count
            ]
        ]
      
        // 内容（转换为 Notion Blocks）
        payload["children"] = buildNotionBlocks(messages: conversation.messages)
      
        return payload
    }
  
    // MARK: - 构建 Notion Blocks
  
    private func buildNotionBlocks(messages: [Message]) -> [[String: Any]] {
        var blocks: [[String: Any]] = []
      
        for message in messages {
            // 角色标题
            let roleText = message.role == "user" ? "👤 用户" : "🤖 助手"
            blocks.append([
                "object": "block",
                "type": "heading_3",
                "heading_3": [
                    "rich_text": [
                        [
                            "type": "text",
                            "text": [
                                "content": roleText
                            ]
                        ]
                    ]
                ]
            ])
          
            // 消息内容（分段处理，Notion 单个 block 有长度限制）
            let contentChunks = splitContent(message.content, maxLength: 2000)
            for chunk in contentChunks {
                blocks.append([
                    "object": "block",
                    "type": "paragraph",
                    "paragraph": [
                        "rich_text": [
                            [
                                "type": "text",
                                "text": [
                                    "content": chunk
                                ]
                            ]
                        ]
                    ]
                ])
            }
          
            // 分隔线
            blocks.append([
                "object": "block",
                "type": "divider",
                "divider": [:]
            ])
        }
      
        return blocks
    }
  
    // MARK: - 辅助方法
  
    private func splitContent(_ content: String, maxLength: Int) -> [String] {
        var chunks: [String] = []
        var currentIndex = content.startIndex
      
        while currentIndex < content.endIndex {
            let endIndex = content.index(currentIndex, offsetBy: maxLength, limitedBy: content.endIndex) ?? content.endIndex
            chunks.append(String(content[currentIndex..<endIndex]))
            currentIndex = endIndex
        }
      
        return chunks
    }
}
```

### SettingsViewModel.swift
```swift
import Foundation
import SwiftUI
import SwiftData

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var apiEndpoint: String = ""
    @Published var apiKey: String = ""
    @Published var apiModel: String = "gpt-3.5-turbo"
    @Published var systemPrompt: String = ""
  
    @Published var notionEnabled: Bool = false
    @Published var notionToken: String = ""
    @Published var notionDatabaseId: String = ""
    @Published var backupStrategy: String = "manual"
  
    @Published var isTestingConnection: Bool = false
    @Published var connectionStatus: ConnectionStatus = .unknown
    @Published var lastBackupTime: Date?
  
    @Published var showApiKey: Bool = false
    @Published var showNotionToken: Bool = false
  
    private let keychainService = KeychainService.shared
    private let notionService = NotionService()
  
    enum ConnectionStatus {
        case unknown
        case testing
        case success
        case failed(String)
      
        var icon: String {
            switch self {
            case .unknown: return "circle"
            case .testing: return "arrow.clockwise"
            case .success: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }
      
        var color: Color {
            switch self {
            case .unknown: return .gray
            case .testing: return .blue
            case .success: return .green
            case .failed: return .red
            }
        }
    }
  
    // MARK: - 初始化
  
    func loadSettings(from settings: AppSettings) {
        apiEndpoint = settings.apiEndpoint
        apiModel = settings.apiModel
        systemPrompt = settings.systemPrompt ?? ""
        notionEnabled = settings.notionEnabled
        notionDatabaseId = settings.notionDatabaseId ?? ""
        backupStrategy = settings.backupStrategy
      
        // 从 Keychain 加载敏感信息
        apiKey = keychainService.read(.apiKey) ?? ""
        notionToken = keychainService.read(.notionToken) ?? ""
    }
  
    // MARK: - 保存设置
  
    func saveSettings(to settings: AppSettings) {
        settings.apiEndpoint = apiEndpoint
        settings.apiModel = apiModel
        settings.systemPrompt = systemPrompt.isEmpty ? nil : systemPrompt
        settings.notionEnabled = notionEnabled
        settings.notionDatabaseId = notionDatabaseId.isEmpty ? nil : notionDatabaseId
        settings.backupStrategy = backupStrategy
      
        // 保存敏感信息到 Keychain
        if !apiKey.isEmpty {
            _ = keychainService.save(apiKey, for: .apiKey)
        }
      
        if !notionToken.isEmpty {
            _ = keychainService.save(notionToken, for: .notionToken)
        }
    }
  
    // MARK: - 测试 Notion 连接
  
    func testNotionConnection() async {
        guard !notionToken.isEmpty, !notionDatabaseId.isEmpty else {
            connectionStatus = .failed("请填写 Token 和 Database ID")
            return
        }
      
        connectionStatus = .testing
        isTestingConnection = true
      
        // 临时保存 Token 到 Keychain
        _ = keychainService.save(notionToken, for: .notionToken)
      
        do {
            let success = try await notionService.testConnection(databaseId: notionDatabaseId)
            if success {
                connectionStatus = .success
            } else {
                connectionStatus = .failed("连接失败")
            }
        } catch {
            connectionStatus = .failed(error.localizedDescription)
        }
      
        isTestingConnection = false
    }
  
    // MARK: - 验证配置
  
    func validateSettings() -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
      
        if apiEndpoint.isEmpty {
            errors.append("API 地址不能为空")
        }
      
        if apiKey.isEmpty {
            errors.append("API Key 不能为空")
        }
      
        if notionEnabled {
            if notionToken.isEmpty {
                errors.append("Notion Token 不能为空")
            }
            if notionDatabaseId.isEmpty {
                errors.append("Notion Database ID 不能为空")
            }
        }
      
        return (errors.isEmpty, errors)
    }
}
```

### NotionViewModel.swift（备份管理）
```swift
import Foundation
import SwiftUI
import SwiftData

@MainActor
class NotionViewModel: ObservableObject {
    @Published var isBackingUp: Bool = false
    @Published var backupProgress: Double = 0.0
  
    private let notionService = NotionService()
  
    // MARK: - 备份单个对话
  
    func backupConversation(_ conversation: Conversation, settings: AppSettings) async throws {
        guard settings.notionEnabled,
              let databaseId = settings.notionDatabaseId else {
            throw NSError(domain: "Notion 备份未启用", code: -1)
        }
      
        conversation.backupStatus = "syncing"
        isBackingUp = true
      
        do {
            let pageId = try await notionService.backupConversation(conversation, databaseId: databaseId)
          
            conversation.notionPageId = pageId
            conversation.lastBackupDate = Date()
            conversation.backupStatus = "success"
            conversation.backupError = nil
          
        } catch {
            conversation.backupStatus = "failed"
            conversation.backupError = error.localizedDescription
            throw error
        }
      
        isBackingUp = false
    }
  
    // MARK: - 批量备份
  
    func backupAllConversations(_ conversations: [Conversation], settings: AppSettings) async {
        guard settings.notionEnabled else { return }
      
        isBackingUp = true
        backupProgress = 0.0
      
        let total = Double(conversations.count)
      
        for (index, conversation) in conversations.enumerated() {
            do {
                try await backupConversation(conversation, settings: settings)
            } catch {
                print("备份失败: \(conversation.title) - \(error.localizedDescription)")
            }
          
            backupProgress = Double(index + 1) / total
        }
      
        isBackingUp = false
        backupProgress = 0.0
    }
  
    // MARK: - 自动备份（在消息发送后调用）
  
    func autoBackupIfNeeded(_ conversation: Conversation, settings: AppSettings) async {
        guard settings.notionEnabled,
              settings.backupStrategy == "auto" else {
            return
        }
      
        // 后台静默备份
        Task {
            try? await backupConversation(conversation, settings: settings)
        }
    }
}
```

## UI 组件实现

### SettingsView.swift（设置面板）
```swift
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SettingsViewModel()
    @Bindable var settings: AppSettings
  
    @State private var showSaveAlert = false
    @State private var saveError: String?
  
    var body: some View {
        NavigationView {
            ZStack {
                Color.appBackground.ignoresSafeArea()
              
                ScrollView {
                    VStack(spacing: 24) {
                        // API 配置
                        SettingsSection(title: "API 配置") {
                            SettingsTextField(
                                title: "API 地址",
                                text: $viewModel.apiEndpoint,
                                placeholder: "https://api.openai.com/v1/chat/completions"
                            )
                          
                            SettingsSecureField(
                                title: "API Key",
                                text: $viewModel.apiKey,
                                placeholder: "sk-proj-...",
                                isSecure: !viewModel.showApiKey,
                                toggleAction: { viewModel.showApiKey.toggle() }
                            )
                        }
                      
                        // 模型配置
                        SettingsSection(title: "模型配置") {
                            SettingsPicker(
                                title: "默认模型",
                                selection: $viewModel.apiModel,
                                options: [
                                    "gpt-3.5-turbo": "GPT-3.5 Turbo",
                                    "gpt-4": "GPT-4",
                                    "gpt-4-turbo": "GPT-4 Turbo"
                                ]
                            )
                          
                            SettingsTextEditor(
                                title: "系统提示词（可选）",
                                text: $viewModel.systemPrompt,
                                placeholder: "You are a helpful assistant..."
                            )
                        }
                      
                        // Notion 备份配置
                        SettingsSection(title: "Notion 备份配置") {
                            SettingsToggle(
                                title: "启用自动备份",
                                isOn: $viewModel.notionEnabled
                            )
                          
                            if viewModel.notionEnabled {
                                SettingsSecureField(
                                    title: "Notion Integration Token",
                                    text: $viewModel.notionToken,
                                    placeholder: "secret_...",
                                    isSecure: !viewModel.showNotionToken,
                                    toggleAction: { viewModel.showNotionToken.toggle() }
                                )
                              
                                SettingsTextField(
                                    title: "Notion Database ID",
                                    text: $viewModel.notionDatabaseId,
                                    placeholder: "a1b2c3d4e5f6..."
                                )
                              
                                // 备份策略
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("备份策略")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.textSecondary)
                                  
                                    VStack(spacing: 8) {
                                        SettingsRadioButton(
                                            title: "每次对话后自动备份",
                                            isSelected: viewModel.backupStrategy == "auto",
                                            action: { viewModel.backupStrategy = "auto" }
                                        )
                                      
                                        SettingsRadioButton(
                                            title: "仅手动备份",
                                            isSelected: viewModel.backupStrategy == "manual",
                                            action: { viewModel.backupStrategy = "manual" }
                                        )
                                    }
                                }
                                .padding(.vertical, 8)
                              
                                // 测试连接按钮
                                Button(action: {
                                    Task {
                                        await viewModel.testNotionConnection()
                                    }
                                }) {
                                    HStack {
                                        if case .testing = viewModel.connectionStatus {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(0.8)
                                        }
                                        Text(viewModel.isTestingConnection ? "测试中..." : "测试 Notion 连接")
                                            .font(.system(size: 15, weight: .medium))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.accentPurple)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                .disabled(viewModel.isTestingConnection)
                              
                                // 连接状态
                                if case .unknown = viewModel.connectionStatus {
                                    // 不显示
                                } else {
                                    HStack(spacing: 8) {
                                        Image(systemName: viewModel.connectionStatus.icon)
                                            .foregroundColor(viewModel.connectionStatus.color)
                                      
                                        switch viewModel.connectionStatus {
                                        case .success:
                                            Text("✅ 连接成功")
                                                .foregroundColor(.green)
                                        case .failed(let error):
                                            Text("❌ \(error)")
                                                .foregroundColor(.red)
                                        case .testing:
                                            Text("🔄 测试中...")
                                                .foregroundColor(.blue)
                                        case .unknown:
                                            EmptyView()
                                        }
                                    }
                                    .font(.system(size: 13))
                                    .padding(.top, 4)
                                }
                              
                                // 最后备份时间
                                if let lastBackup = viewModel.lastBackupTime {
                                    Text("最后备份：\(lastBackup, style: .relative)前")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textSecondary)
                                        .padding(.top, 8)
                                }
                            }
                        }
                      
                        // 关于
                        SettingsSection(title: "关于") {
                            HStack {
                                Text("版本")
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                Text("1.0.0")
                                    .foregroundColor(.textSecondary)
                            }
                            .font(.system(size: 15))
                          
                            Button(action: {
                                // 打开隐私政策
                            }) {
                                HStack {
                                    Text("隐私政策")
                                        .foregroundColor(.linkColor)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.textSecondary)
                                        .font(.system(size: 12))
                                }
                                .font(.system(size: 15))
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("⚙️ 设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        saveSettings()
                    }
                    .foregroundColor(.accentPurple)
                }
              
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundColor(.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.loadSettings(from: settings)
        }
        .alert("保存设置", isPresented: $showSaveAlert) {
            Button("确定", role: .cancel) {
                if saveError == nil {
                    dismiss()
                }
            }
        } message: {
            if let error = saveError {
                Text(error)
            } else {
                Text("设置已保存")
            }
        }
    }
  
    private func saveSettings() {
        let validation = viewModel.validateSettings()
      
        if !validation.isValid {
            saveError = validation.errors.joined(separator: "\n")
            showSaveAlert = true
            return
        }
      
        viewModel.saveSettings(to: settings)
        saveError = nil
        showSaveAlert = true
    }
}

// MARK: - 设置组件

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
  
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
          
            VStack(spacing: 12) {
                content
            }
            .padding(16)
            .glassmorphic(cornerRadius: 12)
        }
    }
}

struct SettingsTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
  
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textPrimary)
          
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(.textPrimary)
                .padding(12)
                .background(Color.appBackground.opacity(0.5))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

struct SettingsSecureField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let isSecure: Bool
    let toggleAction: () -> Void
  
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textPrimary)
          
            HStack {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundColor(.textPrimary)
                } else {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundColor(.textPrimary)
                }
              
                Button(action: toggleAction) {
                    Image(systemName: isSecure ? "eye.slash" : "eye")
                        .foregroundColor(.textSecondary)
                        .font(.system(size: 14))
                }
            }
            .padding(12)
            .background(Color.appBackground.opacity(0.5))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

struct SettingsTextEditor: View {
    let title: String
    @Binding var text: String
    let placeholder: String
  
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textPrimary)
          
            TextEditor(text: $text)
                .font(.system(size: 14))
                .foregroundColor(.textPrimary)
                .frame(height: 100)
                .padding(8)
                .background(Color.appBackground.opacity(0.5))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .overlay(
                    Group {
                        if text.isEmpty {
                            Text(placeholder)
                                .font(.system(size: 14))
                                .foregroundColor(.textPlaceholder)
                                .padding(.top, 16)
                                .padding(.leading, 12)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )
        }
    }
}

struct SettingsPicker: View {
    let title: String
    @Binding var selection: String
    let options: [String: String]
  
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textPrimary)
          
            Menu {
                ForEach(Array(options.keys.sorted()), id: \.self) { key in
                    Button(options[key] ?? key) {
                        selection = key
                    }
                }
            } label: {
                HStack {
                    Text(options[selection] ?? selection)
                        .font(.system(size: 14))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(.textSecondary)
                        .font(.system(size: 12))
                }
                .padding(12)
                .background(Color.appBackground.opacity(0.5))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
        }
    }
}

struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool
  
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(.textPrimary)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.accentPurple)
        }
    }
}

struct SettingsRadioButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
  
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .accentPurple : .textSecondary)
                    .font(.system(size: 18))
              
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.textPrimary)
              
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }
}
```

### BackupStatusBadge.swift（备份状态标记）
```swift
import SwiftUI

struct BackupStatusBadge: View {
    let status: String  // "none", "success", "failed", "syncing"
    let lastBackupDate: Date?
  
    var body: some View {
        Group {
            switch status {
            case "success":
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundColor(.green)
            case "syncing":
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(0.7)
            case "failed":
                Image(systemName: "exclamationmark.icloud.fill")
                    .foregroundColor(.orange)
            default:
                Image(systemName: "icloud")
                    .foregroundColor(.textSecondary.opacity(0.5))
            }
        }
        .font(.system(size: 14))
        .help(tooltipText)
    }
  
    private var tooltipText: String {
        switch status {
        case "success":
            if let date = lastBackupDate {
                return "已备份：\(date.formatted())"
            }
            return "已备份到 Notion"
        case "syncing":
            return "备份中..."
        case "failed":
            return "备份失败，点击重试"
        default:
            return "未备份"
        }
    }
}
```

### 更新 SidebarView.swift（添加备份状态和设置按钮）
```swift
import SwiftUI

struct SidebarView: View {
    let conversations: [Conversation]
    @Binding var selectedConversation: Conversation?
    let onNewChat: () -> Void
    @Environment(\.modelContext) private var modelContext
  
    @State private var showSettings = false
    @Query private var settingsArray: [AppSettings]
  
    private var settings: AppSettings {
        if let first = settingsArray.first {
            return first
        } else {
            let newSettings = AppSettings()
            modelContext.insert(newSettings)
            return newSettings
        }
    }
  
    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏
            HStack {
                Text("OpenCat")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.textPrimary)
              
                Spacer()
              
                Button(action: onNewChat) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.textPrimary)
                        .frame(width: 44, height: 44)
                        .glassmorphic(cornerRadius: 22)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
          
            // 功能菜单（只保留新聊天）
            VStack(spacing: 12) {
                GlassButton(icon: "message", text: "新聊天", isHighlighted: true, action: onNewChat)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
          
            // 分割线
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.1), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 20)
          
            // 历史对话列表
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("昨天")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                  
                    ForEach(conversations) { conversation in
                        ConversationRow(
                            conversation: conversation,
                            isSelected: selectedConversation?.id == conversation.id,
                            settings: settings
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedConversation = conversation
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteConversation(conversation)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.bottom, 20)
            }
          
            Spacer()
          
            // 底部固定区域
            VStack(spacing: 0) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.1), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                    .padding(.horizontal, 20)
              
                // 设置按钮
                GlassButton(icon: "gearshape", text: "设置", action: {
                    showSettings = true
                })
                .padding(20)
            }
        }
        .background(Color.appBackground)
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
        }
    }
  
    private func deleteConversation(_ conversation: Conversation) {
        withAnimation {
            if selectedConversation?.id == conversation.id {
                selectedConversation = nil
            }
            modelContext.delete(conversation)
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let settings: AppSettings
    @State private var isHovered = false
  
    var body: some View {
        HStack {
            Text(conversation.title)
                .font(.system(size: 14))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
          
            Spacer()
          
            // 备份状态图标
            if settings.notionEnabled {
                BackupStatusBadge(
                    status: conversation.backupStatus,
                    lastBackupDate: conversation.lastBackupDate
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            HStack {
                                Rectangle()
                                    .fill(Color.accentPurple)
                                    .frame(width: 3)
                                Spacer()
                            }
                        )
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.05))
                }
            }
        )
        .padding(.horizontal, 12)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
```

### 更新 ChatView.swift（添加手动备份按钮和自动备份）
```swift
import SwiftUI

struct ChatView: View {
    @Bindable var conversation: Conversation
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var notionViewModel = NotionViewModel()
    @State private var inputText = ""
    @State private var isLoading = false
    @Namespace private var bottomID
  
    @Query private var settingsArray: [AppSettings]
    @Environment(\.modelContext) private var modelContext
  
    private var settings: AppSettings {
        if let first = settingsArray.first {
            return first
        } else {
            let newSettings = AppSettings()
            modelContext.insert(newSettings)
            return newSettings
        }
    }
  
    var body: some View {
        VStack(spacing: 0) {
            // 顶部导航栏
            HStack {
                Text(conversation.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.textPrimary)
              
                Spacer()
              
                HStack(spacing: 16) {
                    // 手动备份按钮
                    if settings.notionEnabled {
                        Button(action: {
                            Task {
                                try? await notionViewModel.backupConversation(conversation, settings: settings)
                            }
                        }) {
                            Image(systemName: notionViewModel.isBackingUp ? "arrow.clockwise" : "icloud.and.arrow.up")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.textPrimary)
                                .rotationEffect(.degrees(notionViewModel.isBackingUp ? 360 : 0))
                                .animation(notionViewModel.isBackingUp ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: notionViewModel.isBackingUp)
                        }
                        .disabled(notionViewModel.isBackingUp)
                    }
                  
                    // 更多选项
                    Menu {
                        Button(action: {}) {
                            Label("导出对话", systemImage: "square.and.arrow.up")
                        }
                        Button(action: {}) {
                            Label("清空对话", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.textPrimary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.05), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1),
                alignment: .bottom
            )
          
            // 消息列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(conversation.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                      
                        if isLoading {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .textSecondary))
                                    .scaleEffect(0.8)
                                Text("思考中...")
                                    .font(.system(size: 14))
                                    .foregroundColor(.textSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .transition(.opacity)
                        }
                      
                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                    }
                    .padding(.vertical, 20)
                }
                .onChange(of: conversation.messages.count) { _, _ in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
                .onChange(of: isLoading) { _, _ in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
            }
          
            // 底部输入栏
            InputBarView(
                text: $inputText,
                isLoading: isLoading,
                onSend: sendMessage
            )
        }
        .background(
            LinearGradient(
                colors: [
                    Color.appBackground,
                    Color.appBackground.opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear {
            viewModel.conversation = conversation
            viewModel.settings = settings
        }
    }
  
    private func sendMessage() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
      
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            let userMessage = Message(role: "user", content: trimmedText)
            conversation.messages.append(userMessage)
            conversation.updateTimestamp()
        }
      
        let currentInput = trimmedText
        inputText = ""
        isLoading = true
      
        Task {
            do {
                let response = try await viewModel.sendMessage(currentInput)
              
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        let assistantMessage = Message(role: "assistant", content: response)
                        conversation.messages.append(assistantMessage)
                        conversation.updateTimestamp()
                      
                        // 自动生成标题
                        if conversation.messages.count == 2 {
                            conversation.title = String(currentInput.prefix(20))
                        }
                    }
                    isLoading = false
                  
                    // 自动备份到 Notion
                    Task {
                        await notionViewModel.autoBackupIfNeeded(conversation, settings: settings)
                    }
                }
            } catch {
                await MainActor.run {
                    print("Error: \(error)")
                    isLoading = false
                }
            }
        }
    }
}
```

### 更新 ChatViewModel.swift（支持设置）
```swift
import Foundation
import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
    var conversation: Conversation?
    var settings: AppSettings?
    private let openAIService = OpenAIService()
  
    func sendMessage(_ text: String) async throws -> String {
        guard let conversation = conversation,
              let settings = settings else {
            throw NSError(domain: "未初始化", code: -1)
        }
      
        return try await openAIService.sendMessage(messages: conversation.messages, settings: settings)
    }
}
```

### 更新 ContentView.swift（初始化设置）
```swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Conversation.createdAt, order: .reverse) private var conversations: [Conversation]
    @Query private var settingsArray: [AppSettings]
    @State private var selectedConversation: Conversation?
    @State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn
  
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                conversations: conversations,
                selectedConversation: $selectedConversation,
                onNewChat: createNewConversation
            )
            .navigationSplitViewColumnWidth(AppConstants.sidebarWidth)
        } detail: {
            if let conversation = selectedConversation {
                ChatView(conversation: conversation)
            } else {
                VStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Text("选择或创建新对话")
                            .font(.title3)
                            .foregroundColor(.textSecondary)
                        Text("支持 Markdown 和 LaTeX 渲染")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary.opacity(0.7))
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color.appBackground, Color.appBackground.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            initializeSettings()
        }
    }
  
    private func createNewConversation() {
        let newConversation = Conversation(title: "新对话")
        modelContext.insert(newConversation)
        selectedConversation = newConversation
    }
  
    private func initializeSettings() {
        if settingsArray.isEmpty {
            let settings = AppSettings()
            modelContext.insert(settings)
            try? modelContext.save()
        }
    }
}
```

### 更新 OpenCatCloneApp.swift
```swift
import SwiftUI
import SwiftData

@main
struct OpenCatCloneApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [Conversation.self, Message.self, AppSettings.self])
    }
}
```

## 完整实现的其他组件

由于篇幅限制，以下组件请参考之前的完整实现：

1. **Constants.swift** - 添加新的颜色常量（成功/警告/错误色）
2. **GlassModifiers.swift** - 保持不变
3. **MarkdownView.swift** - 保持不变
4. **LaTeXView.swift** - 保持不变
5. **MarkdownParser.swift** - 保持不变
6. **MessageBubbleView.swift** - 保持不变
7. **InputBarView.swift** - 保持不变
8. **GlassButton.swift** - 保持不变

## 实现步骤

### 1. 创建 Xcode 项目
按照之前的步骤创建项目

### 2. 添加依赖
使用 SPM 添加 MarkdownUI 和 LaTeXSwiftUI

### 3. 实现顺序
1. ✅ 基础工具类（Constants, GlassModifiers, Extensions）
2. ✅ 安全存储（KeychainService）
3. ✅ 数据模型（Message, Conversation, AppSettings）
4. ✅ API 服务（OpenAIService, NotionService）
5. ✅ 视图模型（SettingsViewModel, NotionViewModel, ChatViewModel）
6. ✅ UI 组件（设置相关组件）
7. ✅ 主视图（SettingsView, SidebarView, ChatView, ContentView）
8. ✅ App 入口配置

### 4. 配置 Info.plist
添加网络权限（如需要）

### 5. 测试清单
- [ ] API 配置保存和加载
- [ ] Keychain 安全存储
- [ ] Notion 连接测试
- [ ] 自动备份功能
- [ ] 手动备份功能
- [ ] 备份状态显示
- [ ] Markdown + LaTeX 渲染
- [ ] 液态玻璃效果

## 注意事项

### 安全性
- 敏感信息（API Key, Notion Token）存储在 Keychain
- 不要将包含真实密钥的代码上传到公开仓库
- 考虑添加 Face ID / Touch ID 保护设置

### Notion 备份
- 首次使用需要创建 Notion Integration 和 Database
- Database 需要包含相应的属性字段
- 备份失败时不影响正常对话功能
- 大量消息可能导致 API 限流，考虑添加重试机制

### 性能优化
- 批量备份时使用后台队列
- 避免频繁触发自动备份
- 考虑添加备份队列和去重机制

## 参考资源

- [Notion API 官方文档](https://developers.notion.com/)
- [Keychain Services 文档](https://developer.apple.com/documentation/security/keychain_services)
- [CherryStudio GitHub](https://github.com/kangfenmao/cherry-studio)（参考备份实现）
- [OpenAI API 文档](https://platform.openai.com/docs/api-reference)

---

**完成后的功能清单**：
- ✅ 液态玻璃 UI 效果
- ✅ Markdown + LaTeX 完美渲染
- ✅ 可配置的 API 设置
- ✅ 自定义系统提示词
- ✅ Notion 自动/手动备份
- ✅ 备份状态实时显示
- ✅ Keychain 安全存储
- ✅ 深色主题优化

```