# Windows 桌面精灵架构设计

> 原则：离线优先、主链路无 AI 依赖、系统能力隔离、可诊断、可降级、一次只实现一个 TODO。

## 1. 技术栈

### 1.1 MVP 选型

- 语言/运行时：C# 13、.NET 9（实现时锁定具体 SDK patch，并提交 `global.json`）。
- UI：WPF。原因是 Windows 桌面透明窗口、托盘、命中测试和成熟工具链更适合快速建立首个桌宠闭环。
- 架构：单进程、分层模块化，不引入微服务或进程间通信。
- MVVM：优先使用 .NET 自带通知机制；首个骨架不强制引入第三方 MVVM 框架。
- 配置：`System.Text.Json`，写入 `%LocalAppData%/AI Spirit/settings.json`。
- 日志：通过 `ILoggingService` 输出结构化 JSONL 到本地应用数据目录；业务层不得直接写文件或调用 `Console.WriteLine`。
- 测试：xUnit；核心服务单元测试 + 窗口/状态集成测试；UI 自动化可在 MVP 主流程稳定后加入。
- 资源：画师交付透明序列帧与预览图；最终 PNG/WebP 等运行时格式在 W-001 锁定。渲染层必须封装格式，业务层只认识角色包和动画状态。

首个 MVP 不使用 Electron、WebView、数据库、云服务和 AI SDK。

## 2. 目录结构

```text
window/
├─ PRD.md
├─ DESIGN.md
├─ ARCHITECTURE.md
├─ HARNESS.md
├─ TODO.md
├─ global.json
├─ AIspirit.Windows.sln
├─ src/
│  ├─ AIspirit.App/                 # WPF 入口、DI composition root、窗口
│  │  ├─ Windows/
│  │  ├─ ViewModels/
│  │  └─ App.xaml
│  ├─ AIspirit.Domain/              # 纯状态、值对象、规则；不引用 WPF/IO
│  ├─ AIspirit.Application/         # 用例编排、接口定义、状态机
│  ├─ AIspirit.Infrastructure/      # 设置、日志、单实例、系统托盘等实现
│  ├─ AIspirit.Presentation/        # 可复用控件、主题、动画与资源渲染
│  └─ AIspirit.Diagnostics/         # 安全诊断信封与接口，不含 Debug UI
├─ tests/
│  ├─ AIspirit.Domain.Tests/
│  ├─ AIspirit.Application.Tests/
│  └─ AIspirit.Integration.Tests/
├─ assets/
│  ├─ spirits/default/
│  └─ spirits/alternate/
└─ scripts/
   ├─ check-boundaries.ps1
   └─ smoke-test.ps1
```

依赖方向：`App → Presentation/Application/Infrastructure`，`Infrastructure → Application/Domain`，`Presentation → Application/Domain`，`Application → Domain`。Domain 不得反向引用任何外层。

## 3. 数据模型

```csharp
public sealed record AppSettings(
    int SchemaVersion,
    string SelectedAppearanceId,
    WindowPlacement Placement,
    bool HasSeenOnboarding);

public sealed record WindowPlacement(
    double LeftDip,
    double TopDip,
    string? MonitorId,
    double SavedDpiScale);

public sealed record AppearanceManifest(
    string Id,
    string DisplayName,
    string ArtistName,
    string LicenseId,
    int SchemaVersion,
    string AssetRoot,
    CanvasSize CanvasSize,
    AnchorPoint Anchor,
    IReadOnlyDictionary<SpiritVisualState, AnimationDefinition> Animations);

public sealed record CanvasSize(int Width, int Height);
public sealed record AnchorPoint(double X, double Y);

public enum SpiritVisualState { Loading, Idle, Reacting, Dragging, Fallback }
public enum AppRuntimeState { Booting, Ready, Hidden, Degraded, Fatal }

public sealed record DiagnosticEvent(
    DateTimeOffset Timestamp,
    string Level,
    string EventName,
    string TraceId,
    IReadOnlyDictionary<string, string> SafeMetadata);
```

约束：

