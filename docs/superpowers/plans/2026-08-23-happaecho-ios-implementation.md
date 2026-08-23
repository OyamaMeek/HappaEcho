# HappaEcho iOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the HappaEcho iPhone/iPad application with streaming OpenAI-compatible multimodal chat, SwiftData persistence, secure credentials, rich message rendering, and idempotent per-message Notion backup.

**Architecture:** A single SwiftUI application target uses feature-oriented folders and thin views. Protocol-backed chat and Notion clients feed actor-based coordinators; SwiftData remains the local source of truth, while original image bytes live under Application Support. Tests use in-memory SwiftData, `URLProtocol`, and service fakes.

**Tech Stack:** Xcode 16.4 Swift compiler in Swift 5 language mode, SwiftUI, SwiftData, URLSession, Security/Keychain, PhotosUI, UniformTypeIdentifiers, XCTest, iOS 17.

## Global Constraints

- Product and target name is exactly `HappaEcho`; remove all `OpenCat` copy.
- Minimum deployment target is iOS 17.0.
- Keep one application target and one unit/UI test target pair; do not add a dependency-injection framework.
- Preserve source image bytes; never compress or transcode imported images.
- A user message is persisted before streaming begins and immediately becomes eligible for Notion sync.
- A streamed assistant message is persisted only after completion, stop with non-empty content, or partial failure with non-empty content.
- Notion is a one-way backup; local SwiftData is authoritative.
- Store only chat API key and Notion token in Keychain.
- Use Chinese user-facing copy established by the design spec.
- Use test-first development and commit after every task.

## File Map

- `HappaEcho.xcodeproj/project.pbxproj` — reproducible app, unit-test, and UI-test targets.
- `HappaEcho/App/HappaEchoApp.swift` — app entry and SwiftData container.
- `HappaEcho/App/ContentView.swift` — adaptive split/stack navigation composition.
- `HappaEcho/Models/*.swift` — SwiftData entities and domain enums only.
- `HappaEcho/Infrastructure/HTTP/*.swift` — endpoint-agnostic HTTP and SSE parsing.
- `HappaEcho/Infrastructure/Security/KeychainService.swift` — credential persistence.
- `HappaEcho/Features/Attachments/*.swift` — original-byte import, metadata, cleanup, and previews.
- `HappaEcho/Features/Chat/*.swift` — request DTOs, chat client, session controller, and chat UI.
- `HappaEcho/Features/Titles/*.swift` — automatic/manual title state machine.
- `HappaEcho/Features/Notion/*.swift` — DTO formatter, API client, and sync actor.
- `HappaEcho/Features/Settings/*.swift` — settings form and connectivity checks.
- `HappaEcho/DesignSystem/*.swift` — productivity-glass tokens and components.
- `HappaEcho/Rendering/*.swift` — Markdown, code, table, and LaTeX parsing/rendering with raw-text fallback.
- `HappaEchoTests/**/*Tests.swift` — unit and integration-style tests with fakes.
- `HappaEchoUITests/HappaEchoUITests.swift` — adaptive shell and primary-path smoke tests.

---

### Task 1: Reproducible Xcode project and application shell

**Files:**
- Create: `HappaEcho.xcodeproj/project.pbxproj`
- Create: `HappaEcho/Info.plist`
- Create: `HappaEcho/App/HappaEchoApp.swift`
- Create: `HappaEcho/App/ContentView.swift`
- Create: `HappaEchoTests/HappaEchoTests.swift`
- Create: `HappaEchoUITests/HappaEchoUITests.swift`
- Create: `.gitignore`

**Interfaces:**
- Produces: `@main struct HappaEchoApp: App`, `struct ContentView: View`.
- Produces schemes discoverable through `xcodebuild -list -project HappaEcho.xcodeproj`.

- [ ] **Step 1: Add the minimal app and smoke tests**

```swift
// HappaEchoTests/HappaEchoTests.swift
import XCTest
@testable import HappaEcho

final class HappaEchoTests: XCTestCase {
    func testProductNameIsHappaEcho() {
        XCTAssertEqual(AppIdentity.name, "HappaEcho")
    }
}
```

