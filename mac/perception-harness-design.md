# Perception Harness 设计文档（可直接喂给 Codex）

## 1. 目标

为 AI 桌宠项目设计一个轻量级开发 Harness，用于支持单人快速开发、调试和回放感知层行为。

Harness 的核心目标不是做重型测试平台，而是提供：

1. **诊断记录**：记录每次感知 tick 的输入、闸门判断、耗时、降级信息。
2. **场景回放**：读取 JSONL 诊断日志或 Fixture，复现 GateChain / AttentionState / PetAction 决策。
3. **Mock 输入**：不依赖真实屏幕、音频、OCR，也能模拟典型使用场景。
4. **Feature Flag 调试**：可以在 Debug 面板或配置中开关感知能力。
5. **PetAction 预览**：给定感知快照，预览桌宠会做什么。
6. **Harness 合规约束**：防止 Codex / vibe coding 时绕过 Harness 架构。

该 Harness 只面向开发环境，不进入生产用户 UI。

---

## 2. 设计原则

- **轻量内嵌**：作为客户端工程内的 `Tools/PerceptionLab` 或 Debug-only 模块存在。
- **JSONL 优先**：所有诊断数据以 JSONL 形式落盘，方便人看、脚本处理、回放。
- **纯逻辑可测**：GateChain、AttentionStateMachine、FeatureFlags、ReplayRunner 都应可单元测试。
- **不依赖真实权限**：Replay / Mock 模式不需要屏幕录制、音频、OCR 权限。
- **不阻塞主流程**：诊断写入失败不能影响感知层正常运行。
- **协议边界优先**：生产逻辑不直接调用 macOS 系统 API，而是依赖 Collector Protocol。
- **默认可降级**：高风险/高成本模块必须可关闭、可降级。
- **可扩展**：未来可接入 Agent Eval、Prompt Eval、云端日志上传，但 MVP 不做。

---

## 3. 目录结构

建议在客户端工程中增加如下目录：

```text
Sources/
├── Perception/
│   ├── ...                           # 正式感知层模块
│   ├── Collectors/
│   │   ├── IdleDetecting.swift
│   │   ├── FrontAppDetecting.swift
│   │   ├── ScreenCapturing.swift
│   │   └── ScreenStreaming.swift
│   └── Diagnostics/
│       ├── PerceptionDiagnostics.swift
│       ├── PerceptionDiagnosticEvent.swift
│       └── JSONLWriter.swift
│
├── DebugTools/                       # Debug-only，不参与生产能力
│   └── PerceptionLab/
│       ├── Replay/
│       │   ├── PerceptionReplayRunner.swift
│       │   ├── ReplayScenario.swift
│       │   └── ReplayResult.swift
│       ├── Fixtures/
│       │   ├── FixtureLoader.swift
│       │   ├── FixtureWriter.swift
│       │   └── MockScenarioFactory.swift
│       ├── Mock/
│       │   ├── MockPerceptionCollector.swift
│       │   ├── MockScreenCapture.swift
│       │   ├── MockFrontAppDetector.swift
│       │   ├── MockIdleDetector.swift
│       │   ├── MockScreenStream.swift
│       │   └── MockClock.swift
│       ├── UI/
│       │   ├── PerceptionLabView.swift
│       │   ├── GateDecisionView.swift
│       │   ├── FeatureFlagPanel.swift
│       │   └── PetActionPreviewView.swift
│       └── Scenarios/
│           ├── busy-typing.jsonl
│           ├── switch-to-chat.jsonl
│           ├── static-reading.jsonl
│           ├── co-watching-sports.jsonl
│           ├── screen-locked.jsonl
│           └── stream-fallback.jsonl
│
└── Foundation/
    └── FeatureFlags/
        └── PerceptionFeatureFlags.swift

Scripts/                              # 仓库根目录，与 Sources/ 同级
└── check_perception_boundaries.sh
```

约束：
- `Sources/Perception` 不允许 import `DebugTools`。
- `DebugTools` 只能在 `#if DEBUG` 下编译。
- 系统 API 只允许出现在指定 Collector 实现文件中。

---

## 4. 核心数据结构

### 4.1 PerceptionFeatureFlags

用于控制感知层能力开关。

