# Task 5 report: Original-image attachment store and multimodal body

## Status
Completed and committed on top of required base `f742bb995478ea86b3158d95479aaf6ce23ce4ea`.

## Files changed
- `HappaEcho/Features/Attachments/AttachmentStore.swift`
- `HappaEcho/Features/Attachments/AttachmentImporter.swift`
- `HappaEcho/Features/Chat/MultimodalRequestBody.swift`
- `HappaEchoTests/Attachments/AttachmentStoreTests.swift`
- `HappaEchoTests/Chat/MultimodalRequestBodyTests.swift`
- `HappaEcho.xcodeproj/project.pbxproj` (new sources and tests registered)

## TDD / observed RED evidence
Tests were written before implementation. The first focused test command failed as expected because the project referenced the newly specified production files before they existed:

```text
error: Build input files cannot be found: .../AttachmentStore.swift, .../AttachmentImporter.swift, .../MultimodalRequestBody.swift
```

This established the missing feature before production implementation.

## Test command and result
```bash
xcodebuild test -project /Users/oyamahappa/Documents/GitHub/HappaEcho/.claude/worktrees/happaecho-ios-implementation/HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/AttachmentStoreTests -only-testing:HappaEchoTests/MultimodalRequestBodyTests
```

Result: `TEST SUCCEEDED` — 6 focused tests passed.

Covered behavior: byte-identical transferred-data storage; metadata and non-escaping relative paths; invalid-item cleanup without deleting a valid draft; draft/orphan deletion; correct MIME Data URL and exact body-file length; per-image and total request limits before writing a request.

## Commit
`ff8efb9 feat: preserve and send original image attachments`

## Self-review
- Originals are copied atomically to Application Support attachment storage and SwiftData is only supplied metadata through `ImportedAttachment.makeMessageAttachment`.
- Image validity and pixel metadata come from ImageIO; invalid imported output is removed selectively.
- `importFile` brackets the copy with security-scoped resource start/stop.
- Photos configuration requests `.current`; camera and Photos importers send received bytes directly to the store.
- The body JSON is written to a temporary file, base64 encoding original files in chunks. It exposes exact length/content type, fresh `InputStream` creation, and cleanup.
- Xcode project source and test build entries were added.

## Final-round deterministic coverage (2026-08-24)

### Added coverage and production seams
- `PhotoLibraryImporter.importProvider` now accepts a `PhotoProviderDataLoading` progress seam when available. A deterministic fixture verifies its exact PNG bytes reach `AttachmentStore`, observes progress `[0, 0.25, 0.75, 1]`, and separately asserts picker configuration selects `.current`.
- `AttachmentStore.importFile` uses the injected `SecurityScopedResourceAccessing` adapter. Tests prove exact acquire/release pairing both after successful copying and after an unreadable-source error.
- Multimodal client tests separately verify `PreparedHTTPBody` cleanup after normal `[DONE]` completion, consumer cancellation, and a terminal transport error.
- `FileBodyStreamProvider` is the narrow body-stream seam used by the URLSession delegate. Its deterministic test consumes the first stream and proves a retransmission gets a different, fresh readable stream with the same exact bytes.

### RED/GREEN evidence
1. Photo fixture and scoped-access tests were added first. Focused RED build failed with `cannot find type 'PhotoProviderDataLoading' in scope`. Implemented the provider-progress adapter; the first GREEN run exposed unordered progress (`[0, 1, 0.25, 0.75]` versus required order), then callback resumption was serialized through the main actor. Focused AttachmentStore scope: **10 tests, 0 failures**.
2. Cleanup tests were added first. RED run failed because the public multimodal overload recursively called itself, so cleanup never occurred. Changed it to forward `Optional(body)` to the private overload. The GREEN lifecycle command passed: **3 tests, 0 failures**.
3. The retransmission test was added first. RED build failed with `cannot find 'FileBodyStreamProvider' in scope`. Added the URLSession body-stream provider seam and routed `needNewBodyStream` through it. GREEN result: **1 test, 0 failures**.

### Final Task 4 + Task 5 command and result
```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/AttachmentStoreTests -only-testing:HappaEchoTests/MultimodalRequestBodyTests -only-testing:HappaEchoTests/OpenAICompatibleClientTests -only-testing:HappaEchoTests/ServerSentEventParserTests
```

Result: `TEST SUCCEEDED` — **50 tests passed, 0 failures** (AttachmentStore 10, MultimodalRequestBody 6, OpenAICompatibleClient 19, ServerSentEventParser 15).

- No chat-client integration exists in Tasks 1–4 for replacing its existing in-memory `JSONEncoder` request construction. Task 5 provides the prepared file body and fresh stream interface; transport wiring should consume it when the chat dispatch flow is added.
- System `appintentsmetadataprocessor` emits the existing harmless metadata-extraction warning during the test build.

## iCloud file-representation progress repair (2026-08-24)

### Implementation
- Replaced the Photos data-representation seam with `PhotoFileRepresentationLoading`. Its production `NSItemProvider` adapter calls `loadFileRepresentation(forTypeIdentifier:completionHandler:)` and returns the exact `Progress` supplied by Photos.
- The importer continues to select the first registered image UTType and requests `.current`. It allocates an app-owned staging path before beginning transfer, copies the provider-owned file synchronously inside the completion callback, imports that staged file through `AttachmentStore.importFile`, and removes staging on all terminal paths. No decoding or transcoding occurs.
- `PhotoTransferState` lock-protects the active operation, retained `Progress`, KVO observation, and continuation. Cancellation cancels the provider progress and resumes once; late KVO/completion callbacks do not persist data or report terminal progress. The KVO observation is invalidated and released after success, failure, or cancellation.

### TDD evidence
The new deterministic file-provider tests were written before the adapter/state production code. The RED focused command failed during compilation with:

```text
cannot find type 'PhotoFileRepresentationLoading' in scope
```

After implementation, the controlled transfer, cancellation, provider-error, and actual `NSItemProvider(contentsOf:contentType:)` adapter cases passed.

### Manual acceptance
Added `docs/manual-integration-checklist.md` with a physical-device cloud-only case: observe intermediate progress, cancel with no draft or terminal state, complete a second import, and compare persisted bytes against the picker callback file. Execution is deferred until the Task 13 picker/progress UI exists.

### Lifecycle regression coverage (2026-08-24)
New controlled seams and deterministic tests cover three reviewed cancellation races: cancellation observed after store import deletes the persisted `ImportedAttachment`; a delayed provider completion after cancellation cannot recreate a staging artifact; and queued KVO progress is suppressed when cancellation wins before its main-actor closure executes. RED first exposed the missing injected import/delete seams; GREEN Task 4/5 result: **56 tests passed, 0 failures**.