```swift
// HappaEchoUITests/HappaEchoUITests.swift
import XCTest

final class HappaEchoUITests: XCTestCase {
    func testLaunchShowsNewConversationAction() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["新建对话"].waitForExistence(timeout: 5))
    }
}
```

- [ ] **Step 2: Create the project with iOS 17 app/unit/UI test targets**

Set `PRODUCT_BUNDLE_IDENTIFIER` to `com.happaecho.app`, `IPHONEOS_DEPLOYMENT_TARGET` to `17.0`, `SWIFT_VERSION` to `5.0`, and include camera/photo usage descriptions in `Info.plist`. Add `.DS_Store`, `.superpowers/`, `DerivedData/`, and `xcuserdata/` to `.gitignore`.

- [ ] **Step 3: Build and run the focused unit test**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/HappaEchoTests
```

Expected: `** TEST SUCCEEDED **` and the app shell exposes the “新建对话” accessibility label.

- [ ] **Step 4: Commit**

```bash
git add .gitignore HappaEcho.xcodeproj HappaEcho HappaEchoTests HappaEchoUITests
git commit -m "build: scaffold HappaEcho iOS app"
```

### Task 2: SwiftData domain model

**Files:**
- Create: `HappaEcho/Models/DomainEnums.swift`
- Create: `HappaEcho/Models/Conversation.swift`
- Create: `HappaEcho/Models/Message.swift`
- Create: `HappaEcho/Models/MessageAttachment.swift`
- Create: `HappaEcho/Models/NotionPageBinding.swift`
- Create: `HappaEcho/Models/AppSettings.swift`
- Create: `HappaEcho/Models/HappaEchoSchema.swift`
- Test: `HappaEchoTests/Models/ModelPersistenceTests.swift`

**Interfaces:**
- Produces: `HappaEchoSchema.makeContainer(inMemory:) throws -> ModelContainer`.
- Produces: `MessageRole`, `GenerationState`, `SyncState`, `Conversation`, `Message`, `MessageAttachment`, `NotionPageBinding`, `AppSettings`.

- [ ] **Step 1: Write failing persistence tests**

Test that a conversation persists messages in `sequence` order, deletion cascades to messages/attachments/bindings, settings default to endpoint `https://api.openai.com/v1/chat/completions`, and every new message starts with `.pending` sync state.

```swift
func testNewMessageStartsPending() throws {
    let message = Message(role: .user, content: "你好", sequence: 0)
    XCTAssertEqual(message.syncState, .pending)
}
```

- [ ] **Step 2: Run tests and confirm missing model failures**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/ModelPersistenceTests
```

- [ ] **Step 3: Implement focused `@Model` entities and schema**

Use UUID raw values for stable identity, `@Relationship(deleteRule: .cascade)` for owned records, explicit integer sequence ordering, and one active `NotionPageBinding` invariant enforced by a helper on `Conversation`. Include `Message.nextNotionBatchIndex`, serialized confirmed batch/block IDs, sync error and confirmation timestamps; `MessageAttachment` upload ID/URL/image-block ID/sync error; conversation last-sync/error fields; and a persisted title-generation-attempt flag. These fields are the checkpoints consumed by Tasks 7 and 9.

- [ ] **Step 4: Run model tests**

Use the Step 2 command; expected `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add HappaEcho/Models HappaEchoTests/Models
git commit -m "feat: add SwiftData conversation model"
```

### Task 3: Keychain and settings repository

**Files:**
- Create: `HappaEcho/Infrastructure/Security/KeychainService.swift`
- Create: `HappaEcho/Features/Settings/SettingsRepository.swift`
- Test: `HappaEchoTests/Settings/KeychainServiceTests.swift`
- Test: `HappaEchoTests/Settings/SettingsRepositoryTests.swift`

**Interfaces:**
- Produces: `protocol CredentialStore { func set(_:Data, account:String) throws; func data(account:String) throws -> Data?; func delete(account:String) throws }`.
- Produces: `SettingsRepository.loadChatAPIKey()`, `saveChatAPIKey(_:)`, `loadNotionToken()`, `saveNotionToken(_:)`.

- [ ] **Step 1: Write credential tests using a namespaced test service**

Verify insert, read, update, delete, UTF-8 conversion, and that `AppSettings` contains no secret properties.

- [ ] **Step 2: Run and observe missing-type failures**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/KeychainServiceTests -only-testing:HappaEchoTests/SettingsRepositoryTests
```

