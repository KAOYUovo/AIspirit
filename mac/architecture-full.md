# AI 桌宠 — 完整版架构设计文档

## 1. 产品定位

macOS 端 AI 桌宠，通过屏幕感知理解用户当前行为，以两种模式（陪伴/赋能）提供拟人化互动反馈。本质是一个 **Agent 产品**——桌宠的行为由 Agent 编排逻辑驱动（感知→思考→决策→行动）。

架构采用"轻量本地 Agent + 重型云端 Agent"混合模式：
- **本地 Agent**：处理低延迟反应式行为（表情切换、简单回应、idle检测），Swift 客户端内嵌
- **云端 Agent**：处理复杂多步推理（深度对话、记忆整合、行为规划、自进化），Python 服务

## 2. 系统全景

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Client Layer                                  │
│                                                                       │
│  ┌─────────────────────────────┐     ┌───────────────────────────┐   │
│  │     macOS Desktop App       │     │   Mobile App (Future)      │   │
│  │  ┌───────────────────────┐  │     │                           │   │
│  │  │  Local Agent (Swift)  │  │     │   (只读 + 对话)            │   │
│  │  └───────────────────────┘  │     │                           │   │
│  └──────────────┬──────────────┘     └─────────────┬─────────────┘   │
└─────────────────┼──────────────────────────────────┼─────────────────┘
                  │ HTTPS/WebSocket                   │ HTTPS
                  ▼                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      API Gateway (Go)                                 │
│           (认证 / 限流 / 路由 / WebSocket管理)                        │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────┼──────────────────────────────────────┐
│                        Backend Services                               │
│                                                                       │
│  ┌─────────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐   │
│  │  Agent Service  │ │  User &    │ │  Sync &    │ │  Admin &   │   │
│  │   (Python)      │ │  Billing   │ │  Memory    │ │  Ops       │   │
│  │                 │ │   (Go)     │ │   (Go)     │ │  (Go)      │   │
│  │ • 行为决策      │ │            │ │            │ │            │   │
│  │ • 多步推理      │ │            │ │            │ │            │   │
│  │ • 工具调用      │ │            │ │            │ │            │   │
│  │ • 记忆检索      │ │            │ │            │ │            │   │
│  │ • 人格/情绪     │ │            │ │            │ │            │   │
│  └─────────────────┘ └────────────┘ └────────────┘ └────────────┘   │
│                                                                       │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
┌──────────────────────────────┼──────────────────────────────────────┐
│                        Infrastructure                                 │
│  ┌──────┐ ┌────────┐ ┌────────┐ ┌───────┐ ┌────────┐ ┌──────────┐  │
│  │  DB  │ │ Cache  │ │   S3   │ │ Queue │ │Vector  │ │  GPU     │  │
│  │      │ │        │ │        │ │       │ │  DB    │ │  Cluster │  │
│  └──────┘ └────────┘ └────────┘ └───────┘ └────────┘ └──────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## 3. 技术栈总览

### 3.1 客户端 (macOS)

| 层面 | 选型 | 理由 |
|------|------|------|
| 语言 | Swift 6 (strict concurrency) | 原生性能、系统API直达 |
| UI | SwiftUI + AppKit 混合 | 主界面用SwiftUI，悬浮窗/动画用AppKit |
| 桌宠渲染 | SpriteKit | 帧动画/粒子/状态机，成熟的2D引擎 |
| 屏幕捕获 | ScreenCaptureKit | macOS原生，低开销 |
| 本地推理 | llama.cpp (Swift binding) | GGUF量化，本地Agent的推理引擎 |
| 本地Agent | 自研轻量框架 (Swift) | 反应式行为、低延迟响应 |
| 本地持久化 | SwiftData | 离线优先，自动迁移 |
| 网络层 | URLSession + WebSocket | 原生，支持后台传输 |

### 3.2 后端 — Agent Service (Python)

