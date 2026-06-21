# 感知层 — 确定技术方案

## 1. 总体选型结论

MVP 感知层采用 **混合感知架构**：

- 普通办公/阅读/聊天场景：使用 **ScreenCaptureKit 单帧截图 + 区域 dHash + 多信号融合**
- 实时共看场景：使用 **SCStream 持续屏幕流 + 关键帧提取 + OCR + 系统音频捕获 + 本地 Whisper 转写**
- 交互策略：使用 **Busy / Observing / Engaged 三态注意力状态机**，避免用户忙碌时高频打扰
- 省资源策略：锁屏、熄屏、系统睡眠时暂停 Scheduler

## 2. 屏幕捕获方案

**选型：C — 普通模式单帧 + 共看模式流式/多帧混合**

### 普通模式

普通陪伴模式、赋能模式使用 **ScreenCaptureKit 单帧截图**：

```text
每 3-5 秒触发一次 tick
→ 通过闸门链判断是否需要截图/分析
→ 单帧截图
→ 送本地 VLM / Agent 分析
```

技术方案：

```swift
let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)

// 多显示器：优先选取前台窗口所在的显示器，回退到主显示器
guard let display = content.displays.first(where: { $0.displayID == targetDisplayID })
    ?? content.displays.first else {
    // 无可用显示器：跳过本帧，不触发 AI（见降级策略 ScreenCapture）
    return nil
}
let filter = SCContentFilter(display: display, excludingWindows: [selfWindow])
let config = SCStreamConfiguration()
config.width = display.width
config.height = display.height
config.showsCursor = false
let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
```

> 注意：`SCScreenshotManager.captureImage` 需要 **macOS 14+**，且需要「屏幕录制」TCC 权限。多显示器场景下不要用 `displays.first!` 强解包，应跟随前台窗口所在屏并做空值降级（详见「权限与系统要求」一节）。

### 共看模式

看电影、看球、看直播、看视频课程等场景使用 **SCStream 持续屏幕流**：

```text
检测到动态内容 / 用户进入共看模式
→ 启动 SCStream
→ 持续接收屏幕帧
→ 本地关键帧筛选
→ 仅把关键帧送给 AI
```

不做 30fps 全量 AI 分析，只做低成本持续感知 + 关键帧理解。

### 共看模式进入 / 退出条件（带滞回）

"动态内容"不是单一信号，需组合判断，并使用滞回避免视频暂停/缓冲时反复启停 SCStream：

```text
进入条件（需同时满足并持续 ≥ coWatchEnterSustain）：
1. 前台为视频类 App（白名单：浏览器视频页 / 播放器 / 直播客户端等）
2. 中心区域或全屏区域的 dHash 持续高频变化
3. 窗口为大窗口或全屏

退出条件（需持续 ≥ coWatchExitSustain，滞回）：
- 非动态状态（无明显画面变化）持续超过 coWatchExitSustain
- 或前台切换到非视频类 App
- 或用户手动退出共看模式
```

默认 `coWatchEnterSustain = 5s`、`coWatchExitSustain = 10s`（见末尾「默认参数表」）。退出的滞回时间故意大于进入，避免暂停几秒就退出、播放又进入导致 SCStream 反复启停、徒增功耗。

## 3. 画面变化检测方案

**选型：B — 区域 dHash**

不使用全局 dHash 作为唯一判断，而是将屏幕划分为多个区域，每个区域分别计算 dHash。

```text
┌──────┬──────┬──────┐
│ 左上 │ 中上 │ 右上 │
├──────┼──────┼──────┤
│ 左中 │ 中心 │ 右中 │
├──────┼──────┼──────┤
│ 左下 │ 中下 │ 右下 │
└──────┴──────┴──────┘
```

优势：
- 能检测聊天输入框、字幕、比分牌、弹幕等小区域变化
- 仍然非常轻量
- 比全局 dHash 更适合桌宠场景

区域 dHash 结果：

```swift
struct RegionHashResult {
    let globalDistance: Int
    let regionDistances: [ScreenRegion: Int]
    let changedRegions: [ScreenRegion]

    // 基于 64 位 dHash（8×8）的默认触发阈值
    var hasSignificantChange: Bool {
        globalDistance >= 10 || regionDistances.values.contains { $0 >= 8 }
    }
}
```

阈值说明：

