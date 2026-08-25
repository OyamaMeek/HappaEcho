# Chat Models, Attachments, and Reply Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect the SwiftUI chat workspace to the configured OpenAI-compatible service, support image selection, and let users choose models fetched from the upstream `/v1/models` endpoint.

**Architecture:** `AppEnvironment` will create a `ChatSessionController` from the current SwiftData settings and Keychain API key. `ChatView` owns its controller and photo importer, sends drafts through the controller, and renders stream and failure state. A dedicated model-list client resolves `/v1/models` from the configured chat-completions endpoint; selected model IDs are persisted in `AppSettings` as newline-delimited non-secret data.

**Tech Stack:** SwiftUI, SwiftData, PhotosUI, URLSession, XCTest, Xcode Beta.

## Global Constraints

- Minimum deployment target is iOS 17.0.
- API keys remain exclusively in Keychain through `SettingsRepository`.
- Images retain their original bytes through `AttachmentStore`.
- The upstream models endpoint is OpenAI-compatible `GET /v1/models` with a Bearer API key.
- UI tests are intentionally absent; retain unit tests and test production logic directly.

---

### Task 1: Model discovery transport and persisted model choices

**Files:**
- Modify: `HappaEcho/Models/AppSettings.swift`
- Create: `HappaEcho/Features/Chat/ModelCatalogClient.swift`
- Test: `HappaEchoTests/Chat/ModelCatalogClientTests.swift`

- [ ] Write failing tests for conversion from a completions URL to `/v1/models`, the Bearer request, and stable deduplication of `data[].id`.
- [ ] Implement the minimal `ModelCatalogClient.fetchModels(endpoint:apiKey:)` and non-secret selected-model persistence.
- [ ] Run the focused tests, then add files to the HappaEcho/HappaEchoTests build phases.

### Task 2: Settings model-selection workflow

**Files:**
- Modify: `HappaEcho/Features/Settings/SettingsViewModel.swift`
- Modify: `HappaEcho/Features/Settings/SettingsView.swift`
- Test: `HappaEchoTests/Settings/SettingsViewModelTests.swift`

- [ ] Write failing view-model tests for loading, selecting, and saving the fetched model IDs.
- [ ] Implement loading state, an error state, model selection validation, and a multi-select sheet.
- [ ] Run the focused tests.

### Task 3: Chat controller composition and streaming UI

**Files:**
- Modify: `HappaEcho/App/AppEnvironment.swift`
- Modify: `HappaEcho/App/ContentView.swift`
- Modify: `HappaEcho/Features/Chat/ChatView.swift`
- Modify: `HappaEcho/Features/Chat/MessageRow.swift`
- Test: `HappaEchoTests/Chat/ChatSessionControllerTests.swift`

- [ ] Write a failing test proving a configured session receives stream deltas and persists the terminal assistant turn.
- [ ] Compose `OpenAICompatibleClient` from the current endpoint, API key, and model settings; send chat drafts through `ChatSessionController` rather than direct persistence.
- [ ] Render an in-progress assistant bubble and visible error/retry action.
- [ ] Run focused controller tests.

### Task 4: Photo-picker draft attachment UI

**Files:**
- Modify: `HappaEcho/Features/Chat/ComposerView.swift`
- Modify: `HappaEcho/Features/Chat/ChatView.swift`
- Test: `HappaEchoTests/Chat/ChatSessionControllerTests.swift`

- [ ] Write a failing test showing draft attachments are passed to a sent user message in user order.
- [ ] Add a PhotosPicker button, import selected images with `PhotoLibraryImporter`, show removable draft attachment chips, and clean discarded drafts from `AttachmentStore`.
- [ ] Run focused chat tests.

### Task 5: About metadata and final verification

**Files:**
- Modify: `HappaEcho/Features/Settings/SettingsView.swift`
- Modify: `HappaEcho/Info.plist`

- [ ] Replace `iOS 17+` with bundle marketing/build version and a compile timestamp supplied through `INFOPLIST_KEY_HAPPAECHO_BUILD_TIME`.
- [ ] Run `xcodebuild -list`, focused unit tests, a Debug simulator build, and `git diff --check` using Xcode Beta.
