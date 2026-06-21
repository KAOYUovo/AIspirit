# 项目级 Harness 设计文档（脊柱 + 模块索引）

> 配套文档：[architecture-full.md](architecture-full.md)（完整架构）、[perception-harness-design.md](perception-harness-design.md)（感知层 harness，本文档脊柱的第一个实例）、[perception-final.md](perception-final.md)（感知层技术方案）。

## 1. 目标与定位

本文档定义 AI 桌宠项目的 **项目级 Harness 脊柱与模块索引**，用于支持单人 + Codex 的 vibe coding，让每个模块都能被「可验证地约束」地实现。

它**不是**一份 day-1 必须全部实现的大 spec，而是：

1. **共享脊柱**：定义所有模块通用的诊断信封、traceId、seam 铁律、Feature Flag 登记、合规模板。这部分现在就定下来，很短，但被反复引用。
2. **模块索引**：一张活的清单，记录每个模块的 harness 在哪、处于什么状态。随实现进度回填。

与 perception-harness-design.md 的关系：后者是本脊柱的**第一个实例**——感知层的诊断/回放/Mock/合规规则，都是这里通用约定的具体化。后续每个模块（Local Agent、Pet Engine、Cloud Agent…）都是脊柱的又一个实例。

定位为**活文档**：每完成一个模块就回填第 8 节索引，并把对应占位小节（第 9 节）扩成完整设计。

---

## 2. 实施策略（核心）

### 2.1 总原则

不要一开始就用全量三语言 harness 约束 Codex——P0 阶段后端代码根本不存在，为不存在的层写 harness 只会产出会腐烂的 stub。也不要纯粹模块孤立——少数跨层共享的约定（尤其 traceId）现在定很便宜、事后补很贵。

正确节奏：**先抽一根很薄的脊柱（半天），然后严格按客户端依赖顺序逐模块实现，每模块自带 harness 实例并独立验收。**

### 2.2 步骤

```text
第 0 步（半天，只定约定，不写业务）：
    固化脊柱 = 诊断信封 + traceId 约定 + seam 铁律 + flag 登记 + 合规模板
    （即本文档第 3–7 节）

然后按客户端依赖顺序逐模块，每个模块一个闭环：
    写模块 harness 实例 → Codex 实现 → fixture/replay 验收 → 下一个
```

### 2.3 模块依赖顺序与阶段

```text
Perception            [P0] ← 已有 harness（perception-harness-design.md），脊柱首个实例
   ↓
Local Agent           [P0] RulesEngine + LocalLLM + ActionDispatcher
   ↓                       RemoteProxy 此阶段用 MockCloudAgent 顶替
Pet Engine            [P0] 动画状态机 / 气泡 / 交互
   ↓
──────── 以上为 P0：全本地，无后端，可独立验收 ────────
   ↓
RemoteProxy + Cloud Agent   [P1] 接真后端（Python Agent Service）
   ↓
Go 服务 / 契约测试 / 分布式追踪  [P1+] Gateway / User / Sync / Admin
```

P0 阶段 RemoteProxy 用 mock 顶替，正好对应「本地优先、无后端也能跑通整个客户端」（见非目标对照演进路线 architecture-full.md §11）。

### 2.4 每种方案对比（为什么选逐模块）

| 维度 | 逐模块 + 薄脊柱（本方案） | day-1 全量约束 |
|---|---|---|
| 每轮能否验收 | 能，每模块跑 fixture 即验收 | 不能，全建完才能验 |
| Codex 跑偏概率 | 低（spec 小且具体） | 高（spec 大且抽象） |
| 匹配 P0 路线 | 完全匹配（先客户端本地） | 大量为不存在的层写 harness |
| 事后返工风险 | 低（脊柱兜住跨层一致性） | 中高 |
| 首个可用产物时间 | 快 | 慢 |

---

## 3. 共享诊断信封（脊柱①）

所有模块的诊断事件共用同一个外壳，模块专属内容放进 `payload`。这样单进程的感知日志和未来跨进程的 Agent 日志同构，可被同一套工具读取、拼接、回放。