```swift
struct PerceptionFeatureFlags: Codable, Equatable, Sendable {
    // Core 能力，MVP 默认开启
    var singleFrameCapture: Bool = true
    var regionDHash: Bool = true
    var multiSignalTrigger: Bool = true
    var attentionStateMachine: Bool = true
    var screenStateMonitor: Bool = true

    // Co-Watching 能力，可实验性开启
    var coWatchingStream: Bool = false
    var keyframeExtraction: Bool = false
    var ocrRecognition: Bool = false

    // Audio 能力，隐私敏感，必须用户明确授权
    var systemAudioCapture: Bool = false
    var whisperTranscription: Bool = false

    // Network 能力，必须可关闭
    var webMetadataSearch: Bool = false
}
```

要求：
- 必须 `Codable`，方便写入 JSONL。
- Debug 面板可读写。
- 正式代码通过依赖注入读取，而不是全局硬编码。
- 新增高成本/高风险能力时，必须新增对应 FeatureFlag 和测试。

---

### 4.2 ContextSnapshotHarnessDTO

Harness 不应该直接序列化 `CGImage`，而应序列化可回放的轻量 DTO。

```swift
struct ContextSnapshotHarnessDTO: Codable, Equatable, Sendable {
    var id: String
    var timestamp: Date

    var appName: String
    var windowTitles: [String]

    var idleDuration: TimeInterval
    var recentInputActive: Bool
    var attentionState: AttentionState

    var regionHash: RegionHashDTO?
    var screenshotRef: String?        // 可选：截图文件相对路径，不内嵌二进制

    var isDynamicContent: Bool
    var contentType: ContentType?
}
```

---

### 4.3 CoWatchingSnapshotHarnessDTO

```swift
struct CoWatchingSnapshotHarnessDTO: Codable, Equatable, Sendable {
    var id: String
    var timestampStart: Date
    var timestampEnd: Date

    var appName: String
    var windowTitles: [String]

    var keyframeRefs: [String]        // 关键帧文件路径或 fixture id
    var ocrText: [String]
    var audioTranscript: String?

    var contentType: ContentType
    var recentSummary: String?
}
```

---

### 4.4 RegionHashDTO

```swift
enum ScreenRegion: String, Codable, Sendable {
    case topLeft, topCenter, topRight
    case middleLeft, center, middleRight
    case bottomLeft, bottomCenter, bottomRight
}

struct RegionHashDTO: Codable, Equatable, Sendable {
    var globalDistance: Int
    var regionDistances: [ScreenRegion: Int]
    var changedRegions: [ScreenRegion]

    // 基于 64 位 dHash（8×8）的默认触发阈值，与 perception-final.md 一致
    var hasSignificantChange: Bool {
        globalDistance >= 10 || regionDistances.values.contains { $0 >= 8 }
    }
}
```

阈值后续可配置，不要写死在 DTO 内；这里仅用于默认判断。阈值口径与 perception-final.md §3 统一（64 位 dHash：全局 ≥10、区域 ≥8）。

---

### 4.5 AttentionState / ContentType / PerceptionMode

```swift
enum AttentionState: String, Codable, Sendable {
    case busy
    case observing
    case engaged
}

enum ContentType: String, Codable, Sendable {
    case movie
    case tvShow
    case sports
    case liveStream
    case course
    case game
    case office
    case coding
    case chat
    case unknown
}

enum PerceptionMode: String, Codable, Sendable {
    case normal
    case coWatching
    case lowPower
    case paused
}
```

---

### 4.6 GateDecision

记录本帧为什么分析或跳过。

```swift
enum GateDecisionKind: String, Codable, Sendable {
    case analyze
    case skipIdle
    case skipStable
    case skipAIBusy
    case skipNoScreen
    case skipPrivacyBlocked
    case pausedScreenLocked
    case pausedScreenSleeping
    case pausedSystemSleeping
    case lowPowerThrottled        // Gate 0.5：低电量 / 高热触发降级到 lowPower（见 perception-final.md §17）
    case fallback
}

struct GateDecision: Codable, Equatable, Sendable {
    var kind: GateDecisionKind
    var reasons: [String]
    var triggeredSignals: [TriggerSignal]
    var fallbacks: [String]
}

enum TriggerSignal: String, Codable, Sendable {
    case regionHashChanged
    case appChanged
    case windowTitleChanged
    case recentInputActive
    case forceRefreshInterval
    case dynamicContent
    case userInvoked
    case coWatchingKeyframe
}
```

---

## 5. 诊断日志设计

### 5.1 文件位置

开发环境建议写入：

```text
Application Support/AIPet/Diagnostics/<yyyy-MM-dd>/app.log                          # 运行日志（见 architecture-harness §3.1）
Application Support/AIPet/Diagnostics/perception/<yyyy-MM-dd>/perception.jsonl       # 诊断事件
Application Support/AIPet/Diagnostics/perception/<yyyy-MM-dd>/screenshots/
Application Support/AIPet/Diagnostics/perception/<yyyy-MM-dd>/keyframes/
```