- 哈希为 **64 位 dHash**，全局算一份、每个区域各算一份。
- 全局汉明距离 `≥ 10`（约 16% 位变化）即视为明显变化。
- 任一区域汉明距离 `≥ 8`（约 12.5% 位变化）即视为该区域明显变化，用于捕获字幕、比分、聊天输入框等小区域变动。
- 以上为初始默认值，需在真机用典型场景实测微调（详见末尾「默认参数表」）。不要把阈值写死在结构体里，应从配置注入。

## 4. 多信号融合触发策略

**选型：C — 完整多信号融合**

是否重新分析，不只看 dHash，而是综合多个信号。

触发重新分析的条件：

```text
满足任一条件 → 重新分析：

1. 区域 dHash 明显变化
2. 前台 App 变化
3. 窗口标题变化
4. 过去 30s 内有输入活跃，且距上次分析超过最小间隔
5. 距上次分析超过兜底刷新时间
6. 动态内容触发共看模式
```

伪代码：

```swift
func shouldAnalyze(snapshot: ContextSnapshot, state: PerceptionState) -> Bool {
    if snapshot.regionHash.hasSignificantChange { return true }
    if snapshot.appName != state.lastAppName { return true }
    if snapshot.windowTitles != state.lastWindowTitles { return true }
    if state.recentInputActive(window: 30), state.elapsedSinceLastAnalysis > minAIInterval {
        return true
    }
    if state.elapsedSinceLastAnalysis > forceRefreshInterval { return true }
    if snapshot.isDynamicContent { return true }
    return false
}
```

## 5. 输入活跃度策略

**选型：30s 近期输入活跃窗口**

不使用瞬时 `idleDuration < 5s` 判断，因为用户可能打几秒字、停几秒、再继续打。

采用滑动窗口：

```text
过去 30 秒内，只要检测到过输入，就认为用户近期处于活跃状态。
```

实现方式仍然基于 CGEventSource，不监听具体按键，不增加隐私风险。

```swift
if snapshot.idleDuration < 5 {
    recentActiveTimestamps.append(snapshot.timestamp)
}
recentActiveTimestamps.removeAll {
    snapshot.timestamp.timeIntervalSince($0) > 30
}
```

## 6. 空闲检测

**选型：CGEventSource**

```swift
let idle = CGEventSource.secondsSinceLastEventType(
    .combinedSessionState,
    eventType: CGEventType(rawValue: ~0)!
)
```

- 零开销，单次系统调用
- 覆盖键盘、鼠标、触控板等输入设备
- 无需额外权限
- 用于 idle 判断和输入活跃窗口维护

## 7. 前台应用检测

**选型：NSWorkspace + CGWindowList**

```swift
let app = NSWorkspace.shared.frontmostApplication
let appName = app?.localizedName

let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
let titles = windowList?
    .filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == app?.processIdentifier }
    .compactMap { $0[kCGWindowName as String] as? String }
```

用途：
- 判断用户是否切换 App
- 判断用户是否切换浏览器 Tab / 文档
- 辅助内容类型识别
- 作为多信号融合触发条件

## 8. 陪伴模式互动策略

**选型：C — Busy / Observing / Engaged 三态注意力状态机**

陪伴模式不等于高频打扰。桌宠需要根据用户注意力状态决定互动强度。

| 状态 | 用户状态 | 桌宠行为 |
|---|---|---|
| Busy 忙碌态 | 高频输入、写代码、打字、聊天 | 不弹长气泡，只做表情/姿态变化 |
| Observing 观察态 | 阅读、轻操作、浏览页面 | 可低频短互动 |
| Engaged 互动态 | 用户点击桌宠、主动提问、长时间停顿 | 可展开对话/深度互动 |

状态判断参考：

```text
近期输入活跃度高 → Busy
输入减少但仍在浏览/阅读 → Observing
用户主动唤起或停顿较久 → Engaged
```

初始阈值（带滞回，见末尾「默认参数表」）：

```text
Busy：过去 inputActiveWindow(30s) 内输入事件频次高（连续/高频打字、写代码、聊天）
Observing：有零星输入或纯浏览阅读，未达 Busy 频次门槛
Engaged：用户点击桌宠 / 主动提问，或长时间停顿后主动交互
Engaged → Observing：engagedTimeout(30s) 内无进一步交互则回落
```