```text
通用信封字段（所有模块必填）：
  schemaVersion : Int        — 信封 schema 版本
  traceId       : String     — 贯穿一次完整交互的关联 id（见第 4 节）
  spanId        : String     — 本模块本次处理的局部 id
  parentSpanId  : String?    — 上游 span，用于拼链路
  module        : String     — "perception" | "localAgent" | "petEngine" | "cloudAgent" | ...
  timestamp     : Date
  decision      : String     — 本模块的核心决策结果（各模块自定义枚举）
  latencyMs     : Int?        — 本模块本次耗时
  featureFlags  : {..}        — 本次生效的相关 flag 快照
  errors        : [..]        — 错误（module/code/message/isFallbackApplied）
  fallbacks     : [String]    — 触发的降级
  payload       : {..}        — 模块专属数据
```

JSON 示例（一条 Local Agent 的升级决策事件）：

```json
{
  "schemaVersion": 1,
  "traceId": "trace-7f3a",
  "spanId": "span-localagent-0012",
  "parentSpanId": "span-perception-0128",
  "module": "localAgent",
  "timestamp": "2026-06-20T10:00:00Z",
  "decision": "escalateToCloud",
  "latencyMs": 240,
  "featureFlags": { "localLLM": true, "remoteEnabled": false },
  "errors": [],
  "fallbacks": [],
  "payload": {
    "reason": "user initiated deep conversation",
    "localConfidence": 0.42,
    "routedTo": "MockCloudAgent"
  }
}
```

要求：

- 各模块**不得**自创独立信封格式；只能扩展 `payload`。
- 感知层现有的 `PerceptionDiagnosticEvent`（perception-harness-design.md §5.2）视为本信封的 Perception 实例——其 GateDecision/snapshot 等内容归入 `payload`，并补齐 `traceId/spanId`。
- 信封必须 `Codable` / 可 JSON 序列化，每条事件一行 JSONL。

### 3.1 运行日志（Logger）vs 诊断事件

项目有**两条观测通道，用途不同，都要有**：

| 通道 | 形态 | 用途 | 落盘 |
|---|---|---|---|
| **诊断事件**（§3 信封） | 结构化 JSONL，每次决策一条 | 回放、统计、行为回归 | `*.jsonl` |
| **运行日志**（本节 Logger） | 自由文本、分级 | 开发期调试、排错、看执行流水 | `*.log` |

不要用诊断事件代替日志（决策点之外的执行细节它记不了），也不要用日志代替诊断（日志不可回放）。

#### Logging 门面（遵守 §5 seam 铁律）

```swift
enum LogLevel: Int, Codable, Sendable, Comparable {
    case debug, info, warning, error
}

protocol Logging: Sendable {
    func log(_ level: LogLevel,
             _ message: String,
             module: String,
             traceId: String?,
             metadata: [String: String])
}
```

- **real impl**：`FileLogger`（actor），异步写入滚动 `.log` 文件。
- **mock impl**：`InMemoryLogger`，测试中收集日志行供断言。
- 业务代码只依赖 `Logging`，不直接 `print` / 不直接写文件。

#### 日志行格式（人类可读且可 grep）

```text
2026-06-20T10:00:00.123Z [INFO ] [perception] [trace-7f3a] tick analyzed  region=bottomRight idle=2.1
2026-06-20T10:00:00.130Z [DEBUG] [localAgent] [trace-7f3a] escalate decision  confidence=0.42 routedTo=MockCloudAgent
```

- 固定前缀：`时间戳 [级别] [module] [traceId]`，其后为 message 与 `key=value` 元数据。
- **traceId 与诊断事件共用同一个值**——这样一次交互的日志行和诊断事件能对应起来（grep 同一 traceId 即可拼出执行流水 + 决策）。

#### 落盘位置（与诊断目录一致）

```text
Application Support/AIPet/Diagnostics/<yyyy-MM-dd>/app.log        # 运行日志
Application Support/AIPet/Diagnostics/perception/<yyyy-MM-dd>/perception.jsonl   # 诊断事件
```

