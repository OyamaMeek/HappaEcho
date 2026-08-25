# HappaEcho 开发交接

> 最后更新：2026-08-24  
> 适用对象：没有任何历史上下文、需要继续完成本项目的新 Claude Code 会话

## 1. 我们在做什么

我们正在根据 [`Agent.md`](Agent.md) 开发一款名为 **HappaEcho** 的原生 iOS/iPadOS AI 聊天应用。

已经完成产品澄清和正式设计，核心要求如下：

- 产品名和 Xcode target 名必须是 `HappaEcho`，不要沿用 `Agent.md` 中的 `OpenCat`。
- 最低支持 **iOS 17.0**。`Agent.md` 同时写了 iOS 16 和 SwiftData，但 SwiftData 从 iOS 17 才可用，因此设计已明确选择 iOS 17。
- 使用 SwiftUI、SwiftData、URLSession、Keychain。
- 支持 OpenAI Chat Completions 兼容接口和 SSE 流式回复。
- 支持照片库、相机、文件选择器导入图片。
- 图片保持来源交付给应用的原始字节，不压缩、不转码。
- 当前模型未配置视觉能力时，整条含图消息应在请求前被阻止，不允许静默退化为纯文字。
- 每条本地持久化消息都立即进入 Notion 增量备份队列。
- Notion 是单向备份；SwiftData 本地数据是唯一事实来源。
- Notion 同步必须按对话串行、支持多批 block、持久化检查点，并通过消息 UUID/批次标记避免重试重复追加。
- 首个完整助手回复后由模型生成标题；用户允许手动编辑，手动标题不得被模型覆盖。
- 视觉方向是深色、克制玻璃效果的“高效工作台”，优先保证代码、公式和长回答的阅读效率。

正式文档：

- 设计规格：[`docs/superpowers/specs/2026-08-23-happaecho-ios-design.md`](docs/superpowers/specs/2026-08-23-happaecho-ios-design.md)
- 实施计划：[`docs/superpowers/plans/2026-08-23-happaecho-ios-implementation.md`](docs/superpowers/plans/2026-08-23-happaecho-ios-implementation.md)

实施计划共 14 个任务，必须继续按 `subagent-driven-development` 流程逐任务实现、测试、独立审查，不要跳过门禁。

## 2. 仓库与分支状态

### 2.1 用户可见的主项目目录

路径：

```text
/Users/oyamahappa/Documents/GitHub/HappaEcho
```

分支：`main`

当前主分支比 `origin/main` 超前 3 个提交：

```text
a095ac3 build: scaffold HappaEcho iOS app
6f53180 docs: add HappaEcho implementation plan
050c00e docs: add HappaEcho iOS design spec
```

主目录已有可直接打开的工程：

```text
/Users/oyamahappa/Documents/GitHub/HappaEcho/HappaEcho.xcodeproj
```

用户明确要求 Xcode 工程直接位于项目目录，所以工程骨架提交 `12875ad` 已被 cherry-pick 到 `main`，在主分支上的提交号变成 `a095ac3`。

主目录当前还有未跟踪的 `.claude/`。不要不加检查地删除；其中包含实现 worktree。

### 2.2 实际持续开发的隔离 worktree

路径：

```text
/Users/oyamahappa/Documents/GitHub/HappaEcho/.claude/worktrees/happaecho-ios-implementation
```

分支：

```text
worktree-happaecho-ios-implementation
```

当前 HEAD：

```text
2ea690a fix: cancel streaming transport with consumer
```

该 worktree 当前干净，没有未提交代码。

提交历史：

```text
2ea690a fix: cancel streaming transport with consumer
adbb1ca feat: stream OpenAI-compatible chat responses
52aafd8 feat: secure provider credentials in Keychain
77d0613 feat: add SwiftData conversation model
12875ad build: scaffold HappaEcho iOS app
87d65f3 docs: add HappaEcho implementation plan
4933fad docs: add HappaEcho iOS design spec
3ca783b 0.0.0
```

注意：主分支和 worktree 中的规格、计划、工程骨架内容相同，但提交号因 cherry-pick 不同。继续开发应回到上述 worktree，不要在 `main` 上重做 Task 2 以后内容。

进入已有 worktree 时，优先使用原生 `EnterWorktree`，传入：

```text
/Users/oyamahappa/Documents/GitHub/HappaEcho/.claude/worktrees/happaecho-ios-implementation
```