- 屏幕位置统一以 DIP 表示；仅系统边界适配器处理物理像素和 DPI 转换。
- 设置必须带 `SchemaVersion`；未知新版本不得覆盖原文件。
- 外观 ID 为稳定标识，业务逻辑不依赖资源文件名。
- manifest 必须包含作者/授权、schema、画布、锚点、预览图和动画定义；加载前校验路径、尺寸、帧率和必需状态。
- 角色包是不可变输入；运行时缓存和派生缩略图不得回写或覆盖画师源文件。
- 诊断元数据采用白名单，禁止记录用户内容和完整个人路径。

## 4. 服务层约定

所有跨边界能力必须具备接口、真实实现和测试替身：

| 接口 | 职责 | 真实实现 | 测试替身 |
|---|---|---|---|
| `ISettingsStore` | 读取/原子保存设置 | `JsonSettingsStore` | `InMemorySettingsStore` |
| `IAppearanceCatalog` | 枚举、校验外观 | `EmbeddedAppearanceCatalog` | `FakeAppearanceCatalog` |
| `ISpiritRenderer` | 切换视觉状态/外观 | `WpfSpiritRenderer` | `RecordingSpiritRenderer` |
| `IWindowPlacementService` | DPI/多屏校正 | `WindowsPlacementService` | `FakePlacementService` |
| `ITrayService` | 托盘入口 | `WindowsTrayService` | `FakeTrayService` |
| `ISingleInstanceService` | 单实例与激活 | `MutexSingleInstanceService` | `FakeSingleInstanceService` |
| `ILoggingService` | 安全结构化日志 | `JsonlLoggingService` | `InMemoryLoggingService` |
| `IClock` | 时间与动画/节流测试 | `SystemClock` | `FakeClock` |

服务规则：

- UI 只发送意图，`Application` 用例决定状态变化；View code-behind 仅允许窗口命中测试等 WPF 边界代码。
- IO、注册表、显示器、托盘、互斥锁等 Windows API 只能出现在 `Infrastructure` 指定适配器内。
- 所有可选服务失败必须返回明确结果或受控异常，并由用例层降级；不得让异常穿透 UI Dispatcher。
- 设置保存使用临时文件 + replace/move 的原子策略；损坏文件隔离后使用默认设置。
- 任何新能力先定义接口与 fake，再写真实实现。

### 4.1 动态角色资源管线

```text
画师透明源图 → 离线校验/转换 → 版本化角色包 → IAppearanceCatalog → ISpiritRenderer
```

- MVP 只加载随应用发布的受信任角色包；用户自行导入放在 P1，不能把任意资源文件当作可执行内容。
- `IAppearanceCatalog` 负责 manifest/schema/必需动画/文件哈希校验；`ISpiritRenderer` 只负责预加载、播放、切换与释放。
- 动画状态机由 Application 控制，渲染器不得自行决定业务状态；单次 `react` 完成后报告事件，由状态机回到 `idle`。
- 更换角色必须先完整预加载目标包的首帧和必需动画，成功后原子切换；失败时继续播放旧角色。
- 动画解码、缓存和播放不可阻塞 UI 线程；内存压力下可丢弃非当前角色缓存，但不得丢弃 fallback。
- P1 若支持画师包导入，必须增加签名/哈希、路径穿越、压缩炸弹、尺寸和帧数上限检查。

## 5. AI 引用机制

MVP 的 AI 能力为关闭且不存在运行时依赖。后续聊天、兴趣内容等 AI 能力接入必须遵循：

```text
UI / Use Case → IAIContentService → AIRouter → LocalAIProvider | CloudAIProvider
```

聊天模块另行通过 `IChatService` 暴露会话用例；`IChatService` 可组合 `IAIContentService`，但 UI 不得直接调用 `AIRouter` 或 Provider。聊天消息、会话历史和流式片段使用独立 DTO，不能复用桌宠气泡状态作为数据存储。