| 层面 | 选型 | 理由 |
|------|------|------|
| 语言 | Python 3.12+ | AI/Agent 生态最成熟 |
| Agent框架 | LangGraph / 自研 | 状态机式Agent编排，支持多步推理和工具调用 |
| LLM调用 | LiteLLM / Anthropic SDK | 统一多模型调用，支持 Claude/GPT/本地模型 |
| 向量检索 | LangChain + pgvector | 记忆语义检索 |
| 工具系统 | 自定义 Tool Registry | 桌宠专属工具（查日程、查天气、查专注数据等） |
| API框架 | FastAPI | 异步、流式响应、自动文档 |
| 任务队列 | Celery / ARQ | 异步Agent任务执行 |
| 模型推理 | vLLM / Ollama | GPU推理服务 |

### 3.3 后端 — 业务服务 (Go)

| 层面 | 选型 | 理由 |
|------|------|------|
| 语言 | Go | 高并发网关、业务CRUD、实时推送 |
| API框架 | Gin | 轻量高性能 |
| 实时通信 | WebSocket (gorilla/websocket) | 状态推送、流式转发 |
| 数据库 | PostgreSQL | 用户/订阅/会话 |
| 缓存 | Redis | 会话状态、限流、Agent上下文缓存 |
| 对象存储 | S3兼容 (MinIO/OSS) | 截图、模型文件 |
| 消息队列 | Redis Stream / NATS | Go ↔ Python 服务间通信 |
| 运营后台 | React + Ant Design | 管理端 |

### 3.4 移动端 (Future)

| 层面 | 选型 | 理由 |
|------|------|------|
| 平台 | iOS (SwiftUI) | 与macOS共享核心代码 |
| 定位 | 只读 + 对话 | 查看报告/状态，与桌宠对话 |

## 4. Agent 架构详解

桌宠的"智能"本质是一个 Agent 系统。Agent 分为两层：

```
┌───────────────────────────────────────────────────────────────┐
│                    Client (macOS Swift)                         │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              Local Agent (反应层)                         │   │
│  │                                                           │   │
│  │  Perception ──→ Local Reasoner ──→ Action Dispatcher     │   │
│  │       │              │                    │               │   │
│  │       │         ┌────┴────┐               ▼              │   │
│  │       │         │ 规则 +  │         Pet Engine            │   │
│  │       │         │本地LLM  │         (动画/气泡)           │   │
│  │       │         └────┬────┘                              │   │
│  │       │              │                                    │   │
│  │       │    [需要深度思考?]──────────────────┐             │   │
│  │       │              │No                   │Yes           │   │
│  │       │              ▼                     ▼              │   │
│  │       │        直接响应            Remote Agent Call       │   │
│  └───────┼──────────────────────────────────┼───────────────┘   │
│          │                                  │                    │
└──────────┼──────────────────────────────────┼────────────────────┘
           │                                  │ WebSocket/HTTPS
           │                                  ▼
┌──────────┼─────────────────────────────────────────────────────┐
│          │         Cloud Agent Service (Python)                  │
│          │                                                       │
│  ┌───────┴───────────────────────────────────────────────┐     │
│  │                  Agent Orchestrator                     │     │
│  │                                                         │     │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐ │     │
│  │  │ Planner  │  │ Executor │  │   Reflection/Memory  │ │     │
│  │  │(行为规划) │  │(工具调用) │  │   (反思/记忆整合)    │ │     │
│  │  └──────────┘  └──────────┘  └──────────────────────┘ │     │
│  │                      │                                  │     │
│  │              ┌───────┼───────┐                         │     │
│  │              ▼       ▼       ▼                         │     │
│  │         ┌───────┐┌──────┐┌────────┐                   │     │
│  │         │ Tools ││ LLM  ││VectorDB│                   │     │
│  │         └───────┘└──────┘└────────┘                   │     │
│  └────────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────┘
```