> 区分两条通道：`perception.jsonl` 是可回放的**诊断事件**（本节主题）；`app.log` 是自由文本的**运行日志**（用于调试，规范见 architecture-harness-design.md §3.1）。二者共用同一 traceId，可交叉对应。

也可以提供 Debug 菜单：

```text
Export Diagnostic Package
```

导出为 zip：

```text
perception-diagnostic-<timestamp>.zip
├── app.log
├── perception.jsonl
├── screenshots/
├── keyframes/
└── metadata.json
```

---

### 5.2 PerceptionDiagnosticEvent

```swift
struct PerceptionDiagnosticEvent: Codable, Sendable {
    var schemaVersion: Int = 1
    var id: String
    var timestamp: Date

    // 共享诊断信封字段（见 architecture-harness-design.md §3 / §4）
    var traceId: String          // 贯穿一次完整交互的关联 id（一次 tick 为起点）
    var spanId: String           // 本模块本次处理的局部 id
    var parentSpanId: String?    // 上游 span，用于拼链路
    var module: String = "perception"

    var mode: PerceptionMode
    var featureFlags: PerceptionFeatureFlags

    var snapshot: ContextSnapshotHarnessDTO?
    var coWatchingSnapshot: CoWatchingSnapshotHarnessDTO?

    var decision: GateDecision
    var latency: PerceptionLatency
    var powerState: PowerState?
    var thermalState: String?

    var petActions: [PetActionDTO]
    var errors: [DiagnosticErrorDTO]
}
```

要求：
- GateChain 每次评估必须产出或记录 `PerceptionDiagnosticEvent`。
- ReplayRunner 以该结构作为回放输入。
- 生产逻辑不要依赖 Debug UI，但可以依赖 Diagnostics no-op 实现。
- `traceId / spanId / parentSpanId / module` 为共享诊断信封字段（architecture-harness-design.md §3）。本结构是该信封的 Perception 实例——感知专属内容（snapshot / decision / 等）即信封的 `payload`。P0 单进程内也必须按此格式生成 traceId，便于 P1 跨进程拼链路。

---

### 5.3 PerceptionLatency

```swift
struct PerceptionLatency: Codable, Equatable, Sendable {
    var idleMs: Int?
    var frontAppMs: Int?
    var captureMs: Int?
    var streamMs: Int?
    var hashMs: Int?
    var keyframeMs: Int?
    var ocrMs: Int?
    var audioMs: Int?
    var whisperMs: Int?
    var contentTypeMs: Int?
    var gateMs: Int?
    var totalMs: Int?
}
```

---

### 5.3.1 PowerState

电源 / 热状态快照，用于 Gate 0.5 决策与诊断（对应 perception-final.md §17 Gate 0.5）。

```swift
struct PowerState: Codable, Equatable, Sendable {
    var batteryLevel: Double?     // 0.0–1.0，无电池设备为 nil
    var isCharging: Bool
    var isLowPowerMode: Bool      // 系统低电量模式
}
```

`thermalState` 在事件中以 `String` 记录（如 "nominal" / "fair" / "serious" / "critical"，对应 `ProcessInfo.ThermalState`）。

---

### 5.4 PetActionDTO

用于预览桌宠输出，不强绑定真实渲染层。

```swift
enum PetActionType: String, Codable, Sendable {
    case setExpression
    case playAnimation
    case showBubble
    case suppressBubble
    case enterCoWatching
    case exitCoWatching
}

struct PetActionDTO: Codable, Equatable, Sendable {
    var type: PetActionType
    var payload: [String: String]
}
```

---

### 5.5 DiagnosticErrorDTO

```swift
struct DiagnosticErrorDTO: Codable, Equatable, Sendable {
    var module: String
    var code: String
    var message: String
    var isFallbackApplied: Bool
}
```

---

### 5.6 JSONL 示例

