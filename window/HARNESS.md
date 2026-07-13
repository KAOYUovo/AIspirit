# Windows 桌面精灵 Harness 设计

> Harness 是开发与验收底座，不是用户功能。它用确定性的 Fake、Fixture 和 Replay 复现桌宠行为，使核心逻辑无需真实显示器、托盘、文件故障或画师资源异常也能被验证。

## 1. 目标与非目标

### 1.1 目标

- 一条命令回放 MVP 主链路及 loading、empty、error、degraded。
- 所有 Windows/IO/动画边界可注入 Fake，并能断言调用顺序和最终状态。
- 核心状态变化产生统一诊断信封，支持按 `traceId` 还原链路。
- Debug Lab 可选择场景、Feature Flags、单步/连续回放并查看事件时间线。
- 每轮任务生成 Harness Compliance Report，避免跨层调用和无降级实现。

### 1.2 非目标

- 不模拟完整 Windows 桌面或替代最终真机验收。
- 不在生产环境收集用户交互回放。
- 不把 Debug Lab、Fixture 写入器或故障注入入口编入 Release 用户功能。
- 不为 MVP 引入云端测试平台、分布式追踪或截图识别服务。

## 2. 工程位置与隔离

```text
window/
├─ src/
│  └─ AIspirit.Diagnostics/          # 生产可用的安全诊断接口/信封；无 Debug UI
├─ tests/
│  ├─ AIspirit.TestKit/              # Fake、Fixture builder、Recording adapters
│  ├─ AIspirit.Replay.Tests/         # JSONL 回放与期望断言
│  └─ fixtures/mvp/                  # 版本化场景
├─ tools/
│  └─ AIspirit.HarnessLab/           # 仅 Debug 的场景实验室
└─ scripts/
   ├─ run-harness.ps1
   └─ check-boundaries.ps1
```

生产项目不得引用 `AIspirit.TestKit`、`AIspirit.Replay.Tests` 或 `AIspirit.HarnessLab`。Harness 通过与生产相同的 Application 接口驱动业务，不复制一套状态机。

## 3. Harness DTO

```csharp
public sealed record HarnessScenario(
    int SchemaVersion,
    string Id,
    HarnessInitialState Initial,
    IReadOnlyList<HarnessStep> Steps,
    HarnessExpectation Expected);

public sealed record HarnessStep(
    long AtMilliseconds,
    string Action,
    IReadOnlyDictionary<string, string> Payload,
    InjectedFailure? Failure);

public sealed record DiagnosticEnvelope(
    DateTimeOffset Timestamp,
    string TraceId,
    string SpanId,
    string? ParentSpanId,
    string Module,
    string EventName,
    IReadOnlyDictionary<string, string> SafePayload);

public sealed record ReplayResult(
    string ScenarioId,
    bool Passed,
    IReadOnlyList<ReplayMismatch> Mismatches,
    IReadOnlyList<DiagnosticEnvelope> Events);
```

规则：schema 必须版本化；未知 action、字段或新 schema 明确失败，不能静默忽略。Fixture 不包含真实用户名、个人路径或画师未授权源文件。

## 4. Seam 与 Fake

Harness 覆盖以下边界：

| Seam | Fake 行为 |
|---|---|
| `ISettingsStore` | 正常、空、损坏、版本不兼容、读取/保存失败 |
| `IAppearanceCatalog` | 两套角色、空目录、manifest 错、缺帧、授权缺失 |
| `ISpiritRenderer` | 记录预加载/播放/切换/释放；注入解码和动画完成事件 |
| `IWindowPlacementService` | 单屏、多屏、DPI、屏幕移除、屏外坐标 |
| `ITrayService` | 显示、隐藏、退出、初始化失败 |
| `ISingleInstanceService` | 首实例、已有实例、锁异常 |
| `ILoggingService` | 内存收集、写入失败且不影响主链路 |
| `IClock` | 虚拟时间、动画超时、节流保存，无真实等待 |

每个 Fake 默认行为必须成功；故障只能由场景显式注入。Recording Fake 应保存结构化调用记录，不用字符串日志作为主要断言。

## 5. Feature Flags

MVP Harness Flags：

- `harnessEnabled`：仅测试和 Debug Lab 可开启；Release 固定为 false。
- `diagnosticsEnabled`：测试默认开启，生产默认开启安全最小集。
- `animatedSpiritEnabled`：验证动态关闭时的静态降级。
- `appearanceSwitchingEnabled`：隔离换形象链路。
- `failureInjectionEnabled`：仅测试构建可开启。