### 4.1 Local Agent（客户端本地 Agent）

处理低延迟、反应式行为，不依赖网络。

| 能力 | 实现方式 | 延迟要求 |
|------|----------|----------|
| 屏幕变化检测 | dHash + 规则 | <100ms |
| 简单情绪反应 | 本地小LLM (1-3B) | <1s |
| 专注状态判断 | 本地VLM + 规则引擎 | <3s |
| idle/分心检测 | 纯规则（键鼠+dHash） | <100ms |
| 表情/动作切换 | 状态机 | 即时 |
| 用户输入响应 | 本地LLM简单回复 | <2s |

**决策升级逻辑**：Local Agent 判断是否需要云端 Agent 介入：
- 用户发起深度对话 → 升级
- 需要记忆检索 → 升级
- 复杂场景分析（截图+上下文） → 升级
- 行为规划（待办、精力管理） → 升级
- 简单反应/状态切换 → 本地处理

### 4.2 Cloud Agent（云端 Python Agent）

处理复杂推理、多步决策、记忆管理。

```python
# Agent 核心循环（概念）
class PetAgent:
    def run(self, input: AgentInput) -> AgentOutput:
        # 1. 检索相关记忆
        memories = self.memory.retrieve(input.context)
        # 2. 规划行为
        plan = self.planner.plan(input, memories, self.personality)
        # 3. 执行工具调用（如需要）
        results = self.executor.run_tools(plan.tool_calls)
        # 4. 生成最终响应
        response = self.synthesize(plan, results, memories)
        # 5. 更新记忆
        self.memory.store(input, response)
        # 6. 反思与自进化
        self.reflect(input, response, user_feedback)
        return response
```

Agent 能力模块：

| 模块 | 职责 | 关键技术 |
|------|------|----------|
| **Planner** | 理解意图、规划多步行为 | LLM (Claude/GPT) + CoT |
| **Executor** | 执行工具调用 | Tool Registry + Function Calling |
| **Memory** | 短期/长期记忆管理 | Vector DB + 摘要压缩 |
| **Personality** | 桌宠人格/情绪状态 | Prompt Engineering + 状态机 |
| **Reflection** | 根据用户反馈自我调整 | 偏好学习 + Prompt自适应 |

Agent 可调用的工具（Tool）：

| Tool | 功能 |
|------|------|
| `analyze_screen` | 深度分析截图内容 |
| `search_memory` | 语义搜索历史记忆 |
| `get_focus_stats` | 获取专注统计数据 |
| `set_reminder` | 设置待办提醒 |
| `get_calendar` | 查询日程（需用户授权） |
| `web_search` | 联网搜索（需用户授权） |
| `update_personality` | 更新桌宠人格偏好 |

### 4.3 本地 ↔ 云端协作流程

```
用户操作/屏幕变化
    → Local Agent 感知
    → 本地快速判断（规则 + 小模型）
    ├─ [简单场景] → 本地直接出动作 → Pet Engine 执行
    └─ [复杂场景] → 打包上下文 → Cloud Agent
                      → 多步推理 + 工具调用 + 记忆检索
                      → 流式返回行为指令
                      → Local Agent 接收 → Pet Engine 执行
```

## 5. 客户端架构

```
┌─────────────────────────────────────────────────────────┐
│                    Application Shell                      │
│  (Lifecycle / WindowManager / MenuBar / Permissions)     │
└──────────────────────────┬──────────────────────────────┘
                           │
     ┌─────────────────────┼─────────────────────┐
     ▼                     ▼                     ▼
┌──────────┐      ┌──────────────┐      ┌──────────────┐
│   Pet    │      │ Local Agent  │      │  Perception  │
│  Engine  │◄─────│  (决策中枢)  │◄─────│    Layer     │
└──────────┘      └──────┬───────┘      └──────────────┘
                         │
              ┌──────────┼──────────┐
              ▼          ▼          ▼
       ┌───────────┐┌────────┐┌─────────┐
       │ Local LLM ││ Rules  ││ Remote  │
       │ (llama.cpp)││ Engine ││  Proxy  │──→ Cloud Agent
       └───────────┘└────────┘└─────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│                   Foundation Layer                        │
│  EventBus / Storage / Config / SyncEngine / Privacy      │
└─────────────────────────────────────────────────────────┘
```