- 业务层只能依赖 `IAIContentService`，禁止直接引用模型 SDK。
- AI 功能必须由默认关闭的 Feature Flag 控制。
- 云端调用前必须有独立、可撤回的用户授权，并展示发送的数据类别。
- Prompt 使用版本化模板（`PromptId`、`Version`），禁止散落字符串拼接。
- 输入先经 `IPrivacyFilter`；输出为结构化 DTO，并做 schema 校验、长度限制和安全降级。
- Provider 必须支持超时、取消、限流、重试上限、成本预算和 mock/replay。
- AI 失败不影响精灵显示、拖动、隐藏、退出和本地番茄钟。
- 聊天必须支持取消生成；关闭聊天窗口不得终止桌宠主进程，模型失败时保留用户输入并允许重试。
- 会话历史默认策略必须在聊天模块 PRD 中明确；若持久化，必须支持查看、单条/全部删除和关闭保存。
- 默认不保存原始上下文；诊断日志只记录 provider、耗时、结果类型和错误码。

## 6. 开发约束

1. 每次开发前完整读取 `PRD.md`、`DESIGN.md`、`ARCHITECTURE.md` 和 `TODO.md`。
2. 严格按 `TODO.md` 顺序，一轮只把一个任务从 `[ ]` 变为 `[x]`；禁止顺手实现后续任务。
3. 开始一轮前必须明确：修改目标、允许修改范围、不允许破坏的逻辑、验收标准、时间预算。
4. 任务完成后运行对应单元测试、边界检查和构建；涉及用户模块时验证主流程、loading、empty、error 四态。
5. 新增跨边界能力必须同时提供 interface + real + fake/mock。
6. 新增可选或高隐私能力必须有默认关闭的 Feature Flag 与 fallback。
7. 禁止业务层直接调用 Windows API、文件系统、网络、AI SDK、日志文件。
8. 禁止测试项目被生产项目引用，禁止 Debug 工具进入 Release 主链路。
9. 禁止静默吞异常；允许降级，但必须记录安全诊断事件。
10. 用户已有修改不得被覆盖；结构性变更必须先更新架构文档和 TODO。
11. Harness DTO、Fixture、Replay、Feature Flags、Diagnostics、Debug Lab 和报告遵守 `HARNESS.md`；生产项目不得引用 TestKit 或 Harness Lab。

## 7. 禁止破坏的逻辑

- 精灵即使资源、设置或未来 AI 服务失败，也必须可显示默认形态、拖动、隐藏和退出。
- 正常状态下精灵必须是动态的；只有减少动态效果或资源降级时才允许使用静态形态。
- 更换形象必须是原子操作：新角色未验证并预加载成功前，不得卸载当前角色。
- 隐藏精灵后托盘必须仍能恢复；退出必须真正终止进程。
- 精灵位置不得保存成不可恢复的屏外坐标；显示器变化后必须校正。
- 应用不得抢占用户键盘焦点，不得阻塞桌面操作，不得覆盖系统安全界面。
- 无授权不得读取或发送屏幕、输入、剪贴板、音频、文件和浏览记录。
- 本地设置向后迁移前必须保留可恢复副本；不得因 schema 变化丢失用户选择。
- 主链路不得依赖网络、账号、AI 或第三方在线资源。

## 8. 验收标准

### 8.1 工程

- `dotnet restore`、`dotnet build -c Release`、`dotnet test -c Release` 全部通过。
- `scripts/check-boundaries.ps1` 无违规依赖或直接系统 API 调用。
- Release 产物在断网环境启动并完成完整主流程。
- 日志中无屏幕内容、输入内容、用户名和完整个人路径。

### 8.2 架构

- Domain 可独立测试且不引用 WPF、Windows API、文件或网络包。
- 每个外部边界均有真实实现与 fake/mock，核心用例测试不依赖真实桌面环境。
- 启动编排对设置损坏和资源缺失有可测试降级路径。
- 状态迁移可诊断，测试可断言最终状态和关键事件。
- `run-harness.ps1` 可确定性回放 MVP 主链路和四态，Release 不包含 Harness 调试能力。

### 8.3 产品闭环

- 启动 → 点击回应 → 拖动 → 换装 → 隐藏/恢复 → 退出 → 再启动恢复状态全链路通过。
- loading、appearance empty、settings/resource error、degraded 四态均能稳定复现并符合 `DESIGN.md`。
- 性能、DPI、多屏和辅助动效标准满足 `PRD.md` 与 `DESIGN.md`。