- [ ] **Step 3: Implement Security.framework wrapper**

Use `kSecClassGenericPassword`, service `com.happaecho.credentials`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, update on duplicate item, and typed `KeychainError` mapping.

- [ ] **Step 4: Run tests and commit**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/KeychainServiceTests -only-testing:HappaEchoTests/SettingsRepositoryTests
git add HappaEcho/Infrastructure/Security HappaEcho/Features/Settings HappaEchoTests/Settings
git commit -m "feat: secure provider credentials in Keychain"
```

### Task 4: SSE parser and OpenAI-compatible streaming client

**Files:**
- Create: `HappaEcho/Infrastructure/HTTP/ServerSentEventParser.swift`
- Create: `HappaEcho/Infrastructure/HTTP/HTTPError.swift`
- Create: `HappaEcho/Features/Chat/ChatCompletionTypes.swift`
- Create: `HappaEcho/Features/Chat/OpenAICompatibleClient.swift`
- Test: `HappaEchoTests/Chat/ServerSentEventParserTests.swift`
- Test: `HappaEchoTests/Chat/OpenAICompatibleClientTests.swift`

**Interfaces:**
- Produces: `protocol ChatCompletionService { func stream(request: ChatRequest) -> AsyncThrowingStream<String, Error>; func generateTitle(request: TitleRequest) async throws -> String }`.
- Produces: `ChatRequest` with ordered `ChatInputMessage` values and text/image content parts.

- [ ] **Step 1: Write parser and request tests**

Cover split UTF-8 bytes, CRLF/LF, multiple `data:` lines, blank event boundaries, `[DONE]`, malformed JSON, HTTP 401/429/500, and ensure each input message is encoded once.

- [ ] **Step 2: Verify failures**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/ServerSentEventParserTests -only-testing:HappaEchoTests/OpenAICompatibleClientTests
```

- [ ] **Step 3: Implement incremental SSE parsing and URLSession client**

Decode `choices[].delta.content`, terminate on `[DONE]`, validate HTTP status before yielding, map provider error bodies to `ChatServiceError`, and never swallow cancellation.

- [ ] **Step 4: Run tests and commit**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/ServerSentEventParserTests -only-testing:HappaEchoTests/OpenAICompatibleClientTests
git add HappaEcho/Infrastructure/HTTP HappaEcho/Features/Chat HappaEchoTests/Chat
git commit -m "feat: stream OpenAI-compatible chat responses"
```

### Task 5: Original-image attachment store and multimodal body

**Files:**
- Create: `HappaEcho/Features/Attachments/AttachmentStore.swift`
- Create: `HappaEcho/Features/Attachments/AttachmentImporter.swift`
- Create: `HappaEcho/Features/Chat/MultimodalRequestBody.swift`
- Test: `HappaEchoTests/Attachments/AttachmentStoreTests.swift`
- Test: `HappaEchoTests/Chat/MultimodalRequestBodyTests.swift`

**Interfaces:**
- Produces: `AttachmentStore.importFile(from:conversationID:) async throws -> ImportedAttachment`, `importTransferredData(_:suggestedName:contentType:conversationID:) async throws -> ImportedAttachment`, `deleteDraft(_:)`, and orphan cleanup methods.
- Produces: `PhotoLibraryImporter` configured with `PHPickerConfiguration.preferredAssetRepresentationMode = .current`, progress reporting for transferred iCloud items, and `CameraImporter` that persists the highest-quality bytes returned by the capture delegate.
- Produces: `MultimodalRequestBody.prepareTemporaryFile() async throws -> PreparedHTTPBody`, where `PreparedHTTPBody` contains a body-file URL, exact content length/content type, and cleanup closure; every retry opens a fresh `InputStream` from the file.

- [ ] **Step 1: Write byte-preservation and validation tests**

Use a deterministic PNG fixture; assert imported bytes match exactly for file, transferred Photos data, and camera data; relative paths cannot escape the attachment root; security-scoped access ends after the copy; invalid images identify and remove only that draft item; iCloud progress reaches completion; deletion removes unsent/orphan files; image order remains stable; Base64 Data URLs use the correct MIME type; and configured per-image/total limits throw before a request begins.

- [ ] **Step 2: Run failing tests**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/AttachmentStoreTests -only-testing:HappaEchoTests/MultimodalRequestBodyTests
```