### 5.1 模块职责

| 模块 | 职责 |
|------|------|
| **Perception Layer** | 截屏、dHash、idle检测、前台App检测 |
| **Local Agent** | 本地决策中枢：判断场景→选择处理路径→输出动作 |
| **Rules Engine** | 纯规则判断（idle阈值、dHash过滤、黑名单等） |
| **Local LLM** | 本地小模型推理（简单对话、快速分析） |
| **Remote Proxy** | 与云端Agent通信，上下文打包、流式接收 |
| **Pet Engine** | 动画状态机、对话气泡、交互处理 |
| **SyncEngine** | 离线优先增量同步，CRDT冲突解决 |
| **PrivacyManager** | 黑名单/脱敏/本地云端路由决策 |

## 6. 后端架构

### 6.1 服务拆分（Go + Python 混合）

```
┌─────────────────────────────────────────────────────────────┐
│                   API Gateway (Go)                            │
│       (JWT验证 / 限流 / 路由 / WebSocket长连接管理)           │
└───────────────────────────┬─────────────────────────────────┘
                            │
     ┌──────────────────────┼──────────────────────┐
     ▼                      ▼                      ▼
┌──────────────────┐ ┌─────────────┐ ┌─────────────────┐
│  Agent Service   │ │  User &     │ │   Sync          │
│   (Python)       │ │  Billing    │ │   Service       │
├──────────────────┤ │   (Go)      │ │   (Go)          │
│• Agent编排       │ ├─────────────┤ ├─────────────────┤
│• 多步推理        │ │• 注册/登录  │ │• 数据上行/下行  │
│• 工具调用        │ │• 订阅管理   │ │• 冲突合并       │
│• 记忆检索/写入   │ │• 额度管控   │ │• 跨端状态推送   │
│• 人格/情绪状态   │ │• 设备管理   │ │• 截图存储管理   │
│• 模型路由        │ │• Token计量  │ │                 │
│• Prompt管理      │ │             │ │                 │
│• 自进化/反思     │ │             │ │                 │
└──────┬───────────┘ └──────┬──────┘ └────────┬────────┘
       │                    │                  │
       ▼                    ▼                  ▼
┌─────────────────────────────────────────────────────────────┐
│              Shared Infrastructure                            │
│  PostgreSQL / Redis / S3 / NATS / pgvector / GPU Cluster     │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│              Admin Service (Go + React)                       │
│  用户管理 / Prompt工坊 / Agent行为调试 / 模型管理 /          │
│  A/B测试 / 数据看板 / 记忆审计                               │
└─────────────────────────────────────────────────────────────┘
```

### 6.2 Agent Service（Python，核心）

这是整个后端的灵魂，承载桌宠的"高级认知"能力。

```
Client Request (截图 + 上下文 + 用户消息)
    → 加载用户 Agent 状态（人格、情绪、偏好）
    → 检索相关记忆（短期上下文 + 长期向量检索）
    → Agent 编排循环：
        → Planner: 理解意图 + 规划行为
        → Executor: 调用工具（如需要）
        → Synthesizer: 整合结果生成响应
    → 流式返回行为指令（动作 + 表情 + 文本）
    → 异步写入记忆 + 更新情绪状态
    → Token 计量上报
```

内部模块：