不要创建第二个同名 worktree，也不要删除当前 worktree。

## 3. 已经完成什么

### Task 1：Xcode 工程骨架 — 完成且审查通过

worktree 提交：`12875ad`

已完成：

- `HappaEcho.xcodeproj`
- `HappaEcho` app target
- `HappaEchoTests` unit test target
- `HappaEchoUITests` UI test target
- 共享 scheme `HappaEcho`
- Debug/Release 配置
- iOS 17.0 deployment target
- 相机和照片权限文案
- 最小 SwiftUI 应用壳
- `.gitignore`

验证过：

- `xcodebuild -list -project HappaEcho.xcodeproj`
- iPhone 16 Pro 模拟器单元测试
- UI 启动测试
- Release simulator build

独立任务审查结果：规格 ✅，质量 Approved。

### Task 2：SwiftData 模型 — 完成且审查通过

提交：`77d0613`

已实现：

- `Conversation`
- `Message`
- `MessageAttachment`
- `NotionPageBinding`
- `AppSettings`
- 领域枚举和 `HappaEchoSchema`
- 内存 SwiftData 测试容器
- 模型持久化和级联删除测试

模型已包含后续 Notion 所需的同步状态、批次游标、远端 block 标识、附件上传状态、历史页面绑定，以及标题生成状态。

已知但非阻塞的审查备注，必须在对应后续任务处理：

1. Task 9 应使 `Message.confirmBatch` 幂等。
2. Task 9 应保留每个批次与 block ID 的分组关系，避免只存扁平数组。
3. Task 6 必须保证每个对话的消息 `sequence` 唯一且严格递增。
4. Task 9 应增加同步检查点保存后重新读取的 round-trip 测试。
5. Task 10 必须确保数据库中只有一个 `AppSettings` 记录。

### Task 3：Keychain 与设置仓库 — 完成且审查通过

提交：`52aafd8`

已实现：

- `CredentialStore` 协议
- `KeychainService`
- `SettingsRepository`
- Chat API Key 与 Notion Token 的保存、读取、更新、删除
- 使用 `kSecClassGenericPassword`
- service 固定为 `com.happaecho.credentials`
- accessibility 为 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- 测试使用随机账户名，避免碰生产账户

测试：15 个聚焦测试通过；完整单元测试通过。

已知非阻塞备注：后续可把“Keychain 返回非 Data”和“数据不是 UTF-8”拆成不同错误，并补充错误路径测试。

### Task 4：SSE 与 OpenAI 兼容流式客户端 — 代码已提交，但任务尚未通过门禁

初始提交：`adbb1ca`

已实现文件：

- `HappaEcho/Infrastructure/HTTP/ServerSentEventParser.swift`
- `HappaEcho/Infrastructure/HTTP/HTTPError.swift`
- `HappaEcho/Features/Chat/ChatCompletionTypes.swift`
- `HappaEcho/Features/Chat/OpenAICompatibleClient.swift`
- `HappaEchoTests/Chat/ServerSentEventParserTests.swift`
- `HappaEchoTests/Chat/OpenAICompatibleClientTests.swift`

已知测试状态：

- SSE parser 的 13 个测试通过。
- 聚焦流式客户端测试通过。
- 完整 `OpenAICompatibleClientTests` 曾在取消测试中挂起。

后台修复提交：`2ea690a`

该提交：

- 在流式读取循环外加入 `withTaskCancellationHandler`。
- consumer task 取消时调用 `transport.cancel()`。
- URLProtocol 测试桩的 `stopLoading()` 会通知完成。
- 取消测试在 `task.cancel()` 后增加一次 `Task.yield()`。

但是后台代理在旧会话结束时被停止，**没有留下完整的新测试报告，也没有经过独立任务审查**。因此 Task 4 绝对不能直接标记完成。

## 4. 当前卡在哪里

当前卡在 **Task 4 的取消行为完整验证与任务审查**。

最新代码在 `2ea690a`，worktree 干净。需要确认：

1. consumer 取消确实取消底层 URLSession transport。
2. `OpenAICompatibleClientTests.testCancellation...` 不再挂起。
3. `ServerSentEventParserTests` 和完整 `OpenAICompatibleClientTests` 全部通过。
4. 测试桩修改没有通过“伪造完成”掩盖生产取消 bug。
5. 取消、`[DONE]`、错误完成三条路径都只结束一次，没有 continuation double-finish 或泄漏。