- [ ] **Step 3: Implement file-backed imports and streamed body writing**

Copy security-scoped file URLs into `Application Support/HappaEcho/Attachments/<conversation UUID>/`; use atomic writes, MIME detection through UTType, checked Base64 size arithmetic, and generate a temporary file-backed HTTP body incrementally. Set exact `Content-Length`; the chat client opens a fresh stream/file handle for retries or authentication redirects and removes the temporary body on success, cancellation, or terminal failure, so all originals and encoded copies are never resident together.

- [ ] **Step 4: Run tests and commit**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/AttachmentStoreTests -only-testing:HappaEchoTests/MultimodalRequestBodyTests
git add HappaEcho/Features/Attachments HappaEcho/Features/Chat/MultimodalRequestBody.swift HappaEchoTests/Attachments HappaEchoTests/Chat/MultimodalRequestBodyTests.swift
git commit -m "feat: preserve and send original image attachments"
```

### Task 6: Chat session controller

**Files:**
- Create: `HappaEcho/Features/Chat/ChatSessionController.swift`
- Create: `HappaEcho/Features/Chat/ChatSessionState.swift`
- Test: `HappaEchoTests/Chat/ChatSessionControllerTests.swift`

**Interfaces:**
- Consumes: `ChatCompletionService`, `ModelContext`, `AttachmentStore`, and `NotionSyncScheduling`.
- Produces: `send(text:attachments:conversation:) async`, `continueGeneration(after:in:) async`, `stop(conversationID:)`, and observable per-conversation generation state.

- [ ] **Step 1: Write state-machine tests**

Cover immediate user persistence, exactly-once context ordering, one active generation per conversation, completed response persistence, zero-delta stop, non-empty stop, empty failure, partial failure, continuation after `failedPartial` using the saved partial assistant content exactly once in context, conversation switching without cancellation, unsupported-vision blocking, and context-limit draft restoration.

- [ ] **Step 2: Confirm tests fail**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/ChatSessionControllerTests
```

- [ ] **Step 3: Implement controller with task ownership by conversation UUID**

Keep assistant text transient until terminal state, use `withTaskCancellationHandler`, save partial content only when non-empty, and call `syncScheduler.enqueue(messageID:)` immediately after every persisted message.

- [ ] **Step 4: Run tests and commit**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/ChatSessionControllerTests
git add HappaEcho/Features/Chat/ChatSessionController.swift HappaEcho/Features/Chat/ChatSessionState.swift HappaEchoTests/Chat/ChatSessionControllerTests.swift
git commit -m "feat: coordinate persistent streaming conversations"
```

### Task 7: Automatic and manual conversation titles

**Files:**
- Create: `HappaEcho/Features/Titles/TitleGenerationCoordinator.swift`
- Test: `HappaEchoTests/Titles/TitleGenerationCoordinatorTests.swift`

**Interfaces:**
- Produces: `generateIfEligible(for:) async` and `setManualTitle(_:for:) async throws`.

- [ ] **Step 1: Write title lifecycle tests**

Verify only the first `.completed` assistant response triggers once; stopped/partial first replies immediately apply the first-user-message fallback but leave model generation eligible for the first later completed reply; output strips quotes/newlines and caps at 30 grapheme clusters; request failure keeps the fallback; and a manual edit made during generation cancels/invalidates the model result.

- [ ] **Step 2: Run failing tests**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/TitleGenerationCoordinatorTests
```

- [ ] **Step 3: Implement generation token and final manual-edit guard**

Persist an attempt flag only when a model request actually starts, apply the first-user fallback for stopped/partial/error states, normalize generated output with `Character`-based truncation, and enqueue only a Notion metadata update after title changes.