#### 行为要求

```text
1. 异步、非阻塞：写日志失败只内部记错误计数，绝不抛给主流程（与 JSONLWriter 同原则）。
2. 分级可控：默认级别 Debug 构建=debug、Release 构建=warning；可由 Feature Flag / 配置调整。
3. 按日期滚动，自动清理（默认保留 7 天，与诊断日志一致）。
4. 生产模式默认不记录用户敏感内容（截图像素、OCR 文本、transcript 原文）——
   只记元信息（如「OCR 命中 3 段文本」而非文本本身）。
5. 导出诊断包（perception-harness §5.1）时一并打包 app.log。
```

---

## 4. traceId / 链路追踪约定（脊柱②）

traceId 现在（P0 单进程）用不到跨进程拼接，但**必须从第一天就带上**，否则 P1 接入 Cloud Agent 时无法把一次行为拼回完整链路，届时返工所有已落地的事件结构。

```text
生成时机：
  - 一次用户可感知的交互起点生成一个 traceId，例如：
    · 一次感知 tick（Perception 起点）
    · 一次用户主动输入 / 点击桌宠
  - traceId 在该交互的整条链路上保持不变

传播路径（同一 traceId，每跳新建 spanId，parentSpanId 指向上游）：
  Perception(tick)
    → Local Agent(决策)
    → RemoteProxy(打包)
    →〔P1+〕Gateway → Agent Service(Python) → Tools / Memory
    → 回传 → Pet Engine(执行)

P0 阶段：
  - 即使全程在客户端单进程内，也按上述格式生成 traceId / spanId / parentSpanId
  - MockCloudAgent 也要透传 traceId，模拟真实跨进程行为
```

原则：单进程日志与未来跨进程日志**结构同构**，工具无需区分阶段即可拼链路。

---

## 5. Seam 铁律：protocol + real + mock（脊柱③）

把感知层「每个系统 API 封装进 Collector」上升为全项目通用规则：

> **任何跨边界处都必须有 `protocol` + `real implementation` + `mock implementation`。**

跨边界处（seam）包括：系统 API、网络调用、LLM 调用、数据库、进程间通信。

全项目已知 seam 清单：

| Seam | protocol | real impl | mock impl | 阶段 |
|---|---|---|---|---|
| 系统 idle 检测 | IdleDetecting | CGEventSourceIdleDetector | MockIdleDetector | P0 ✅ |
| 前台 App | FrontAppDetecting | NSWorkspaceFrontAppDetector | MockFrontAppDetector | P0 ✅ |
| 屏幕截图 | ScreenCapturing | ScreenCaptureKitCapturer | MockScreenCapture | P0 ✅ |
| 屏幕流 | ScreenStreaming | SCStreamCapturer | MockScreenStream | P0 ✅ |
| 运行日志 | Logging | FileLogger | InMemoryLogger | P0 |
| 本地 LLM | LocalReasoning | LlamaCppReasoner | MockLocalLLM | P0 |
| 云端 Agent | CloudAgentCalling | RemoteProxyClient | **MockCloudAgent** | P0(mock)/P1(real) |
| LLM 调用(服务端) | LLMProviding | LiteLLMProvider | MockLLM / 录制回放 | P1 |
| 工具系统 | ToolInvoking | ToolRegistry | MockToolRegistry | P1 |
| 记忆/向量库 | MemoryStoring | PgvectorMemory | MockMemory | P1 |
| 网关 | — | Gin Gateway | MockGateway | P1 |
| 基础设施 | — | PG / Redis / S3 | sqlite / fakeredis / 本地fs | P1 |

要求：

- 业务逻辑只依赖 protocol，不直接 import real impl 或系统/网络 API。
- 新增 seam 必须三件套齐全，否则视为架构违规（非风格问题）。
- 标 ✅ 的已在感知层落地；其余在做到对应模块时建立，先占位。

---

## 6. Feature Flag 登记约定（脊柱④）

