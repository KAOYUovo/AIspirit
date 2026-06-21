# AGENTS.md — AI 桌宠项目 Codex 工作规则

> Codex 在本工程的每次任务前都会自动读取本文件。以下为**常驻约束**，无需在每次 prompt 里重复。
> 每次任务你只需告诉我「实现哪个模块/功能」，其余约束按本文件执行。

## 0. 开工前必读文档（按优先级）

1. `architecture-harness-design.md` —— 项目级 harness 脊柱与约定，**最高优先级**。
2. 当前模块对应的 harness 实例文档：
   - Perception → `perception-harness-design.md` + `perception-final.md`
   - 其他模块 → `architecture-harness-design.md` §9 对应占位小节
3. 涉及架构全貌时参考 `architecture-full.md`。

设计文档与 harness 文档（perception-final / perception-harness / architecture-harness）口径已对齐，不要单独偏离任何一份。

## 0.5 技术选型评审（新模块的第一步）

开始任何新模块前，若该模块**还没有**敲定的 `<module>-final.md` 设计文档（对标
`perception-final.md`），**第一步是技术选型评审，不写代码、不写 harness**：

```text
1. 从 architecture-full.md 对该模块的描述出发，拆出该层的关键功能点 / 决策点。
2. 每个功能点给 2–3 个候选方案，逐个列出：实现方式 / 优点 / 缺点 / 适用场景。
3. 给出带理由的推荐（标注「推荐」），但明确「最终由我抉择」。
4. 用提问方式让我逐点拍板（一次问清，不要替我默认决定）。
5. 把我的决策固化成 `<module>-final.md`，体例对标 perception-final.md：
   每节「选型 X + 理由」，并补默认参数表。
```

这份 `<module>-final.md` 才是后续 §1.1 扩写 harness、§1 拆 Task 的**设计主来源**。
未经此步、未经我抉择，不得直接进入 harness 扩写或编码。

注意：Perception 已有 `perception-final.md`（已走完此流程），可直接进入实现。
其余模块（Local Agent / Pet Engine / Cloud Agent / Go 服务）均需先走 §0.5。

## 1. 一次只做一个模块，模块内一次只做一个 Task

- 严格按 `architecture-harness-design.md` §2.3 的依赖顺序推进：
  Perception → Local Agent → Pet Engine →（P0 完）→ RemoteProxy+Cloud Agent → Go 服务。
- **不要**因为"看起来能一次做完"就把下游模块一起实现。脊柱的价值就是逐模块验收。
- **一个模块不要一次性实现**：模块开工第一步，Codex 先生成该模块的 Task 列表——
  - **以设计文档为主来源**拆功能实现 Task（Perception 见 `perception-final.md`，
    含 §23 文件清单与各节技术方案；其他模块见其设计文档）。
  - harness 文档提供**约束**与**脚手架顺序**：先建少量脚手架（DTO / Diagnostics / Mock，
    使后续能 test-first），再按设计文档逐个功能推进。`perception-harness-design.md` §14
    是 harness 脚手架的拆分参考，**不是完整功能 Task 清单**。
  - 每个 Task 要小到"一轮能验收"，且尽量自带其 fixture / 边界检查。
  - Task 列表**经我确认后写入 §6 进度表**，之后按表逐 Task 推进；不要每轮重拆。
- 确认后**一个 Task 一轮**，跑完该 Task 的测试/fixture 验收后再开下一个 Task。
- 若该模块的 harness 还是占位（§9.x），先把占位扩成该模块 harness 设计，**经我确认后**再拆 Task。
  扩写时按 §1.1 的「模块 harness 扩写清单」产出。

## 1.1 模块 harness 扩写清单

当一个模块的 harness 还是脊柱 §9.x 占位时，开工第一步是把它扩成一份完整的
`<module>-harness-design.md`。**前置条件：该层已有 `<module>-final.md`（即已走完 §0.5
技术选型评审）；若没有，先回到 §0.5。不要从零发明**——继承脊柱的通用约定，只新写本层特有部分。
Codex 起草时必须逐项覆盖以下清单，并把它当作该文档的章节骨架：