切换需带滞回，避免在 Busy / Observing 边界反复抖动；状态机阈值应从配置注入，便于调参。

## 9. 熄屏 / 锁屏 / 系统睡眠处理

**选型：B — Gate 0 屏幕状态检测**

监听系统事件：

```swift
// 锁屏 / 解锁
com.apple.screenIsLocked
com.apple.screenIsUnlocked

// 屏幕休眠 / 唤醒
NSWorkspace.screensDidSleepNotification
NSWorkspace.screensDidWakeNotification

// 系统睡眠 / 唤醒
NSWorkspace.willSleepNotification
NSWorkspace.didWakeNotification
```

逻辑：

```text
锁屏 / 熄屏 / 系统睡眠 → 暂停 Scheduler
解锁 / 唤醒 → 恢复 Scheduler
```

这是 Gate 0，比 idle 检测更早。

## 10. 共看模式视觉采集

**选型：B — SCStream 持续屏幕流 + 关键帧**

适用于：
- 看电影
- 看电视剧
- 看球
- 看直播
- 看游戏比赛
- 看课程视频

流程：

```text
进入共看模式
→ 启动 SCStream
→ 本地持续接收帧
→ 抽帧 + 关键帧筛选
→ 多帧输入 VLM
→ Co-Watching Agent 生成互动
```

原则：
- 不把每一帧送 AI
- 只把关键帧/片段送 AI
- 视觉反应可以快，深度理解可以稍慢

## 11. 共看关键帧提取

**选型：C — 固定抽帧 + 变化量筛选**

流程：

```text
SCStream 连续帧
→ 固定间隔抽帧（例如 1fps）
→ 区域 dHash / OCR 变化量筛选
→ 保留最近 5-10 秒内最有代表性的 3-5 帧
→ 送 VLM 分析
```

优势：
- 比纯固定抽帧更有效
- 比纯变化触发更稳定
- 能避免重复静止帧浪费 AI 调用

## 12. 字幕 / 比分 / 标题识别

**选型：B — Vision Framework 本地 OCR**

```text
关键帧 / 截图
→ Vision Text Recognition
→ 提取字幕、比分、直播标题、课程标题等文本
```

用途：
- 看球时识别比分、时间、球队
- 看电影/电视剧时识别字幕
- 看直播时识别标题、弹幕、主播信息
- 看课程时识别课件标题和关键词

优势：
- macOS 原生
- 本地运行
- 隐私友好
- 不依赖云端 OCR

## 13. 系统音频捕获

**选型：B — ScreenCaptureKit 捕获系统音频**

```swift
let config = SCStreamConfiguration()
config.capturesAudio = true
config.sampleRate = 16000
config.channelCount = 1
config.excludesCurrentProcessAudio = true   // 排除桌宠自身 TTS，避免录入后再转写形成回环
```

捕获内容：
- 电影台词
- 直播解说
- 球赛解说
- 课程讲解
- 游戏声音

要求：
- 必须提供明确开关
- 必须在 UI 中说明用途
- 默认可根据隐私策略决定是否开启

## 14. 语音转写

**选型：B — 本地 Whisper 转写**

流程：

```text
系统音频
→ 5-10 秒音频片段
→ 本地 Whisper 转写
→ transcript 文本
→ 与关键帧、OCR、窗口标题一起送 Agent
```

优势：
- 本地处理，隐私更好
- 对电影、直播、球赛、课程理解帮助很大
- 比单纯画面分析更接近真人共看体验

## 15. 内容类型识别

**选型：C — 窗口标题 + 多帧视觉 + OCR + 音频转写**

识别类型：

```text
movie / tv_show / sports / live_stream / course / game
office / coding / chat / unknown
```

> 枚举口径与 perception-harness-design.md §4.5 `ContentType` 统一（此处为叙述用 snake_case，对应 Swift 枚举的 camelCase：`tvShow` / `liveStream`）。前一行为共看类内容，后一行为普通模式常见场景。

输入信号：

```json
{
  "windowTitle": "...",
  "frames": ["keyframe1", "keyframe2", "keyframe3"],
  "ocrText": ["字幕", "比分", "标题"],
  "audioTranscript": "解说/台词/课程内容"
}
```

输出：

```json
{
  "contentType": "sports",
  "confidence": 0.86,
  "summary": "用户正在观看一场篮球比赛，比赛进入最后阶段。"
}
```