不强求现在建中心化 flag 系统，但**任何高成本/高风险/跨层能力都必须登记**，格式统一：

```text
flag 名（lowerCamelCase）
  层      : client | agentService | goService
  默认值  : true | false
  风险级别: core | experimental | privacy | cost
  说明    : 一句话
```

要求：

- 客户端与服务端不得各搞一套命名风格。
- 感知层的 `PerceptionFeatureFlags`（perception-harness-design.md §4.1）是本约定的客户端实例。
- 新增能力时同步登记，并在诊断信封 `featureFlags` 中体现。

---

## 7. 合规约束模板（脊柱⑤）

### 7.1 通用 Definition of Done

任何模块的改动必须满足（具体到模块时可加项）：

```text
1. 新能力有 FeatureFlag（除非 core 必需）。
2. 新跨边界调用封装在 seam（protocol + real + mock）中。
3. 核心决策记录共享诊断信封事件（含 traceId/spanId）。
4. 新触发/跳过/降级逻辑有单元测试或 replay fixture。
5. 可选模块失败有 fallback，不阻塞主流程。
6. 业务逻辑不直接依赖系统 API / 网络 / LLM / DB 具体实现。
7. DebugTools / 测试替身不被生产代码 import。
8. 测试 + lint + 边界检查脚本通过。
9. 输出 Harness Compliance Report。
```

### 7.2 每语言边界规则（模板，做到该层时具化）

```text
Swift（客户端）：
  - 系统 API（ScreenCaptureKit / CGEventSource / NSWorkspace / Vision / Whisper）
    只允许出现在指定 Collector 文件中（见 perception-harness-design.md §11.2）。

Python（Agent Service）— P1 具化：
  - LLM 调用只能走 ModelRouter，禁止业务代码直接调 SDK。
  - 工具调用只能走 ToolRegistry。
  - DB / 向量库访问只能走 MemoryService。

Go（业务服务）— P1+ 具化：
  - 服务边界通过定义好的 client 调用，禁止跨服务直连 DB。
```

### 7.3 边界检查脚本组织

```text
Scripts/
  check_perception_boundaries.sh   # 已有
  check_agent_boundaries.sh        # P1 占位
  check_go_boundaries.sh           # P1+ 占位
每个脚本独立可跑；CI/本地提交前统一调用。
```

### 7.4 Codex 任务模板

```text
请实现 [模块/功能名]，必须遵守 architecture-harness-design.md 脊柱约定
及该模块的 harness 实例文档。

约束：
1. 跨边界调用必须走 seam（protocol + real + mock）。
2. 新增能力必须登记 FeatureFlag。
3. 核心决策必须记录共享诊断信封事件（带 traceId/spanId）。
4. 新行为必须有单元测试或 replay fixture。
5. 可选模块失败必须降级。
6. 生产代码不得 import 测试替身 / DebugTools。
7. 最后运行测试 + 对应边界检查脚本，输出 Harness Compliance Report。
```

### 7.5 Harness Compliance Report 模板

```text
Harness Compliance Report:
- FeatureFlag added/used: yes/no
- Seam (protocol+real+mock) complete: yes/no
- Diagnostics recorded (with traceId): yes/no
- Fixture/replay added: yes/no
- Fallback implemented: yes/no
- Forbidden direct API/SDK/DB usage: none / details
- Test replicas imported by production code: no / details
- Tests run: ...
- Boundary script run: ...
```

---

## 8. 模块 Harness 索引（活清单）

每完成一个模块回填本表。

| 模块 | 阶段 | Harness 文档/小节 | 状态 | 关键 fixture / 验收点 |
|---|---|---|---|---|
| Perception | P0 | perception-harness-design.md（实例参考） | 已设计·已对齐脊柱 | busy-typing / switch-to-chat / screen-locked / co-watching-sports / stream-fallback |
| Local Agent | P0 | 本文档 §9.1（占位） | 占位 | 升级决策（本地 vs 云端）replay |
| Pet Engine | P0 | 本文档 §9.2（占位） | 占位 | 动作/表情状态机 replay |
| Cloud Agent (Python) | P1 | 本文档 §9.3（占位） | 占位 | 录制 LLM 回放 + 行为断言 |
| Go 服务 / 契约 / 追踪 | P1+ | 本文档 §9.4（占位） | 占位 | 跨语言 schema 契约 fixture |