旧 Task 4 报告位于：

```text
.superpowers/sdd/2026-08-23-happaecho-ios-implementation/task-4-report.md
```

它仍只记录 `adbb1ca` 和取消测试挂起，必须在完成验证后追加 `2ea690a` 的修复报告、精确测试命令与结果。

Task 4 尚未生成最终 review package，也尚未经过 task reviewer。

## 5. 新会话应从哪里继续

### 第一步：进入 worktree 并恢复 SDD 流程

1. 调用 `using-superpowers`。
2. 调用 `subagent-driven-development`，参数为：

```text
执行 docs/superpowers/plans/2026-08-23-happaecho-ios-implementation.md，逐任务完成 HappaEcho
```

3. 使用 `using-git-worktrees` 检测隔离环境。
4. 通过原生 `EnterWorktree(path: ...)` 进入现有 worktree，不要创建新的：

```text
/Users/oyamahappa/Documents/GitHub/HappaEcho/.claude/worktrees/happaecho-ios-implementation
```

### 第二步：检查 SDD 台账

台账：

```text
.superpowers/sdd/2026-08-23-happaecho-ios-implementation/progress.md
```

台账身份首行应为：

```text
# SDD ledger — plan: docs/superpowers/plans/2026-08-23-happaecho-ios-implementation.md
```

Task 1–3 已完成。Task 4 的后台修复提交可能没有被台账记录，所以必须结合 `git log` 和本交接文档恢复，不要重新实现 Task 1–3。

### 第三步：完成 Task 4 门禁

建议操作顺序：

1. 阅读 Task 4 brief、旧 report、`adbb1ca..2ea690a` diff。
2. 运行完整聚焦测试，并设置合理超时，避免再次无限挂起：

```bash
xcodebuild test -project HappaEcho.xcodeproj -scheme HappaEcho -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:HappaEchoTests/ServerSentEventParserTests -only-testing:HappaEchoTests/OpenAICompatibleClientTests
```

3. 若取消测试仍挂起，使用 `systematic-debugging`；不要通过删测试、降低断言或只改 URLProtocol 假完成来绕过。
4. 若修复需要新提交，继续提交到 worktree 分支。
5. 将测试命令、测试数量、结果和所有修复提交追加到 `task-4-report.md`。
6. 以 Task 4 的原始 BASE `52aafd82d97acad663f0c08435dd2ed6ea347eea` 生成 review package：

```bash
/Users/oyamahappa/.claude/skills/subagent-driven-development/scripts/review-package docs/superpowers/plans/2026-08-23-happaecho-ios-implementation.md 52aafd82d97acad663f0c08435dd2ed6ea347eea HEAD
```

7. 派独立 reviewer 同时给出：
   - Spec compliance ✅/❌
   - Task quality Approved/具体 findings
8. 只有 review clean 后，才在 ledger 写：

```text
Task 4: complete (commits 52aafd8..<最终 HEAD>, review clean)
```

### 第四步：继续 Task 5–14

Task 4 通过后，严格按实施计划继续：

5. 原图附件存储与多模态请求体。
6. 聊天会话控制器。
7. 自动/手动标题。
8. Notion payload 与 API client。
9. 幂等 Notion 同步协调器。
10. 设置界面与连接测试。
11. Markdown/代码/LaTeX 渲染与设计系统。
12. iPhone/iPad 自适应聊天 UI。
13. 依赖组装、生命周期恢复、删除协调器和手动验收清单。
14. 全规格追踪、完整测试、Release build 和最终全分支审查。

不要在任务之间询问是否继续；原用户已要求“继续完成”。只有真实阻塞或会改变既定设计的冲突才需要停下。

## 6. 绝对不要再踩的坑

### 6.1 不要在 `main` 重新开发

当前完整开发在 worktree。主目录只有设计、计划和工程骨架。直接在 `main` 开始 Task 2 会造成重复实现和分支分叉。

继续开发必须进入：

```text
.claude/worktrees/happaecho-ios-implementation
```

### 6.2 不要删除 `.claude/`

主目录的 `.claude/` 当前包含整个实现 worktree。它虽然在 `git status` 中显示为未跟踪，但不是垃圾目录。删除会丢失 Task 2–4 的开发分支工作区。

### 6.3 不要再次创建 Xcode 工程