## 16. 联网搜索策略

**选型：B — 只搜索公开元信息，不拉取视频源**

允许搜索：
- 片名、演员、导演、简介
- 球队、比分、赛程、球员资料
- 课程标题、公开资料
- 直播标题、公开页面信息
- 相关百科/公开元数据

明确不做：
- 拉取完整视频源
- 搜索盗版资源
- 绕过平台付费墙
- 下载影视/直播内容

Agent 工具定位：

```text
identify_media_content
→ 根据标题/OCR/音频/视觉摘要搜索公开元信息
→ 返回背景信息，辅助桌宠互动
```

## 17. 最终闸门链

```text
Gate 0: 屏幕状态检测
    └─ 锁屏 / 熄屏 / 系统睡眠 → 暂停 Scheduler

Gate 0.5: 电源 / 热状态检测
    └─ thermalState ≥ .serious 或 电量 < 20% 且未充电 → 切 lowPower

Gate 1: Idle 检测
    └─ idleDuration > 60s → 标记 idle，普通模式不截图

Gate 1.5: 隐私黑名单（前置过滤）
    └─ 前台 App / 窗口标题命中黑名单 → 根本不截图、不进入后续链路

Gate 2: AI 忙碌检测
    └─ 上一帧 AI 未完成 → skip / pending

Gate 3: 捕获策略选择
    ├─ 普通模式 → ScreenCaptureKit 单帧截图
    └─ 共看模式 → SCStream 流式帧缓存

Gate 4: 多信号融合判断
    ├─ 区域 dHash 明显变化 → 通过
    ├─ App 变化 → 通过
    ├─ 窗口标题变化 → 通过
    ├─ 近期输入活跃 + 超过最小 AI 间隔 → 通过
    ├─ 动态内容 / 共看模式关键帧触发 → 通过
    └─ 超过兜底刷新时间 → 通过

Gate 5: OCR / 音频 / 内容类型识别
    ├─ 普通模式：按需执行
    └─ 共看模式：关键帧 + OCR + 音频转写

Gate 6: 隐私二次兜底过滤
    └─ 对截图、OCR 文本、音频 transcript 再做一次敏感内容过滤
       （Gate 1.5 拦前台黑名单；此处兜底拦内容级敏感信息，
        如转写出的验证码、OCR 到的密码框内容 → 不外送、本地丢弃）

通过 → 组装 ContextSnapshot / CoWatchingSnapshot → 输出给 Agent
```

> 隐私采用「前置 + 兜底」双层：Gate 1.5 在**捕获前**按前台 App/标题拦截，确保敏感画面根本不被截图；Gate 6 在内容产出后做**二次过滤**，覆盖 OCR 文本和音频 transcript 中可能出现的敏感信息。两者缺一不可——只靠 Gate 6 会导致敏感画面已被截图并 OCR 后才过滤，为时已晚。

## 18. 输出数据结构

### 普通模式

```swift
struct ContextSnapshot {
    let screenshot: CGImage?
    let screenshotJPEG: Data?
    let appName: String
    let windowTitles: [String]
    let idleDuration: TimeInterval
    let regionHash: RegionHashResult
    let recentInputActive: Bool
    let attentionState: AttentionState
    let timestamp: Date
}
```

### 共看模式

```swift
struct CoWatchingSnapshot {
    let keyframes: [CGImage]
    let appName: String
    let windowTitles: [String]
    let ocrText: [String]
    let audioTranscript: String?
    let contentType: ContentType
    let recentSummary: String?
    let timestampRange: ClosedRange<Date>
}
```

## 19. Feature Flags（能力开关）

为保证快速迭代和稳定性，所有高成本/高风险能力都必须通过 Feature Flags 控制。

```swift
struct PerceptionFeatureFlags {
    // Core 能力，MVP 默认开启
    var singleFrameCapture = true
    var regionDHash = true
    var multiSignalTrigger = true
    var attentionStateMachine = true
    var screenStateMonitor = true

    // Co-Watching 能力，可实验性开启
    var coWatchingStream = false
    var keyframeExtraction = false
    var ocrRecognition = false

    // Audio 能力，隐私敏感，必须用户明确授权
    var systemAudioCapture = false
    var whisperTranscription = false

    // Network 能力，必须可关闭
    var webMetadataSearch = false
}
```

使用原则：