```json
{
  "schemaVersion": 1,
  "id": "tick-000128",
  "timestamp": "2026-06-20T10:00:00Z",
  "traceId": "trace-000128",
  "spanId": "span-perception-000128",
  "parentSpanId": null,
  "module": "perception",
  "mode": "normal",
  "featureFlags": {
    "singleFrameCapture": true,
    "regionDHash": true,
    "multiSignalTrigger": true,
    "attentionStateMachine": true,
    "screenStateMonitor": true,
    "coWatchingStream": false,
    "keyframeExtraction": false,
    "ocrRecognition": false,
    "systemAudioCapture": false,
    "whisperTranscription": false,
    "webMetadataSearch": false
  },
  "snapshot": {
    "id": "snapshot-000128",
    "timestamp": "2026-06-20T10:00:00Z",
    "appName": "Safari",
    "windowTitles": ["NBA Finals Live"],
    "idleDuration": 2.1,
    "recentInputActive": true,
    "attentionState": "observing",
    "regionHash": {
      "globalDistance": 18,
      "regionDistances": {
        "bottomRight": 45,
        "center": 12
      },
      "changedRegions": ["bottomRight"]
    },
    "screenshotRef": "screenshots/tick-000128.jpg",
    "isDynamicContent": true,
    "contentType": "sports"
  },
  "decision": {
    "kind": "analyze",
    "reasons": ["region bottomRight changed", "recent input active"],
    "triggeredSignals": ["regionHashChanged", "recentInputActive"],
    "fallbacks": []
  },
  "latency": {
    "idleMs": 0,
    "frontAppMs": 2,
    "captureMs": 12,
    "hashMs": 1,
    "gateMs": 0,
    "totalMs": 18
  },
  "petActions": [
    {
      "type": "setExpression",
      "payload": { "expression": "curious" }
    }
  ],
  "errors": []
}
```

---

## 6. JSONLWriter

实现一个异步、失败不影响主流程的 JSONL 写入器。

```swift
actor JSONLWriter {
    init(fileURL: URL)
    func append<T: Encodable>(_ value: T) async
    func flush() async
}
```

实现要求：
- 每条事件一行 JSON。
- 写入失败只记录到内存错误计数，不抛给主流程。
- 支持按日期切分文件。
- Debug 构建默认开启；Release 默认关闭或仅用户开启诊断时开启。

---

## 7. PerceptionDiagnostics

统一入口，正式感知层只依赖它，不直接操作文件。

```swift
actor PerceptionDiagnostics {
    init(enabled: Bool, rootDirectory: URL)

    func record(_ event: PerceptionDiagnosticEvent) async
    func exportPackage() async throws -> URL
    func clearOldLogs(olderThan days: Int) async
}
```

要求：
- `enabled == false` 时所有调用 no-op。
- 自动清理旧日志，默认保留 7 天。
- 导出 zip 时包含 JSONL 和引用到的截图/关键帧。
- 感知层不能直接写文件，必须通过 `PerceptionDiagnostics`。

---

## 8. Replay Harness

### 8.1 ReplayScenario

```swift
struct ReplayScenario: Codable, Sendable {
    var id: String
    var name: String
    var description: String
    var events: [PerceptionDiagnosticEvent]
}
```

---

### 8.2 PerceptionReplayRunner

回放历史事件，重新执行 GateChain / AttentionStateMachine / PetActionPlanner。

```swift
struct PerceptionReplayConfig: Codable, Sendable {
    var overrideFeatureFlags: PerceptionFeatureFlags?
    var speed: ReplaySpeed
    var startIndex: Int?
    var endIndex: Int?
}

enum ReplaySpeed: Codable, Sendable {
    case realtime
    case fast
    case step
}

actor PerceptionReplayRunner {
    init(
        gateChain: GateChain,
        attentionStateMachine: AttentionStateMachine,
        petActionPlanner: PetActionPlanning
    )

    func replay(_ scenario: ReplayScenario, config: PerceptionReplayConfig) async -> ReplayResult
}
```

要求：
- Replay 使用 DTO，不依赖真实 `CGImage` / 音频 buffer。
- Replay 可以覆盖 FeatureFlags。
- Replay 必须能统计 analyze / skip / fallback 数量。

---

### 8.3 ReplayResult

```swift
struct ReplayResult: Codable, Sendable {
    var scenarioID: String
    var totalEvents: Int
    var analyzedCount: Int
    var skippedCount: Int
    var fallbackCount: Int
    var decisions: [GateDecision]
    var petActions: [[PetActionDTO]]
    var mismatches: [ReplayMismatch]
}

struct ReplayMismatch: Codable, Sendable {
    var eventID: String
    var expected: String
    var actual: String
    var reason: String
}
```

---

## 9. Fixture / Mock 场景

### 9.1 必备场景 Fixture

至少创建以下 JSONL fixture，用于回归测试：

#### busy-typing.jsonl

```text
VS Code 前台
窗口标题不变
区域 dHash 小变化
idleDuration 断续低于 5s
预期：attentionState = busy，不弹长气泡；每 10-20s 分析一次
```

#### switch-to-chat.jsonl

```text
appName 从 VS Code → WeChat
窗口标题变化
预期：立即触发分析
```