| 模块 | 职责 | 技术 |
|------|------|------|
| **AgentOrchestrator** | Agent主循环编排 | LangGraph / 自研状态机 |
| **PlannerNode** | 意图理解 + 行为规划 | LLM + CoT prompting |
| **ToolExecutor** | 工具注册与执行 | Function Calling |
| **MemoryService** | 记忆读写与检索 | pgvector + 摘要LLM |
| **PersonalityEngine** | 人格模板 + 情绪状态机 | Prompt模板 + 状态持久化 |
| **ModelRouter** | 按任务路由到不同模型 | LiteLLM + 自定义策略 |
| **PromptRegistry** | Prompt版本管理与热更新 | DB + 缓存 |
| **ReflectionEngine** | 用户反馈→偏好学习→自进化 | 异步Pipeline |

关键设计：
- **Prompt 热更新**：模板存数据库，Admin 可在线编辑发布，客户端无需更新
- **模型热切换**：注册表管理可用模型，支持灰度切换、A/B测试
- **多级降级**：云端GPU → 第三方API → 通知客户端降级到本地模型
- **有状态 Agent**：每个用户有独立的 Agent 状态（情绪、记忆、偏好），存 Redis + DB

### 6.3 User & Billing Service（Go）

| 功能 | 说明 |
|------|------|
| 账号体系 | Apple ID登录 + 邮箱注册 |
| 订阅管理 | 免费档（仅本地）/ 基础档 / 高级档 |
| 额度管控 | 按Token用量或请求次数，支持日/月额度 |
| 设备管理 | 单账号多设备，设备列表查看与管理 |

### 6.4 Sync Service（Go）

| 功能 | 说明 |
|------|------|
| 会话同步 | 专注会话记录、统计数据上云 |
| 记忆同步 | 长期记忆加密上传，跨设备可用 |
| 配置同步 | 用户偏好/桌宠人设跨端一致 |
| 截图管理 | 可选上传（加密），支持云端回看 |
| 实时状态 | WebSocket推送桌宠当前状态到移动端 |

### 6.5 Admin Service（Go + React）

| 模块 | 功能 |
|------|------|
| 用户管理 | 查看/封禁/额度调整 |
| Prompt 工坊 | 在线编辑/版本管理/灰度发布/效果对比 |
| Agent 调试 | 查看Agent推理链路、工具调用日志、行为回放 |
| 模型管理 | 注册模型/设置路由规则/监控推理延迟 |
| 数据看板 | DAU/留存/会话时长/模型调用量/付费转化 |
| A/B 测试 | Prompt/模型/Agent策略的多组实验 |
| 记忆审计 | 用户记忆内容抽检（脱敏） |

## 7. 核心数据流

### 7.1 陪伴模式

```
ScreenCapture ─3s─→ ContextSnapshot
    → Local Agent 感知 + PrivacyFilter
    → 本地小模型快速分析（用户在看什么）
    ├─ [常见场景] → 本地直接生成反应 → Pet Engine
    └─ [需要深度理解] → Cloud Agent
        → 检索用户记忆/偏好
        → 生成个性化互动（结合人格+记忆+当前场景）
        → 流式返回 → Pet Engine
```

### 7.2 赋能模式

```
ScreenCapture ─5s─→ ContextSnapshot
    → Local Agent: dHash gate / idle gate / 规则过滤
    → 本地VLM判断专注状态
    ├─ [clearly focused/idle] → 本地直出 → Pet Engine
    └─ [模糊/需要上下文判断] → Cloud Agent
        → 结合历史专注模式 + 记忆 → 精确判断
        → 生成有上下文的提醒文案
        → 返回 → Pet Engine + 提醒系统
```

### 7.3 对话交互

```
用户输入消息
    → Local Agent 判断复杂度
    ├─ [简单闲聊] → 本地LLM回复 (<2s)
    └─ [复杂对话] → Cloud Agent
        → 加载人格 + 检索记忆 + 可能调用工具
        → 流式返回 → 对话气泡
```

### 7.4 移动端