```text
1. 新能力默认可关闭
2. 高耗电能力必须可关闭
3. 隐私敏感能力必须用户明确开启
4. 某模块异常时可单独关闭，不影响主链路
5. 后续可用于灰度发布、A/B 测试、低配设备降级
```

## 20. 降级策略

每个感知模块都必须定义失败后的降级路径，避免单点失败拖垮整体体验。

| 模块 | 级别 | 失败处理 |
|---|---|---|
| ScreenStateMonitor | 必需 | 失败时退化为 idle 检测，不暂停 Scheduler |
| IdleDetector | 必需 | 失败时默认 active，但记录诊断日志 |
| FrontAppDetector | 必需 | appName 置为 `unknown`，窗口标题置空 |
| ScreenCapture | 必需 | 跳过本帧，不触发 AI |
| RegionDHash | 推荐 | 退化为时间兜底 + App/标题变化触发 |
| AttentionStateMachine | 推荐 | 默认 Observing，避免误打扰 |
| SCStream | 可选 | 共看模式退化为多帧单帧截图 |
| KeyframeExtractor | 可选 | 退化为固定间隔抽帧 |
| OCRTextRecognizer | 可选 | 忽略 OCR 文本，仅用视觉帧和标题 |
| SystemAudioCapture | 可选 | 共看模式退化为无音频 |
| WhisperTranscriber | 可选 | 忽略音频转写，仅用视觉 + OCR |
| WebMetadataSearch | 可选 | 不联网，仅基于本地上下文互动 |

降级原则：

```text
必需模块失败 → 本帧跳过或使用安全默认值
推荐模块失败 → 降级到更简单的触发策略
可选模块失败 → 忽略该信号，不阻塞主流程
```

## 21. 诊断日志与可观测性

感知层有**两条观测通道**（详见 architecture-harness-design.md §3.1）：

1. **诊断事件**（`perception.jsonl`）：每次 tick 的结构化决策记录，可被 ReplayRunner 回放。本节主题。
2. **运行日志**（`app.log`）：开发期自由文本调试日志，分级（debug/info/warning/error），通过 `Logging` 协议写入。用于排错、观察执行流水。

两者共用同一个 `traceId`，可交叉对应：grep 同一 traceId 既能看到该 tick 的决策事件，也能看到这一路的日志行。运行日志的写入门面、格式、落盘、降级要求统一遵循 architecture-harness-design.md §3.1，本文档不再重复。

诊断事件建议记录 JSONL：

```json
{
  "ts": "2026-06-20T10:00:00Z",
  "mode": "normal | coWatching | lowPower | paused",
  "decision": "analyze | skip_idle | skip_stable | skip_busy | paused_screen_locked",
  "appName": "Safari",
  "windowTitles": ["..."],
  "idleDuration": 3.2,
  "recentInputActive": true,
  "attentionState": "busy | observing | engaged",
  "regionHash": {
    "globalDistance": 18,
    "changedRegions": ["bottomRight"]
  },
  "featureFlags": {
    "coWatchingStream": false,
    "ocrRecognition": true,
    "systemAudioCapture": false
  },
  "latencyMs": {
    "capture": 12,
    "hash": 1,
    "ocr": 34,
    "whisper": 0
  },
  "fallbacks": ["ocr_failed"]
}
```

重点观测项：

```text
1. 本帧为什么触发分析
2. 本帧为什么跳过
3. 是否进入/退出共看模式
4. 是否触发降级
5. 截图/OCR/Whisper/VLM 各环节耗时
6. 电池/低电量策略是否生效
7. 桌宠是否处于 Busy 态而抑制互动
```

## 22. 模式隔离

普通模式、共看模式、省电模式、暂停模式必须使用独立 Profile，避免高成本能力在错误场景中被打开。

```swift
enum PerceptionMode {
    case normal       // 普通陪伴/赋能
    case coWatching   // 实时共看
    case lowPower     // 省电
    case paused       // 锁屏/熄屏/睡眠
}

struct PerceptionProfile {
    let tickInterval: TimeInterval
    let minAIInterval: TimeInterval
    let useSingleFrameCapture: Bool
    let useStreamCapture: Bool
    let useOCR: Bool
    let useAudioCapture: Bool
    let useWhisper: Bool
    let useWebSearch: Bool
}
```

建议默认 Profile：