#### static-reading.jsonl

```text
Safari 前台
无输入
区域 dHash 稳定
预期：不频繁分析，仅兜底刷新
```

#### co-watching-sports.jsonl

```text
动态内容持续变化
OCR 包含比分
音频 transcript 包含解说
预期：进入 coWatching，contentType = sports
```

#### screen-locked.jsonl

```text
screenState = locked
预期：mode = paused，不截图，不分析
```

#### stream-fallback.jsonl

```text
coWatchingStream enabled
stream start error
预期：fallback 到多帧单帧截图
```

---

### 9.2 MockScenarioFactory

提供代码生成场景，不必手写 JSONL。

```swift
enum MockScenarioKind {
    case busyTyping
    case switchToChat
    case staticReading
    case coWatchingSports
    case screenLocked
    case streamFallback
}

struct MockScenarioFactory {
    func make(_ kind: MockScenarioKind) -> ReplayScenario
}
```

---

## 10. Mock Collectors 与协议边界

为了不依赖真实系统权限，定义 Collectors 协议。

```swift
protocol IdleDetecting: Sendable {
    func secondsSinceLastInput() async -> TimeInterval
}

protocol FrontAppDetecting: Sendable {
    func detect() async -> FrontAppSnapshot
}

protocol ScreenCapturing: Sendable {
    func capture() async throws -> CapturedFrame
}

protocol ScreenStreaming: Sendable {
    func start() async throws
    func stop() async
}

// 运行日志门面（规范见 architecture-harness-design.md §3.1）
protocol Logging: Sendable {
    func log(_ level: LogLevel,
             _ message: String,
             module: String,
             traceId: String?,
             metadata: [String: String])
}
```

正式实现：

```text
CGEventSourceIdleDetector
NSWorkspaceFrontAppDetector
ScreenCaptureKitCapturer
SCStreamCapturer
FileLogger                       # 异步写 app.log，actor
```

Mock 实现：

```text
MockIdleDetector
MockFrontAppDetector
MockScreenCapture
MockScreenStream
InMemoryLogger                   # 测试中收集日志行供断言
```

要求：
- GateChain / Scheduler 不直接依赖系统 API。
- 单元测试和 Replay 使用 Mock。
- 新 Collector 必须同时提供 protocol、real implementation、mock implementation。
- Codex 不允许在业务逻辑中直接调用系统 API。

---

## 11. Harness 合规约束

这一章用于防止 Codex / vibe coding 时绕过 Harness。

### 11.1 Definition of Done

任何感知层相关修改必须满足：

```text
1. 新功能必须有 FeatureFlag，除非是 core 必需能力。
2. 新的系统 API 调用必须封装在 Collector 中。
3. 新 Collector 必须有 protocol + real implementation + mock implementation。
4. Gate 决策必须记录 PerceptionDiagnosticEvent。
5. 新触发/跳过/降级逻辑必须有单元测试或 Replay fixture。
6. 涉及典型用户场景变化时，必须新增或更新 JSONL fixture。
7. ReplayRunner 必须能复现该场景。
8. 可选模块失败必须有 fallback。
9. 普通模式不得误开 coWatchingStream / systemAudioCapture / whisperTranscription。
10. DebugTools 不得被生产 Perception 代码 import。
11. 所有测试、lint、边界检查脚本必须通过。
```

---

### 11.2 禁止直接系统 API 调用

系统 API 只能出现在指定 Collector 文件中。

| API | 允许文件 |
|---|---|
| `CGEventSource.secondsSinceLastEventType` | `CGEventSourceIdleDetector.swift` |
| `NSWorkspace.shared.frontmostApplication` | `NSWorkspaceFrontAppDetector.swift` |
| `NSWorkspace` sleep/wake notifications | `ScreenStateMonitor.swift` |
| `CGWindowListCopyWindowInfo` | `NSWorkspaceFrontAppDetector.swift` |
| `SCScreenshotManager` / `SCShareableContent` | `ScreenCaptureKitCapturer.swift` |
| `SCStream` | `SCStreamCapturer.swift` |
| `VNRecognizeTextRequest` | `OCRTextRecognizer.swift` |
| Whisper 模型调用 | `WhisperTranscriber.swift` |
| `print` / `NSLog` / 直接文件写日志 | 仅 `FileLogger.swift`（其余代码用 `Logging` 协议） |

违反规则时，必须视为架构违规，而不是普通代码风格问题。

---

### 11.3 SwiftLint 自定义规则示例

可以在 `.swiftlint.yml` 中加入：