```
Mobile App
    → GET /api/pet/status → 当前桌宠状态/表情
    → GET /api/sessions/today → 今日专注统计
    → WebSocket /ws/pet → 实时状态推送
    → POST /api/agent/chat → 云端Agent对话
```

## 8. 模块依赖关系

### 客户端内部

```
Perception ──→ Local Agent ──→ Pet Engine
                  │
        ┌─────────┼─────────┐
        ▼         ▼         ▼
   Local LLM   Rules    Remote Proxy ──→ Cloud Agent (Backend)
                  │
                  ▼
      Foundation (EventBus / Storage / Config / SyncEngine)
```

### 后端服务间

```
API Gateway (Go)
    ├──→ Agent Service (Python) ──→ LLM API / vLLM / Vector DB
    ├──→ User & Billing (Go) ──→ PostgreSQL / Redis
    └──→ Sync Service (Go) ──→ PostgreSQL / S3 / Redis

Agent Service ←──NATS──→ Sync Service (记忆读写)
Admin Service (Go) ──→ 所有后端服务（管理接口）
```

### 语言边界

```
┌─────────────┐     ┌───────────────────┐     ┌──────────────┐
│ Swift Client│────→│   Go (Gateway +   │────→│   Python     │
│             │     │   Biz Services)   │     │ (Agent Core) │
└─────────────┘     └───────────────────┘     └──────────────┘
  桌宠渲染/感知        认证/限流/同步/计费       Agent编排/推理/记忆
```

## 9. 扩展性设计

| 未来功能 | 客户端扩展点 | 后端扩展点 (Python Agent) |
|----------|-------------|--------------------------|
| 长短期记忆 | 本地轻量向量缓存 | MemoryService + pgvector |
| 待办提醒 | Local Agent 新增 reminder 动作 | Agent Tool: `set_reminder` |
| 精力管理 | Perception 统计数据上报 | Agent Tool: `analyze_energy` + 报告生成 |
| 隐私控制 | PrivacyFilter 规则引擎 | 服务端E2E加密 + 数据保留策略 |
| 模型选择 | 配置面板切换 | ModelRouter 多后端注册 |
| 自进化 | 用户反馈采集上报 | ReflectionEngine → 偏好学习 → Prompt自适应 |
| 多端同步 | SyncEngine (CRDT) | Sync Service + WebSocket广播 |
| 社区/皮肤 | Pet Engine 资源包加载 | 资源市场 + CDN分发 |
| 第三方集成 | PluginHost | Agent Tool 动态注册 + OAuth |

## 10. 安全与隐私架构

```
截图 → PrivacyFilter
       ├─ 黑名单应用？→ 丢弃
       ├─ 敏感窗口？→ 模糊处理
       └─ 通过
            ├─ 用户选择本地推理？→ 不上传
            └─ 用户允许云端？→ E2E加密上传 → 推理后删除
```

原则：
- **默认本地**：首次使用默认纯本地推理
- **端到端加密**：截图上云全程 E2E 加密，推理后立即删除原图
- **用户可控**：细粒度控制哪些应用可被捕获、数据保留时长
- **最小收集**：后端只存分析结果，不长期存储原始截图

## 11. 分阶段演进路线

| 阶段 | 范围 | 后端需求 |
|------|------|----------|
| **P0 - MVP** | macOS客户端 + 本地模型 + 两种模式 | 无 |
| **P1 - 云端增强** | + 云端推理 + 账号体系 + 基础订阅 | Inference + User Service |
| **P2 - 记忆与进化** | + 长短期记忆 + 自进化 + 隐私控制 | + Sync + Vector DB |
| **P3 - 多端** | + iOS查看端 + 跨端同步 | + WebSocket + 移动推送 |
| **P4 - 平台化** | + 皮肤市场 + 插件 + 第三方集成 | + Admin完善 + CDN |

## 12. 目录结构

### 客户端 (Swift)