- [ ] **Step 4: Run tests and commit**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/TitleGenerationCoordinatorTests
git add HappaEcho/Features/Titles HappaEchoTests/Titles
git commit -m "feat: generate and protect conversation titles"
```

### Task 8: Notion payload formatting and API client

**Files:**
- Create: `HappaEcho/Features/Notion/NotionTypes.swift`
- Create: `HappaEcho/Features/Notion/NotionBlockFormatter.swift`
- Create: `HappaEcho/Features/Notion/NotionClient.swift`
- Test: `HappaEchoTests/Notion/NotionBlockFormatterTests.swift`
- Test: `HappaEchoTests/Notion/NotionClientTests.swift`

**Interfaces:**
- Produces: `protocol NotionService: Sendable` with `createPage(_ request: NotionPageRequest) async throws -> NotionPage`, `updatePageProperties(pageID:String, properties:[String:NotionProperty]) async throws`, `appendBlocks(pageID:String, blocks:[NotionBlock]) async throws -> [String]`, `listBlocks(pageID:String, cursor:String?) async throws -> NotionBlockPage`, `createFileUpload(_:) async throws -> NotionFileUpload`, `sendFile(uploadID:String,fileURL:URL) async throws`, and `completeFileUpload(uploadID:String) async throws -> NotionFileUpload`.
- Produces deterministic `NotionBlockBatch` values with marker `happaecho-message:<UUID>:batch:<index>`.

- [ ] **Step 1: Write formatter/client tests**

Verify Title/Created/Updated/Model/MessageCount/Status properties, 2,000-character rich-text splitting, deterministic Markdown headings/lists/quotes/code fallback, raw LaTeX preservation, block-count batching, exact markers, pagination, Notion version header, upload lifecycle, and error mapping for 401/403/404/429/5xx.

- [ ] **Step 2: Run failing tests**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/NotionBlockFormatterTests -only-testing:HappaEchoTests/NotionClientTests
```

- [ ] **Step 3: Implement Codable DTOs and client methods**

Use `Authorization: Bearer`, a single pinned Notion API version constant, paginated child reads, explicit file upload stages, and typed `NotionError` carrying retry delay when present.

- [ ] **Step 4: Run tests and commit**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/NotionBlockFormatterTests -only-testing:HappaEchoTests/NotionClientTests
git add HappaEcho/Features/Notion HappaEchoTests/Notion
git commit -m "feat: add Notion backup API client"
```

### Task 9: Idempotent Notion synchronization coordinator

**Files:**
- Create: `HappaEcho/Features/Notion/NotionSyncCoordinator.swift`
- Create: `HappaEcho/Features/Notion/NotionSyncScheduling.swift`
- Test: `HappaEchoTests/Notion/NotionSyncCoordinatorTests.swift`

**Interfaces:**
- Produces: `protocol NotionSyncScheduling: Sendable` with nonisolated enqueue shims `enqueue(messageID: UUID)`, `enqueueMetadata(conversationID: UUID)`, `resumePending()`, and `cancel(conversationID: UUID)`; each forwards into the `NotionSyncCoordinator` actor. SwiftData fetches and mutations execute through an injected `@MainActor ModelStore` protocol so `ModelContext` never crosses actor boundaries.

- [ ] **Step 1: Write coordinator tests with a scripted fake service**

Cover per-conversation serialization, cross-conversation concurrency, coalescing, disabled queue suspension, re-enable scan, initial page binding, database change history, image upload resume, multi-batch cursor persistence, lost-response reconciliation by marker, no duplicate append, 429 `Retry-After`, exponential retry capped at three, permanent auth/not-found failure, and derived conversation state.

- [ ] **Step 2: Run failing tests**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/NotionSyncCoordinatorTests
```

- [ ] **Step 3: Implement actor-based queues and persisted checkpoints**

Use one FIFO worker task per conversation, mutate SwiftData on `@MainActor`, save uploaded-file IDs and every confirmed batch before advancing, reconcile uncertain responses through paginated marker lookup, and derive `none/syncing/success/failed` without storing conflicting duplicate state.