Flag 必须经统一 `IFeatureFlags` 注入，禁止通过散落环境变量或 UI 静态字段读取。

## 6. Fixture 与 Replay

### 6.1 MVP 必备场景

1. `happy-path`：启动 → idle → 点击 react → 拖动 → 换角色 → 隐藏 → 恢复 → 退出。
2. `loading-slow-assets`：虚拟延迟后由 loading 进入 ready。
3. `appearance-empty`：空目录进入 empty，可恢复内置角色。
4. `settings-corrupt`：损坏设置被隔离，默认位置启动并进入 degraded/ready。
5. `appearance-preload-failed`：目标角色失败，旧角色继续播放。
6. `display-removed`：已保存显示器不存在，位置回到主屏安全区。
7. `save-failed`：保存失败提示一次，当前会话继续运行。
8. `renderer-fallback`：动画解码失败，静态 fallback 仍可拖动、隐藏和退出。

### 6.2 Replay 语义

- 使用 `IClock` 虚拟时间，回放不得依赖 `Task.Delay` 的真实等待。
- 每一步断言运行时状态、可见角色、窗口位置、服务调用和关键诊断事件。
- Replay 结果必须区分：状态不匹配、缺失事件、多余副作用、超时和隐私字段违规。
- Fixture 期望只声明稳定业务结果，不绑定 WPF 控件树或内部私有方法。

## 7. Diagnostics

- 每次启动、状态迁移、角色预加载/切换、位置校正、隐藏/恢复、fallback 和退出均产生 `DiagnosticEnvelope`。
- 同一用户动作共享 `traceId`；跨服务调用使用 `parentSpanId` 建立链路。
- payload 使用字段白名单，不记录用户输入、完整路径、屏幕内容和资源二进制。
- 日志写入失败不能中断主流程；测试必须能断言对应 fallback。

## 8. Debug Harness Lab

仅 Debug 构建提供：

- 场景选择与重新加载。
- Feature Flags 面板。
- Run、Pause、Step、Reset。
- 当前 App/Spirit 状态、角色 ID、窗口位置。
- 服务调用记录、诊断时间线和 Replay mismatch。
- 主流程、loading、empty、error、degraded 快捷场景。

Lab 只能调用 Harness Runner 和应用接口，不直接调用 Windows API。Release 构建不得包含入口、菜单或故障注入能力。

## 9. 边界检查

`check-boundaries.ps1` 至少检查：

1. Domain 不引用 WPF、Windows Forms、文件系统、网络和 AI SDK。
2. Application 不直接调用 Windows API、文件写入或具体 Renderer。
3. 生产项目不引用 TestKit、Replay Tests 或 Harness Lab。
4. Debug Lab/Fake/Fixture/FailureInjection 不进入 Release 发布目录。
5. 业务代码不直接使用 `Console.WriteLine`、`File.*` 或散落 Feature Flag。
6. 日志 payload 不出现禁止字段名。

## 10. Harness Compliance Report

每个实现任务完成后输出：

```text
Harness Compliance Report
- Task:
- Interface + real + fake complete: yes/no/n.a.
- Feature Flag added/used: yes/no/n.a.
- Diagnostics recorded: yes/no/n.a.
- Fixture added/updated: yes/no/n.a.
- Replay passed: yes/no/n.a.
- Fallback verified: yes/no/n.a.
- Main/loading/empty/error verified: ...
- Forbidden dependency usage: none/details
- Release excludes Harness Lab/TestKit: yes/no
- Tests/build/boundary commands:
```

`n.a.` 必须说明理由。报告出现 seam 缺 Fake、错误无 fallback、决策无诊断、生产引用 Harness 或边界脚本失败时，任务不得勾选。

## 11. Harness 验收标准

- `run-harness.ps1` 一条命令运行全部八个 MVP fixture，并以非零退出码报告失败。
- 同一 fixture 重复运行得到相同状态、事件顺序和结果。
- 无真实显示器切换、托盘、用户设置目录和画师源文件也能运行核心 Replay。
- happy path 与四态场景均有明确断言，无无限 loading。
- 任一可选边界失败时主链路按设计降级，且事件时间线能说明原因。
- Release 构建不包含 Debug Lab、Fixture、Fake 和故障注入入口。