```text
A. 忠于设计：本层职责须符合 architecture-full.md 对该模块的定义（如 Local Agent 见 §4.1），
   不得自由发挥；偏离设计必须先说明并经我确认。
B. 继承脊柱（不重写，引用即可）：
   - 诊断信封（脊柱 §3）——只定义本层 payload 字段
   - traceId / span 透传（脊柱 §4）——明确如何接上游 parentSpanId
   - 运行日志 Logging（脊柱 §3.1）
   - 合规模板 DoD（脊柱 §7）
C. 本层 seam 清单：列出该模块所有跨边界处，每个给 protocol + real + mock
   （遵守脊柱 §5 铁律），并登记到脊柱 §5 的 seam 表。
D. 本层 Feature Flags：新增能力的 flag（脊柱 §6）。
E. 该测什么：核心决策/状态机的测试点；易跑偏模块标注「先测后写」。
F. Fixture / 回放：本层关键行为的回归场景，能被回放验证。
G. 降级策略：可选子模块失败时的 fallback。
H. 边界脚本：本层需要新增的禁止项（如禁止直接调用某 SDK）。
```

确认后回填两处：
1. AGENTS.md §6 进度表对应行（标注新 harness 文档名、补 Task 子行）。
2. 脊柱 §9.x 占位小节，改为指向新文档。

## 2. 先计划，后实现

- 收到任务后**先不要写代码**，先给出：文件清单 + Task 拆分 + 打算先写哪些测试/fixture。
- 等我确认计划后再动手。
- 每轮只实现进度表里**当前那一个 Task**，不要提前做后续 Task。
- 对 GateChain / AttentionStateMachine / FeatureFlags / ReplayRunner / Fallback 等易跑偏模块，
  按"先写测试和 fixture、确认后再写实现"两步走。

## 3. 硬约束（违反视为架构违规，不是风格问题）

1. **Seam 铁律**：任何跨边界处（系统 API / 网络 / LLM / DB / 进程间）必须
   `protocol + real impl + mock impl` 三件套齐全。业务逻辑只依赖 protocol。
2. **系统 API 隔离**：ScreenCaptureKit / CGEventSource / NSWorkspace / Vision / Whisper
   只允许出现在指定 Collector 文件中（见 `perception-harness-design.md` §11.2）。
   日志同理：业务代码不得直接 `print` / `NSLog` / 写文件，只能用 `Logging` 协议（见脊柱 §3.1）。
   Python 侧：LLM 只走 ModelRouter、工具只走 ToolRegistry、DB 只走 MemoryService。
3. **可观测**：每次核心决策必须产出共享诊断信封事件，带
   `traceId / spanId / parentSpanId / module`（格式见脊柱 §3、§4）；
   执行流水用 `Logging` 写运行日志（`app.log`），与诊断事件共用同一 traceId（见脊柱 §3.1）。
   P0 单进程内也要按此格式生成 traceId，便于 P1 跨进程拼链路。
4. **Feature Flag**：新能力必须登记 FeatureFlag；隐私/高成本能力默认关闭。
5. **降级**：可选模块失败必须 fallback，不阻塞主链路。
6. **隔离**：DebugTools / 测试替身不得被生产代码 import。
7. **参数不写死**：关键阈值从对应模块的默认参数表读取（如 Perception 见
   `perception-final.md` §28），通过依赖注入，不在各处硬编码。

## 4. 交付前必做

- 跑通单元测试 + 该模块所有 replay fixture。
- 运行对应边界检查脚本（如 `Scripts/check_perception_boundaries.sh`）。
- 按 `architecture-harness-design.md` §7.5 输出 **Harness Compliance Report**。
- 清理实现过程中产生的临时文件。

## 5. 验收抓手