- [ ] **Step 4: Run tests and commit**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/NotionSyncCoordinatorTests
git add HappaEcho/Features/Notion/NotionSyncCoordinator.swift HappaEcho/Features/Notion/NotionSyncScheduling.swift HappaEchoTests/Notion/NotionSyncCoordinatorTests.swift
git commit -m "feat: synchronize Notion backups idempotently"
```

### Task 10: Settings and connection testing UI

**Files:**
- Create: `HappaEcho/Features/Settings/SettingsViewModel.swift`
- Create: `HappaEcho/Features/Settings/SettingsView.swift`
- Test: `HappaEchoTests/Settings/SettingsViewModelTests.swift`

**Interfaces:**
- Consumes: settings repository, chat client factory, Notion service.
- Produces validated save state and `testNotionConnection()` result.

- [ ] **Step 1: Write validation tests**

Cover valid HTTPS endpoint, invalid URL, required model, optional custom per-image/total limits, masked secrets, secret preservation when fields remain unchanged, and Notion connection success/auth/not-found errors.

- [ ] **Step 2: Run tests, implement view model and form, rerun**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/SettingsViewModelTests
```

The form must have API, Notion, and About sections; secure fields reveal only on explicit action; do not include a dead privacy-policy control.

- [ ] **Step 3: Commit**

```bash
git add HappaEcho/Features/Settings HappaEchoTests/Settings
git commit -m "feat: add secure provider settings"
```

### Task 11: Message rendering and productivity-glass system

**Files:**
- Create: `HappaEcho/DesignSystem/HappaEchoTheme.swift`
- Create: `HappaEcho/DesignSystem/GlassSurface.swift`
- Create: `HappaEcho/Rendering/MessageDocumentParser.swift`
- Create: `HappaEcho/Rendering/MessageContentView.swift`
- Create: `HappaEcho/Rendering/LaTeXRenderer.swift`
- Create: `HappaEcho/Rendering/CodeBlockView.swift`
- Test: `HappaEchoTests/Rendering/MessageDocumentParserTests.swift`

**Interfaces:**
- Produces: deterministic `MessageDocument` nodes and `MessageContentView(content:)`.

- [ ] **Step 1: Write parser tests**

Cover headings, paragraphs, lists, quotes, links, tables, fenced/inline code, `$...$`, `$$...$$`, malformed delimiters, and raw-text fallback.

- [ ] **Step 2: Run tests and implement native parser/renderer**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/MessageDocumentParserTests
```

Use `AttributedString(markdown:)` for inline Markdown, dedicated scroll views for tables/code/display math, selectable text, copy buttons, Dynamic Type, Reduce Transparency fallback to opaque surfaces, and VoiceOver labels. Implement `LaTeXRenderer.render(_ expression: String, displayMode: Bool) -> Result<Image, LaTeXRenderError>` with Core Graphics/Core Text for fractions, superscripts, subscripts, roots, common Greek symbols, operators, and grouped expressions; cache by expression/font scale. Unsupported syntax returns failure and `MessageContentView` renders the exact source formula. Under Reduce Motion, disable glow/stream insertion animations and use opacity-free state changes.

- [ ] **Step 3: Run tests and commit**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/MessageDocumentParserTests
git add HappaEcho/DesignSystem HappaEcho/Rendering HappaEchoTests/Rendering
git commit -m "feat: render rich chat messages"
```

### Task 12: Adaptive sidebar and chat interface

**Files:**
- Create: `HappaEcho/Features/Chat/SidebarView.swift`
- Create: `HappaEcho/Features/Chat/ChatView.swift`
- Create: `HappaEcho/Features/Chat/MessageRow.swift`
- Create: `HappaEcho/Features/Chat/ComposerView.swift`
- Create: `HappaEcho/Features/Attachments/AttachmentPicker.swift`
- Create: `HappaEcho/Features/Attachments/AttachmentStrip.swift`
- Create: `HappaEcho/Features/Notion/SyncStatusView.swift`
- Modify: `HappaEcho/App/ContentView.swift`
- Test: `HappaEchoUITests/HappaEchoUITests.swift`

**Interfaces:**
- Consumes all coordinators and SwiftData queries.
- Produces iPad split and iPhone stacked primary workflows.

- [ ] **Step 1: Expand UI smoke tests**

Test launch, new conversation, conversation search and time grouping, settings presentation, model-without-vision send blocking, attachment strip removal, stop button during streaming using launch-injected fakes, per-conversation generation indicators after navigation, manual title editing, Notion status detail, failed-sync retry from sidebar and chat top bar, and Reduce Motion behavior.