`HappaEcho.xcodeproj` 已存在，已通过构建和测试，并已放到主项目目录。继续修改现有 `project.pbxproj`，每个新增 Swift 文件必须明确加入正确 target membership。

### 6.4 不要使用 `OpenCat` 名称

正式产品名是 **HappaEcho**。新增代码、copy、scheme、target、测试和文档都必须使用 HappaEcho。

### 6.5 不要把最低版本降到 iOS 16

SwiftData 要求 iOS 17，设计已明确采用 iOS 17.0。不要实现 Core Data 双栈兼容层。

### 6.6 不要把 Task 4 当成已经完成

`2ea690a` 只是未审查的取消修复。必须跑完整测试、补报告、生成 review package 并经过独立 reviewer。

### 6.7 不要让取消测试无限挂起

运行取消相关测试时使用可观察、可终止的 URLProtocol fixture，并设置命令超时。若挂起，先查清 AsyncThrowingStream consumer、producer task、URLSessionDataTask 和 continuation 的所有权链。

### 6.8 不要用测试桩掩盖生产 bug

`stopLoading()` 调用 `urlProtocolDidFinishLoading` 可能让测试退出，但不自动证明 production transport 正确。审查时必须确认生产路径的 `transport.cancel()` 会结束 delegate-backed event stream，并且没有双完成。

### 6.9 不要压缩或转码图片

用户明确选择“始终发送原图”。所谓原图是照片库 `.current` representation、相机 delegate 返回的最高质量当前表示、文件选择器原始文件字节；应用不得再压缩或转码。超过配置限制时阻止发送并指出具体文件。

### 6.10 不要把图片二进制放入 SwiftData

SwiftData 只存附件元数据和 Application Support 相对路径。原始字节放在：

```text
Application Support/HappaEcho/Attachments/<conversation UUID>/
```

### 6.11 不要按 token 同步 Notion

用户要求每条消息后同步，不是每个流式 token。用户消息持久化后立即排队；助手流结束、停止且有内容、或部分失败且有内容后持久化一次并排队。

### 6.12 不要盲目重试 Notion append

必须使用确定性消息 UUID/批次 marker、远端分页对账、持久化批次游标和每批 block ID。响应丢失时先查远端 marker，找到后补记本地状态，未找到才追加。

### 6.13 不要忽略 Task 2 的 deferred minors

尤其是：

- `confirmBatch` 幂等。
- 保留批次到 block IDs 的分组。
- 消息 sequence 严格递增。
- checkpoint round-trip 测试。
- `AppSettings` 单例。

这些是后续任务的明确输入，不是可以永久遗忘的备注。

### 6.14 不要跳过 SDD 的每任务审查

每个任务都需要：

1. implementer 测试和报告。
2. 从该任务 BASE 到 HEAD 生成 review package。
3. 独立 reviewer 给出规格和质量两个结论。
4. Important/Critical 进入 fix loop。
5. clean 后更新 ledger。

实现者自评不能替代独立审查。

### 6.15 不要对主目录执行破坏性清理

不要运行 `git clean -fdx`。这会删除 git-ignored 的 SDD 工作区，也可能破坏 `.claude/worktrees`。`.DS_Store` 可以单独忽略或删除，但要精准操作。

## 7. 验证环境

- Xcode：16.4，build 16F6。
- 已安装并使用 iPhone 16 Pro 模拟器。
- 模拟器 runtime 曾显示 iOS 18.6，而 Xcode SDK 为 18.5；iOS 17 deployment target 构建和测试已通过。
- 未安装 XcodeGen；工程是已提交的标准 `.xcodeproj`，不要依赖外部生成工具。

## 8. 完成后的分支处理

当前不要急着把 worktree 整体合并到 `main`，因为 Task 4–14 尚未完成。全部任务、最终全分支审查和 Release build 通过后：

1. 使用 `finishing-a-development-branch` skill。
2. 对比 `main` 已有的 cherry-pick 提交，避免重复应用设计/计划/工程骨架。
3. 采用合并或选择后续提交时，确认没有重复历史或冲突。
4. 未经用户明确要求，不 push、不开 PR。

## 9. 一句话恢复点

**进入现有 `worktree-happaecho-ios-implementation`，从 HEAD `2ea690a` 开始，先完整验证并独立审查 Task 4 的流式取消修复；Task 4 clean 后按实施计划继续 Task 5–14。**