---

## 9. 各模块 Harness 占位小节

> 占位小节只回答「该模块 harness 要解决什么问题、关键 seam、该测什么」，不写实现细节。做到该层时再扩成完整设计或独立文档。
>
> **实现前置**：每个占位模块在写 harness / 编码前，必须先走 AGENTS.md §0.5 技术选型评审，
> 产出经用户抉择的 `<module>-final.md`，再按 §1.1 扩写 harness。

### 9.1 Local Agent Harness（P0，占位）

```text
要回答的问题：
  - 给定一个 ContextSnapshot，Local Agent 是否正确决定「本地直出 vs 升级云端」？
关键 seam：
  - LocalReasoning（本地 LLM）→ MockLocalLLM
  - CloudAgentCalling → MockCloudAgent（P0 用 mock 跑通）
该测什么：
  - 升级决策规则（深度对话/记忆检索/复杂场景 → 升级；简单反应 → 本地）
  - RulesEngine 阈值
  - ActionDispatcher 输出动作正确
  - 决策事件记录到诊断信封（带 traceId）
```

### 9.2 Pet Engine Harness（P0，占位）

```text
要回答的问题：
  - 给定一个 PetAction，渲染层状态机是否进入正确状态、是否抑制气泡？
关键 seam：
  - 渲染/动画后端可替身（无需真实窗口即可断言状态）
该测什么：
  - 动作 → 状态机转移正确
  - busy 态抑制长气泡
  - 气泡/表情/动画指令解析
```

### 9.3 Cloud Agent Harness（P1，占位）

```text
要回答的问题：
  - 给定录制的输入 + 录制的 LLM 响应，Orchestrator 是否产生确定性的行为？
关键 seam：
  - LLMProviding → MockLLM / 录制回放
  - ToolInvoking → MockToolRegistry
  - MemoryStoring → MockMemory
该测什么：
  - trace 级回放（录制输入 + 录制 LLM 响应重跑 Orchestrator）
  - Agent Eval：prompt 黄金回归 + 行为断言（LLM-as-judge 留作演进）
  - Planner/Executor/Memory 各节点
```

### 9.4 Go 服务 / 契约 / 追踪 Harness（P1+，占位）

```text
要回答的问题：
  - 跨语言接口（Swift↔Go↔Python）的 schema 是否保持一致、不漂移？
  - 一次交互的 traceId 是否真的贯穿三种语言？
关键 seam：
  - MockGateway、基础设施替身（sqlite / fakeredis / 本地 fs）
该测什么：
  - 契约测试：两侧对同一份 schema fixture 测
  - 端到端 trace 拼接：从 Perception tick 到 Cloud Agent 回传，traceId 一致
```

---

## 10. 非目标与演进

### 脊柱阶段不做

```text
1. 不建中心化 Feature Flag 平台（仅做登记约定）。
2. 不建分布式 trace 收集后端（仅约定 traceId 字段与本地 JSONL）。
3. 不做 Agent Eval 看板 / LLM-as-judge（留 P1+，见下）。
4. 不为不存在的层（Go 服务）写实现级 harness，仅占位。
5. 不做云端日志上传、自动 prompt 优化、分布式测试。
```

### 演进方式

```text
- 做到某模块时，把第 9 节对应占位小节扩成完整设计（或拆为独立文档），
  并回填第 8 节索引状态。
- Agent Eval（prompt 黄金回归 / 行为断言 / 可选 LLM-as-judge）在 Cloud Agent
  模块（§9.3）落地时展开——届时才有 Agent 代码可评，现在写即空文字。
- 跨语言契约测试与分布式追踪在 Go 服务接入（§9.4）时展开。
```