我会以 Compliance Report 为准验收。若报告出现"某 seam 缺 mock"/"直接调用了系统 API/SDK/DB"
/"决策未记录诊断"等项，本次实现会被打回重做，不予放行。

## 6. 模块进度

每完成并验收一个 Task / 模块就更新本表（状态：⬜ 未开始 / 🔨 进行中 / ✅ 已验收）。
开工前先看这里确认「现在该做哪个」。

模块开工时，Codex 先依 §1 规则（**以设计文档为主来源**、harness 提供约束与脚手架顺序）
生成 Task 列表，经我确认后在该模块行下补出 Task 子行，再逐 Task 推进。
不必预先给所有模块都画满子行——用到时再拆。

| 顺序 | 模块 / Task | 阶段 | 状态 | 备注 |
|---|---|---|---|---|
| 1 | **Perception** | P0 | ✅ | P0 感知层已完成；全量测试、replay、boundary、Debug/Release PerceptionLabApp build、Live Tick 已通过 |
|   | └ P-00 最小 Swift Package / 目录骨架 / 测试 target / 进度表登记 | P0 | ✅ | `swift test` 已通过；无业务实现 |
|   | └ P-01 基础 DTO + FeatureFlags + 默认参数/Profile | P0 | ✅ | `swift test` 已通过；Codable round-trip；默认值对齐 perception-final.md §19/§28 |
|   | └ P-02 Logging seam | P0 | ✅ | `swift test` 已通过；Logging/FileLogger/InMemoryLogger；未发现业务 `print`/`NSLog` |
|   | └ P-03 Diagnostics + JSONLWriter | P0 | ✅ | `swift test` 已通过；诊断信封含 traceId/spanId；JSONL 一行一事件 |
|   | └ P-04 Mock/Fixture 基础 | P0 | ✅ | `swift test` 已通过；ReplayScenario、FixtureLoader/Writer、MockScenarioFactory |
|   | └ P-05 ReplayRunner 最小闭环 | P0 | ✅ | `swift test` 已通过；统计 analyze/skip/fallback；支持 override flags |
|   | └ P-06 Boundary Script + SwiftLint 规则 | P0 | ✅ | `swift test` + boundary 已通过；禁止直接系统 API；禁止生产 Perception import DebugTools |
|   | └ P-07 Collector protocols + mocks | P0 | ✅ | `swift test` + boundary 已通过；Idle/FrontApp/ScreenCapture/ScreenStream/ScreenState/Power/OCR/Audio/Whisper/WebMetadata seam |
|   | └ P-App-00 最小 macOS PerceptionLab 调试应用 | P0 | ✅ | `swift build --product PerceptionLabApp` 已通过；SwiftUI App；mock scenario / replay / flags / decision / PetAction 预览 |
|   | └ P-08 InputActivityWindow | P0 | ✅ | `swift test` + boundary 已通过；30s 近期输入活跃窗口；instantInputThreshold=5s |
|   | └ P-09 ScreenStateMonitor Gate 0 | P0 | ✅ | `swift test` + boundary + app build 已通过；锁屏/熄屏/睡眠 paused；失败退化继续 |
|   | └ P-10 Power/Thermal Gate 0.5 | P0 | ✅ | `swift test` + boundary + app build 已通过；低电量/高热/系统低电量模式切 lowPower |
|   | └ P-11 IdleDetector + Gate 1 | P0 | ✅ | `swift test` + boundary + app build 已通过；idle >60s skipIdle；失败默认 active 并输出 fallback error |
|   | └ P-12 FrontAppDetector + 隐私黑名单 Gate 1.5 | P0 | ✅ | `swift test` + boundary + app build 已通过；app/title 变化触发；黑名单捕获前阻断 |
|   | └ P-13 单帧 ScreenCapture + ImageEncoder | P0 | ✅ | `swift test` + boundary + app build 已通过；捕获失败跳过本帧；权限拒绝降级 |
|   | └ P-14 RegionDHashComputer | P0 | ✅ | `swift test` + boundary + app build 已通过；全局 + 3x3 区域 64 位 dHash；阈值注入 |
|   | └ P-15 GateChain 多信号融合 Gate 2-4 | P0 | ✅ | `swift test` + boundary + app build 已通过；纯逻辑 GateChain；覆盖 harness §13.1 |
|   | └ P-16 AttentionStateMachine + PetAction 抑制 | P0 | ✅ | `swift test` + boundary + app build 已通过；Busy/Observing/Engaged + engagedTimeout；Busy 抑制长气泡 |
|   | └ P-17 PerceptionScheduler + latest-only + VLM 预算 | P0 | ✅ | `swift test` + boundary + app build 已通过；AI busy skip；latest-only；vlmTimeout/vlmMaxPerHour |
|   | └ P-18 Co-watching 进入/退出状态机 | P0 | ✅ | `swift test` + boundary + app build 已通过；动态内容 + 大窗口/全屏 + 滞回 |
|   | └ P-19 SCStreamCapturer + stream fallback | P0 | ✅ | `swift test` + boundary + app build 已通过；flag=false 不启动；失败退化多帧单帧截图 |
|   | └ P-20 KeyframeExtractor | P0 | ✅ | `swift test` + boundary + app build 已通过；固定抽帧 + 变化量筛选 |
|   | └ P-21 OCRTextRecognizer | P0 | ✅ | `swift test` + boundary + app build 已通过；flag=false 不调用；失败忽略 OCR 文本 |
|   | └ P-22 SystemAudioCapture + WhisperTranscriber seams | P0 | ✅ | `swift test` + boundary + app build 已通过；audio/whisper 默认 false；失败不阻塞共看 |
|   | └ P-23 ContentTypeDetector | P0 | ✅ | `swift test` + boundary + app build 已通过；sports/office/coding/chat/unknown fixtures |
|   | └ P-24 隐私 Gate 6 + WebMetadataSearch seam | P0 | ✅ | `swift test` + boundary + app build 已通过；敏感 OCR/transcript 过滤；联网默认关闭 |
|   | └ P-25 ContextSnapshot / CoWatchingSnapshot 组装输出 | P0 | ✅ | `swift test`、边界检查、PerceptionLabApp build 已通过；Profile 隔离；普通模式不得误开高成本能力 |
|   | └ P-26 Debug UI / PerceptionLab | P0 | ✅ | `swift test`、boundary、Debug/Release PerceptionLabApp build 已通过；仅 DEBUG；flags、诊断、PetAction 预览 |
|   | └ P-27 全量 replay fixture 与模块最终验收 | P0 | ✅ | `swift test`、六个 replay fixture、JSONL round-trip、boundary、Debug/Release app build 已通过 |
|   | └ P-LIVE-00 macOS Live Perception Harness | P0 | ✅ | `swift test` + boundary + Debug/Release app build 已通过；Xcode 真机单帧 live tick 验收入口；real collectors + UI 展示 |
| 2 | **Local Agent** | P0 | ⬜ | harness 占位（脊柱 §9.1），开工前先扩写 harness + 依设计文档拆 Task |
| 3 | **Pet Engine** | P0 | ⬜ | harness 占位（脊柱 §9.2），开工前先扩写 harness + 依设计文档拆 Task |
| — | （P0 完成里程碑：全本地可独立运行） | | | |
| 4 | **RemoteProxy + Cloud Agent** | P1 | ⬜ | harness 占位（脊柱 §9.3），P0 阶段用 MockCloudAgent |
| 5 | **Go 服务 / 契约 / 追踪** | P1+ | ⬜ | harness 占位（脊柱 §9.4） |

规则：
- 同一时间只应有一个**模块**处于 🔨；上一个模块未 ✅ 不开下一个。
- 模块内同一时间只应有一个 **Task** 处于 🔨；上一个 Task 未 ✅ 不开下一个。