```yaml
custom_rules:
  forbid_direct_screen_capture:
    name: "Do not call ScreenCaptureKit directly outside ScreenCapture module"
    regex: "SCScreenshotManager|SCStream|SCShareableContent"
    included: "Sources/.*\\.swift"
    excluded: "Sources/Perception/Collectors/ScreenCaptureKitCapturer.swift|Sources/Perception/Collectors/SCStreamCapturer.swift"
    message: "Use ScreenCapturing / ScreenStreaming protocol instead."

  forbid_direct_idle_detection:
    name: "Do not call CGEventSource directly outside IdleDetector"
    regex: "CGEventSource\\.secondsSinceLastEventType"
    included: "Sources/.*\\.swift"
    excluded: "Sources/Perception/Collectors/CGEventSourceIdleDetector.swift"
    message: "Use IdleDetecting protocol instead."

  forbid_direct_front_app_detection:
    name: "Do not call NSWorkspace directly outside FrontAppDetector or ScreenStateMonitor"
    regex: "NSWorkspace\\.shared"
    included: "Sources/.*\\.swift"
    excluded: "Sources/Perception/Collectors/NSWorkspaceFrontAppDetector.swift|Sources/Perception/ScreenStateMonitor.swift"
    message: "Use FrontAppDetecting / ScreenStateMonitor instead."

  forbid_direct_logging:
    name: "Do not use print / NSLog directly; use Logging protocol"
    regex: "\\b(print|NSLog)\\s*\\("
    included: "Sources/.*\\.swift"
    excluded: "Sources/Perception/FileLogger.swift"
    message: "Use the Logging protocol (inject a logger) instead of print/NSLog."
```

---

### 11.4 Boundary Script

新增脚本：

```text
Scripts/check_perception_boundaries.sh
```

脚本检查：

```text
1. SCScreenshotManager 只能出现在 ScreenCaptureKitCapturer.swift
2. SCStream 只能出现在 SCStreamCapturer.swift
3. CGEventSource 只能出现在 CGEventSourceIdleDetector.swift
4. NSWorkspace.shared 只能出现在 NSWorkspaceFrontAppDetector.swift / ScreenStateMonitor.swift
5. VNRecognizeTextRequest 只能出现在 OCRTextRecognizer.swift
6. Whisper 调用只能出现在 WhisperTranscriber.swift
7. print / NSLog 只能出现在 FileLogger.swift（其余代码用 Logging 协议）
8. DebugTools 不能被 Sources/Perception import
```

Codex 生成代码后必须运行该脚本。

---

### 11.5 FeatureFlag 合规测试

必须覆盖：

```text
1. coWatchingStream=false 时，不允许启动 SCStream。
2. keyframeExtraction=false 时，不允许执行关键帧提取。
3. ocrRecognition=false 时，不允许调用 OCR。
4. systemAudioCapture=false 时，不允许启动音频捕获。
5. whisperTranscription=false 时，不允许转写。
6. webMetadataSearch=false 时，不允许联网搜索。
```

示例：

```swift
func testCoWatchingStreamDisabledDoesNotStartStream() async throws {
    var flags = PerceptionFeatureFlags()
    flags.coWatchingStream = false

    let mockStream = MockScreenStream()
    let runner = PerceptionRunner(flags: flags, screenStream: mockStream)

    await runner.enterCoWatchingIfNeeded()

    XCTAssertFalse(mockStream.didStart)
}
```

---

### 11.6 Diagnostics 合规测试

GateChain 每次评估必须产生日志事件。

```swift
func testGateChainRecordsDiagnosticEvent() async throws {
    let diagnostics = MockPerceptionDiagnostics()
    let gateChain = GateChain(diagnostics: diagnostics, ...)

    _ = await gateChain.evaluate(...)

    XCTAssertEqual(diagnostics.events.count, 1)
    XCTAssertFalse(diagnostics.events[0].decision.reasons.isEmpty)
}
```

建议更强约束：

```swift
struct GateEvaluationResult {
    let decision: GateDecision
    let diagnosticEvent: PerceptionDiagnosticEvent
}
```

让诊断事件成为 GateChain 返回值的一部分，避免实现时被忽略。

---

### 11.7 Codex 固定任务模板

不要给 Codex 模糊任务，例如“实现共看模式”。必须使用约束模板：