| 模式 | tick | AI 最小间隔 | 截图 | SCStream | OCR | 音频 | Whisper | 联网搜索 |
|---|---:|---:|---|---|---|---|---|---|
| normal | 3-5s | 10-30s | 开 | 关 | 按需 | 关 | 关 | 关 |
| coWatching | 流式 | 5-15s | 备用 | 开 | 开 | 开 | 开 | 按需 |
| lowPower | 10-15s | 60s | 开 | 关 | 关/按需 | 关 | 关 | 关 |
| paused | 停止 | - | 关 | 关 | 关 | 关 | 关 | 关 |

隔离原则：

```text
1. 普通模式不得默认开启音频、Whisper、SCStream
2. 共看模式必须有明确进入/退出条件（见第 2 节进入/退出滞回）
3. 低电量或高热状态下自动切 lowPower（见闸门链 Gate 0.5）
4. 锁屏/熄屏/睡眠时进入 paused，彻底停止采集
5. 用户可手动退出共看模式，回到 normal
6. 送 VLM 的图像统一经 ImageEncoder 降采样（imageMaxEdge / imageJPEGQuality，见第 28 节）
```

## 23. 文件清单

```text
Perception/
├── PerceptionScheduler.swift       # tick调度 + latest-only防堆积
├── PerceptionFeatureFlags.swift    # 能力开关
├── PerceptionProfile.swift         # 模式 Profile / 能力组合
├── PerceptionDiagnostics.swift     # 诊断事件（perception.jsonl）
├── Logging.swift                   # Logging 协议 + LogLevel
├── FileLogger.swift                # 运行日志 real impl（异步写 app.log）
├── ScreenStateMonitor.swift        # 锁屏/熄屏/睡眠监听
├── GateChain.swift                 # 闸门链编排
├── ScreenCapture.swift             # ScreenCaptureKit 单帧截图
├── ScreenStreamCapture.swift       # SCStream 共看模式屏幕流
├── FrontAppDetector.swift          # NSWorkspace + CGWindowList
├── IdleDetector.swift              # CGEventSource 封装
├── InputActivityWindow.swift       # 30s 输入活跃窗口
├── RegionDHashComputer.swift       # 区域 dHash
├── KeyframeExtractor.swift         # 固定抽帧 + 变化量筛选
├── OCRTextRecognizer.swift         # Vision Framework OCR
├── SystemAudioCapture.swift        # ScreenCaptureKit 系统音频捕获
├── WhisperTranscriber.swift        # 本地 Whisper 转写
├── ContentTypeDetector.swift       # 内容类型识别
├── AttentionStateMachine.swift     # Busy / Observing / Engaged
├── ImageEncoder.swift              # 图片缩放 + JPEG 编码
├── ContextSnapshot.swift           # 普通模式输出
└── CoWatchingSnapshot.swift        # 共看模式输出
```

## 24. 数据边界与去向

屏幕监视类产品最核心的隐私承诺是「数据去哪了」。本节明确各类感知数据的边界。

### MVP 阶段（当前）

```text
截图 / 关键帧 → 仅送本地 VLM，不出设备
OCR 文本 / 音频 transcript → 仅本地使用，不出设备
idle 时长 / 输入活跃度 / 前台 App / 窗口标题 → 永不离开设备
```

- MVP 阶段所有视觉、音频、文本理解均在**本地**完成，截图不上传任何云端。
- 联网搜索（第 16 节）仅在用户开启 `webMetadataSearch` 时启用，且**只发送文本元信息**（片名/比分/标题等关键词），**绝不发送原始截图、关键帧或完整 OCR/transcript**。

### 后续阶段（云端接入，暂不实现）

当后续接入云端 VLM 时，必须满足：

```text
1. 上云前先经过 Gate 1.5 / Gate 6 隐私过滤
2. 上云前先降采样（长边 1536px、JPEG 0.6），不传原始分辨率
3. 必须有独立 Feature Flag 且默认关闭
4. 必须在 UI 中明确告知用户「截图将上传至云端分析」
5. idle / 输入活跃度 / 原始音频 buffer 始终不上云
```

### 不变量

```text
- 原始音频 buffer 永不离开设备（仅本地 Whisper 转写后的文本参与后续）
- 任何敏感窗口（Gate 1.5 黑名单）内容永不进入任何外送链路
- 默认本地优先；任何外送能力都必须可一键关闭
```

## 25. 权限与系统要求