- [ ] **Step 2: Implement adaptive productivity-workbench UI**

Use a 280–320pt sidebar with search, calendar-day grouping, persistent generation/sync badges, and retry controls; a compact toolbar; low-saturation indigo user bubbles; document-style assistant messages; a multiline composer; PhotosPicker using the Task 5 `.current` importer and progress callback; camera capture preserving delegate-returned bytes; image-only fileImporter with scoped-access copy; ten-image limit; per-item error removal; cleanup of canceled unsent drafts; keyboard-safe layout; and bottom-near auto-scroll threshold.

- [ ] **Step 3: Run UI smoke tests on phone and tablet**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoUITests
```

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -only-testing:HappaEchoUITests
```

- [ ] **Step 4: Commit**

```bash
git add HappaEcho/App HappaEcho/Features HappaEchoUITests
git commit -m "feat: build adaptive HappaEcho workspace"
```

### Task 13: Dependency wiring, lifecycle recovery, and end-to-end verification

**Files:**
- Create: `HappaEcho/App/AppEnvironment.swift`
- Create: `HappaEcho/App/ConversationDeletionCoordinator.swift`
- Modify: `HappaEcho/App/HappaEchoApp.swift`
- Modify: `HappaEcho/App/ContentView.swift`
- Create: `HappaEchoTests/App/AppEnvironmentTests.swift`
- Create: `docs/manual-integration-checklist.md`

**Interfaces:**
- Produces one application composition root and test-injectable environment.

- [ ] **Step 1: Write composition tests**

Verify production environment uses Keychain and URLSession clients, test launch uses deterministic fakes, app activation calls `resumePending()`, and `ConversationDeletionCoordinator.delete(conversationID:) async throws` performs generation cancellation, sync cancellation, awaited task quiescence, SwiftData cascade deletion, then attachment orphan cleanup in that exact order.

- [ ] **Step 2: Implement the composition root and lifecycle hooks**

Create the SwiftData container once, construct shared services once, inject controllers through environment values, and call pending-sync recovery when scene phase becomes active.

- [ ] **Step 3: Write the manual checklist with exact cases**

Include real compatible endpoint setup, text stream, stop, partial error and continue generation, original-image byte/size observation, Photos iCloud progress, unsupported model blocking, automatic/manual title, Notion page creation, one logical append per persisted message with multi-batch recovery, image upload, database switch, offline retry, 429 retry, app relaunch recovery, failed-sync retry from both surfaces, iPhone/iPad layout, Dynamic Type, VoiceOver, Reduce Transparency, Reduce Motion, and camera unavailable behavior.

- [ ] **Step 4: Run the complete suite and analyze warnings**

```bash
xcodebuild clean test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -enableCodeCoverage YES
```

Expected: `** TEST SUCCEEDED **`; no Swift concurrency, missing-purpose-string, or project-file warnings.

- [ ] **Step 5: Run tablet UI tests and inspect git state**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -only-testing:HappaEchoUITests
```

```bash
git status --short
git diff --check
```

Expected: only intentional source/test/document changes and no whitespace errors.

- [ ] **Step 6: Commit**

```bash
git add HappaEcho HappaEchoTests docs/manual-integration-checklist.md
git commit -m "feat: complete HappaEcho application"
```

### Task 14: Final specification trace and release build

**Files:**
- Modify only if verification exposes a defect in files introduced above.

**Interfaces:**
- Consumes the completed application.
- Produces a verified Debug test result and Release simulator build.

- [ ] **Step 1: Trace every design completion criterion to a passing test or manual checklist item**

Record the mapping in the implementation session notes; add a missing automated test before fixing any uncovered behavior.

- [ ] **Step 2: Build Release configuration**

```bash
xcodebuild build -project HappaEcho.xcodeproj -scheme HappaEcho -configuration Release -destination 'generic/platform=iOS Simulator'
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run final full tests after any correction**

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit only verified corrections**

```bash
git add HappaEcho HappaEchoTests HappaEchoUITests docs
git commit -m "test: verify HappaEcho release readiness"
```