```text
请实现 [功能名]，必须遵守 perception-harness-design.md 和 perception-final.md。

约束：
1. 不允许在非 Collector 文件中直接调用 macOS 系统 API。
2. 如新增感知能力，必须新增/使用 PerceptionFeatureFlags。
3. 如新增 Collector，必须提供 protocol + real implementation + mock implementation。
4. Gate 决策必须记录 PerceptionDiagnosticEvent。
5. 新触发/跳过/fallback 行为必须新增单元测试或 Replay fixture。
6. 可选模块失败必须降级，不得中断主流程。
7. DebugTools 不得被生产 Perception 代码 import。
8. 最后运行测试和边界检查脚本，并输出 Harness Compliance Report。
```

---

### 11.8 Harness Compliance Report

Codex 每次完成感知层任务后必须输出：

```text
Harness Compliance Report:
- FeatureFlag added/used: yes/no
- Diagnostics recorded: yes/no
- Mock added: yes/no
- Fixture added/updated: yes/no
- Replay test added: yes/no
- Fallback implemented: yes/no
- Forbidden direct API usage: none / details
- DebugTools imported by production code: no / details
- Tests run: ...
- Boundary script run: ...
```

---

### 11.9 先测试，后实现

对容易跑偏的模块，建议分两步给 Codex：

```text
Step 1: 只写测试和 fixture，不写实现。
Step 2: 测试确认后，再实现代码。
```

适用模块：
- GateChain
- AttentionStateMachine
- FeatureFlags
- ReplayRunner
- KeyframeExtractor
- Fallback 逻辑

---

## 12. Debug UI

如果项目有 macOS Debug 菜单，增加 `Perception Lab` 页面。

### 12.1 PerceptionLabView

包含四个区域：

```text
┌──────────────────────────────────────────────┐
│ Feature Flags                                │
├──────────────────────────────────────────────┤
│ Current Snapshot                             │
├──────────────────────────────────────────────┤
│ Gate Decision Timeline                       │
├──────────────────────────────────────────────┤
│ PetAction Preview                            │
└──────────────────────────────────────────────┘
```

---

### 12.2 FeatureFlagPanel

展示并切换：

```text
[✓] singleFrameCapture
[✓] regionDHash
[✓] multiSignalTrigger
[✓] attentionStateMachine
[ ] coWatchingStream
[ ] keyframeExtraction
[ ] ocrRecognition
[ ] systemAudioCapture
[ ] whisperTranscription
[ ] webMetadataSearch
```

要求：
- Debug 构建可实时修改。
- 修改后写入本地 debug settings。
- Release 不显示或隐藏在开发者开关后。

---

### 12.3 GateDecisionView

每帧展示：

```text
Frame #128
decision: analyze
reasons:
- region bottomRight changed
- recent input active
signals:
- regionHashChanged
- recentInputActive
latency:
- capture: 12ms
- hash: 1ms
fallbacks: none
```

---

### 12.4 PetActionPreviewView

展示 Agent / Mode 层输出：

```text
expression: curious
animation: leanForward
bubble: "最后半分钟了，这球很关键啊！"
suppressed: false
suppressReason: none
```

如果用户处于 `busy`：

```text
bubble suppressed: true
reason: attentionState=busy
```

### 12.5 Live Tick 真机验收

Debug 版 `PerceptionLab` 允许运行一次真实 macOS 感知 tick，用于在 Xcode 中验收
当前机器上的感知链路：

```text
Run Live Tick
→ Idle / FrontApp / ScreenState / Power real collectors
→ ScreenCapture real collector（需要屏幕录制权限）
→ ImageEncoder / RegionDHashComputer
→ GateChain
→ Current Snapshot / Gate Decision / errors 展示
```

要求：
- Live Tick 只存在于 DebugTools / PerceptionLab，不进入生产 Perception 代码。
- Live Tick 不直接调用系统 API，只依赖已有 collector protocol 与 real implementation。
- 屏幕录制权限失败时必须显示 fallback error，不崩溃。
- 锁屏、idle、隐私阻断等前置 gate 命中时不得截图。

---

## 13. Harness 测试用例

### 13.1 GateChain Tests

必须覆盖：

```text
1. locked screen → pausedScreenLocked
2. idle > 60s → skipIdle
3. AI busy → skipAIBusy
4. app changed → analyze
5. window title changed → analyze
6. region hash changed → analyze
7. recent input active + min interval reached → analyze
8. no signal + under force refresh → skipStable
9. force refresh interval reached → analyze
10. privacy blocked → skipPrivacyBlocked
```

---

### 13.2 AttentionStateMachine Tests

```text
1. high recent input activity → busy
2. low input + stable app → observing
3. user invoked pet → engaged
4. engaged timeout → observing
5. busy suppresses long bubble
```

---

### 13.3 Replay Tests