### 系统要求

```text
最低系统版本：macOS 14（SCScreenshotManager.captureImage 要求）
SCStream 系统音频捕获：macOS 13+
```

### TCC 权限

| 能力 | 所需权限 | 说明 |
|---|---|---|
| 单帧截图 / SCStream | 屏幕录制（Screen Recording） | 首次使用触发系统授权弹窗；App 更新后可能需重新授权 |
| 系统音频捕获 | 屏幕录制 | ScreenCaptureKit 音频随屏幕录制权限 |
| idle 检测 | 无 | CGEventSource 不需要额外权限 |
| 前台 App / 窗口标题 | 无（部分窗口标题可能受限） | NSWorkspace / CGWindowList |

### onboarding 与降级

```text
1. 首次启动引导用户授予「屏幕录制」权限，说明用途
2. 权限被拒：
   - 禁用截图 / SCStream / OCR / 音频相关能力
   - 退化为「仅基于前台 App、窗口标题、idle、输入活跃度」的轻感知
   - 在 UI 提示用户去系统设置开启，不反复弹窗打扰
3. 权限被撤销（运行中）：检测到捕获失败 → 走 ScreenCapture 降级路径（跳过本帧），并提示用户
```

## 26. VLM / AI 调用预算

避免单次调用卡死拖垮后续，以及控制资源占用：

```text
1. 单次 VLM 调用超时 vlmTimeout(20s) 后取消，不无限等待
2. 普通模式每小时调用上限 vlmMaxPerHour(120)，超出则仅靠兜底刷新
3. 调用失败不自动重试，仅记录诊断事件（errors + fallback）
4. Gate 2 已保证「上一帧未完成则 skip」，配合超时取消防止堆积
```

## 27. 生产快照保留策略

区别于开发 Harness 的诊断日志（保留 7 天），**生产模式**对用户数据从严：

```text
1. ContextSnapshot / CoWatchingSnapshot 仅驻内存，用完即弃
2. 截图 / 关键帧默认不落盘
3. 仅在用户显式开启「诊断模式」时，才按 Harness 规则落盘并自动清理
4. 提供「清除全部本地感知数据」一键入口
```

## 28. 默认参数表

所有可调旋钮集中于此，便于调参与统一注入。Profile（第 22 节）与各模块从此表读取常量，不在各处写死。

| 参数 | 默认值 | 范围 | 说明 |
|---|---|---|---|
| tickInterval (normal) | 4s | 3–5s | 普通模式调度心跳 |
| minAIInterval (normal) | 15s | 10–30s | 两次 AI 分析最小间隔 |
| minAIInterval (coWatching) | 10s | 5–15s | 共看模式关键帧/AI 分析最小间隔 |
| tickInterval (lowPower) | 12s | 10–15s | 省电模式调度心跳 |
| minAIInterval (lowPower) | 60s | — | 省电模式两次 AI 分析最小间隔 |
| forceRefreshInterval | 120s | 60–300s | 无信号时的兜底强制刷新 |
| idleThreshold | 60s | — | 超过判 idle，普通模式不截图 |
| inputActiveWindow | 30s | — | 输入活跃滑动窗口 |
| instantInputThreshold | 5s | — | 单次「刚输入过」判定 |
| dHashGlobal | 10 | 6–14 | 64 位 dHash 全局触发阈值 |
| dHashRegion | 8 | 5–12 | 64 位 dHash 区域触发阈值 |
| coWatchEnterSustain | 5s | — | 进入共看需持续的时长 |
| coWatchExitSustain | 10s | — | 退出共看需持续的时长（滞回） |
| engagedTimeout | 30s | — | Engaged 无交互后回落 Observing |
| thermalTrigger | .serious | — | 切 lowPower 的热状态阈值 |
| batteryTrigger | <20% 且未充电 | — | 切 lowPower 的电量阈值 |
| vlmTimeout | 20s | — | 单次 VLM 调用超时取消 |
| vlmMaxPerHour | 120 | — | 普通模式每小时 AI 调用上限 |
| imageMaxEdge | 1536px | 1024–1568 | 送 VLM 前缩放长边 |
| imageJPEGQuality | 0.6 | 0.5–0.7 | 送 VLM 前 JPEG 压缩质量 |

以上为初始默认值，需在真机用典型场景（打字、阅读、看球、看电影）实测后微调。