```
AIPet/
├── App/                        # 入口、生命周期、权限
├── Perception/                 # 屏幕捕获、环境感知
│   ├── ScreenCapture.swift
│   ├── FrontAppDetector.swift
│   ├── IdleDetector.swift
│   └── DHashComputer.swift
├── Agent/                      # 本地 Agent
│   ├── LocalAgent.swift        # 决策中枢
│   ├── RulesEngine.swift       # 规则判断
│   ├── LocalLLM.swift          # llama.cpp 封装
│   ├── RemoteProxy.swift       # 云端Agent通信
│   └── ActionDispatcher.swift  # 动作分发
├── Pet/                        # 桌宠渲染与交互
│   ├── PetWindow.swift
│   ├── PetRenderer.swift
│   ├── PetStateMachine.swift
│   └── BubbleView.swift
├── Sync/                       # 云端同步
├── Privacy/                    # 隐私管理
├── Foundation/                 # 基础设施
└── UI/                         # 设置页
```

### 后端 — Agent Service (Python)

```
agent-service/
├── app/
│   ├── main.py                 # FastAPI 入口
│   ├── agent/
│   │   ├── orchestrator.py     # Agent 主循环编排
│   │   ├── planner.py          # 行为规划
│   │   ├── executor.py         # 工具执行
│   │   ├── reflection.py       # 反思与自进化
│   │   └── personality.py      # 人格/情绪状态机
│   ├── memory/
│   │   ├── service.py          # 记忆读写
│   │   ├── retriever.py        # 向量检索
│   │   └── compressor.py       # 记忆摘要压缩
│   ├── tools/                  # Agent 可调用工具
│   │   ├── registry.py
│   │   ├── screen_analyze.py
│   │   ├── focus_stats.py
│   │   └── reminder.py
│   ├── models/
│   │   ├── router.py           # 模型路由
│   │   └── providers/          # 各LLM provider适配
│   └── prompts/                # Prompt 模板
├── tests/
└── pyproject.toml
```

### 后端 — 业务服务 (Go)

```
backend/
├── cmd/                        # 服务入口
│   ├── gateway/
│   ├── user/
│   ├── sync/
│   └── admin/
├── internal/
│   ├── gateway/                # API网关
│   ├── user/                   # 用户/计费
│   ├── sync/                   # 同步服务
│   └── admin/                  # 运营后台
├── pkg/                        # 公共库
├── deploy/                     # 部署配置
└── admin-web/                  # 运营前端 (React)
```

## 13. 关键接口（概要）

### 客户端 ↔ 后端

| 接口 | 方法 | 服务 | 用途 |
|------|------|------|------|
| `/api/auth/login` | POST | User (Go) | Apple ID / 邮箱登录 |
| `/api/agent/analyze` | POST (stream) | Agent (Python) | 云端Agent分析截图+上下文 |
| `/api/agent/chat` | POST (stream) | Agent (Python) | 云端Agent对话 |
| `/api/agent/feedback` | POST | Agent (Python) | 用户反馈（自进化输入） |
| `/api/sync/push` | POST | Sync (Go) | 数据上行（增量） |
| `/api/sync/pull` | GET | Sync (Go) | 数据下行（增量） |
| `/api/memory/query` | POST | Agent (Python) | 记忆语义检索 |
| `/api/pet/status` | GET | Sync (Go) | 桌宠当前状态（移动端） |
| `/api/config/prompts` | GET | Agent (Python) | 拉取最新Prompt版本 |
| `/ws/realtime` | WebSocket | Gateway (Go) | 实时状态推送 + 流式Agent响应转发 |

### 后端内部 (Go ↔ Python)

通过 Redis Stream / NATS 异步通信 + gRPC 同步调用：
- Gateway 将 Agent 请求转发到 Python Agent Service（gRPC/HTTP）
- Agent Service 写入记忆后通知 Sync Service（NATS event）
- User Service 的额度信息由 Gateway 注入请求 header，Agent Service 读取