```text
1. busy-typing fixture replay should produce mostly busy state
2. switch-to-chat fixture should trigger immediate analyze
3. static-reading fixture should rarely analyze (仅兜底刷新)
4. screen-locked fixture should produce no capture events
5. co-watching-sports fixture should produce contentType=sports
6. stream-fallback fixture should record fallback
```

---

### 13.4 Boundary Tests / Lint

```text
1. boundary script must pass
2. SwiftLint custom rules must pass
3. Release build must not include DebugTools UI
4. Sources/Perception must not import DebugTools
```

---

## 14. Codex 实现任务拆分

> 注意：本节拆分的是 **harness 脚手架本身**（DTO / Diagnostics / Fixture / ReplayRunner /
> 边界脚本 / Debug UI），**不是感知层功能的完整 Task 清单**。感知功能实现（ScreenCapture、
> 区域 dHash、闸门链、AttentionStateMachine、OCR、共看模式、Whisper 等）的 Task 必须**以
> `perception-final.md`（含 §23 文件清单）为主来源生成**。实际推进时两者交织：先建少量
> 脚手架使后续能 test-first，再按 perception-final.md 逐个功能模块推进，每个功能配自己的
> fixture 与边界检查。下面 6 项仅作脚手架顺序参考。

建议按以下顺序生成脚手架代码。

### Task 1：基础 DTO 和 Feature Flags

生成：

```text
PerceptionFeatureFlags.swift
ContextSnapshotHarnessDTO.swift
CoWatchingSnapshotHarnessDTO.swift
RegionHashDTO.swift
GateDecision.swift
PetActionDTO.swift
```

验收：
- 全部 `Codable`。
- 可 JSON 编解码。
- 有基础单元测试。

---

### Task 2：JSONLWriter + PerceptionDiagnostics

生成：

```text
JSONLWriter.swift
PerceptionDiagnostics.swift
PerceptionDiagnosticEvent.swift
```

验收：
- 能写入 JSONL。
- 每条事件一行。
- disabled 时 no-op。
- 写入失败不抛给主流程。

---

### Task 3：Mock Scenario + Fixture Loader

生成：

```text
FixtureLoader.swift
FixtureWriter.swift
MockScenarioFactory.swift
ReplayScenario.swift
```

验收：
- 能从 JSONL 读取 scenario。
- 能生成 busyTyping / screenLocked mock scenario。

---

### Task 4：Replay Runner

生成：

```text
PerceptionReplayRunner.swift
ReplayResult.swift
ReplayMismatch.swift
```

验收：
- 能回放 scenario。
- 能统计 analyzed / skipped / fallback 数量。
- 能覆盖 feature flags。

---

### Task 5：Boundary Script + SwiftLint 规则

生成：

```text
Scripts/check_perception_boundaries.sh
.swiftlint.yml custom_rules
```

验收：
- 禁止直接系统 API 调用。
- 禁止生产 Perception import DebugTools。
- 脚本可在本地运行。

---

### Task 6：Debug UI

生成：

```text
PerceptionLabView.swift
FeatureFlagPanel.swift
GateDecisionView.swift
PetActionPreviewView.swift
```

验收：
- 能展示当前 flags。
- 能展示最近 N 条诊断事件。
- 能展示 PetAction 预览。
- 仅 Debug 编译。

---

## 15. 非目标

Harness MVP 不做：

```text
1. 云端日志上传
2. 完整 Web 后台
3. 复杂 Agent 评分系统
4. 自动 prompt 优化
5. 分布式测试
6. 真正的视频文件回放
7. 用户生产环境日志收集
```

后续可扩展，但当前只做单人开发可用的轻量工具。

---

## 16. 最终验收标准

完成后应满足：

1. 真实运行时可以产出 `perception.jsonl`。
2. JSONL 可以被 ReplayRunner 读取并复现 GateChain 决策。
3. 不需要屏幕录制/音频权限，也能通过 MockScenarioFactory 测试核心逻辑。
4. Debug UI 可以查看 Feature Flags、最近的 GateDecision、PetAction 预览。
5. 任一可选模块失败时，诊断日志能记录 fallback，主流程不崩。
6. 单人开发时，可以用 fixture 快速复现：打字、切聊天、静态阅读、看球、锁屏、流式失败等场景。
7. Codex 生成的感知层代码必须通过 harness 合规检查。
8. 生产感知代码不得直接调用系统 API，必须通过 Collector Protocol。
9. 生产感知代码不得依赖 DebugTools。
10. 每次新增感知能力都必须有 FeatureFlag、Mock、测试、诊断日志和 fallback。
