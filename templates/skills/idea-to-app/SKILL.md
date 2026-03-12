---
name: idea-to-app
description: CodeFlow 全流程工作流技能。将用户的产品想法转化为完整应用。当用户描述新产品想法时，工程经理读取此 Skill 来协调整个团队完成研发工作。
---

# Idea to App — 全流程工作流

## 触发条件

### 新建项目
当用户以以下方式表达意图时启动「新建工作流」：
- 「我想做一个...」「帮我做...」「新建一个...」「我有个想法...」
- 或在 CodeFlow 初始化的项目中输入「开始」「Start」「继续」

### 迭代追加功能
当已完成的项目（`current_phase: completed`）需要追加新功能时：
- 「加一个...功能」「新增...」「我想增加...」「帮我加上...」「迭代一下...」
- 工程经理识别到 `current_phase: completed`，进入「迭代工作流」（见本文档末尾）

## 核心原则

1. **有状态**：所有决策和进度记录在 `docs/project-state.md`，支持中断续传
2. **并行优先**：同一阶段内的独立任务并行派发，提升效率
3. **质量门控必须实证**：每阶段的质量门控必须实际读取文件内容，逐项核查，将找到的具体内容作为 evidence 填入。不允许文件存在就视为通过
4. **反馈回路透明**：Agent 失败时必须记录路由原因，不允许悄悄重试
5. **升级机制**：超过重试上限时暂停，向用户请求决策
6. **先跑通再完善**：优先保证核心流程可用，再迭代打磨细节

---

## 阶段 0：初始化与复杂度评估

工程经理在启动时执行：

1. 检查 `docs/project-state.md` 是否存在
   - 存在 → 读取当前阶段，从断点继续
   - 不存在 → 创建初始状态文档，执行复杂度评估
2. 确认用户的想法已记录到 `idea` 字段
3. **评估项目复杂度，决定工作模式**

### 复杂度评估标准

| 维度 | 简单 (fast-track) | 标准 (standard) |
|------|-------------------|-----------------|
| 核心功能数 | ≤ 5 个 | > 5 个 |
| 用户角色 | 1-2 种 | > 2 种 |
| 数据模型 | ≤ 5 个实体 | > 5 个实体 |
| 第三方集成 | 0-1 个 | > 1 个 |
| 典型场景 | PH 产品、个人工具、落地页、MVP | SaaS 平台、管理系统、多端应用 |

### 两种工作模式

**fast-track 模式**（简单项目，快速交付）：
```
阶段1 发现+架构（合并）: product-manager → backend-architect + frontend-architect
阶段2 环境搭建: devops-engineer（仅 docker-compose + 基础配置）
阶段3 实现（并行）: backend-developer + frontend-developer
阶段4 验收交付: 工程经理验收 + 基本部署配置
```
- 跳过独立的 UX 设计阶段（PM 在 PRD 中包含基础页面规划）
- 跳过独立的 QA 和安全审计阶段（开发者自测 + 基本安全检查）
- 跳过运营分析阶段
- 质量门控简化为：能启动 + 核心流程跑通

**standard 模式**（标准项目，完整流程）：
```
阶段1 发现（并行）: product-manager + ux-designer
阶段2 架构（并行）: backend-architect + frontend-architect
阶段2.5 环境搭建: devops-engineer（开发环境）
阶段3 实现（并行）: backend-developer + frontend-developer
阶段3.5 设计走查: 工程经理协调 PM + UX 验证实现效果
阶段4 质量（并行）: qa-engineer + security-auditor
阶段5 交付（顺序）: devops-engineer（生产配置）→ operations-analyst
```

**工程经理在评估后，将 `mode` 写入 project-state.md，后续所有决策以此为依据。**

---

## fast-track 模式详细流程

### 阶段 1：发现 + 架构

**顺序执行**：
1. `product-manager` — 编写精简版 PRD（含基础页面规划），输出 `docs/prd.md`
2. `backend-architect` + `frontend-architect`（并行）— 基于 PRD 设计架构

**质量门控**：
- `docs/prd.md` 存在，包含功能列表和页面规划
- `docs/architecture.md` 和 `docs/frontend-arch.md` 存在
- `docs/api-contract.yaml` 存在

### 阶段 2：环境搭建

**执行**：`devops-engineer`（仅搭建本地开发环境）

> **跳过条件**：如果架构文档指定使用 Supabase/Firebase 等云端 BaaS 方案，且不需要本地 Docker 环境，工程经理可将此阶段标记为 `skipped`，直接进入阶段 3。

- 独立后端：创建 `docker-compose.yml` + `Dockerfile` + `.env.example`
- BaaS 方案：创建 `.env.example` + 可选 Supabase 本地配置
- 确保开发环境基础设施可用

**质量门控**：开发环境可用（Docker 可启动，或 BaaS 连接正常）

### 阶段 3：实现

**并行派发**：`backend-developer` + `frontend-developer`

**质量门控**：
- 后端可启动，核心 API 可访问
- 前端可编译渲染，核心页面可导航

### 阶段 4：验收交付

**工程经理执行**：
- 检查核心用户流程是否跑通
- 更新 `docs/deployment.md` 为简版启动说明
- 标记项目完成

---

## standard 模式详细流程

### 阶段 1：发现（顺序）

**目标**：理解用户需求，产出产品规格和设计规范

**顺序执行**：
1. `product-manager` — 分析想法，编写 PRD，输出 `docs/prd.md`
2. `ux-designer` — **基于 PRD 功能列表** 设计页面结构和交互流程，输出 `docs/design.md`

> PM 先完成 PRD，UX 再基于 PRD 设计。这确保 UX 设计的页面完整覆盖 PRD 中的所有功能，避免并行导致的信息不对齐。

**质量门控**（两者均完成后检查）：
- `docs/prd.md` 存在，且包含：用户故事、功能列表、验收标准
- `docs/design.md` 存在，且包含：页面清单、组件清单、交互规范

**失败路由**：
- `requirement_ambiguity` → 重新派发 `product-manager` 澄清
- `design_issue` → 重新派发 `ux-designer` 修正

### 阶段 2：架构（并行）

**目标**：确定技术栈，设计系统架构和接口规范

**并行派发**：
- `backend-architect` — 系统架构、数据库设计、API 合约，输出 `docs/architecture.md` + `docs/api-contract.yaml`
- `frontend-architect` — 前端架构、组件设计、状态管理方案，输出 `docs/frontend-arch.md`

**质量门控**：
- `docs/architecture.md` 存在，包含：技术栈选型、服务架构、数据模型
- `docs/api-contract.yaml` 存在，符合 OpenAPI 3.0 格式
- `docs/frontend-arch.md` 存在，包含：技术栈、组件树、路由规划

**失败路由**：
- `architectural_issue` → 重新派发 `backend-architect` 重新设计
- `requirement_ambiguity` → 路由回 `product-manager` 补充需求

### 阶段 2.5：环境搭建

**目标**：在代码开发之前搭好本地运行环境

**执行**：`devops-engineer`（仅开发环境配置）
- 根据架构文档创建 `docker-compose.yml`（包含数据库、缓存等依赖服务）
- 创建后端和前端的 `Dockerfile`
- 创建 `.env.example` 环境变量模板
- 验证 `docker-compose up` 可成功启动基础设施服务

**质量门控**：
- `docker-compose.yml` 存在，`docker-compose up` 基础设施服务可启动
- `.env.example` 文件已创建

> 这确保开发者在阶段 3 写代码时有可用的数据库和缓存环境，不会因为环境问题返工。

### 阶段 3：实现（并行）

**目标**：基于架构文档实现完整的前后端代码

**并行派发**：
- `backend-developer` — 实现所有 API 端点、业务逻辑、数据模型，输出到 `src/backend/`
- `frontend-developer` — 实现所有页面、组件、状态管理，输出到 `src/frontend/`

**质量门控**：
- 后端：应用可成功启动，核心 API 可访问
- 前端：应用可编译渲染，核心页面可导航
- 端点数量与 `api-contract.yaml` 基本一致
- 页面数量与 `design.md` 基本一致

**失败路由**：
- `code_bug` → 重新派发对应 developer 修复
- `requirement_ambiguity` → 路由回 `product-manager`
- `architectural_issue` → 路由回 `backend-architect`
- `env_issue` → 路由到 `devops-engineer` 解决环境问题

### 阶段 3.5：设计走查

**目标**：验证实现效果是否符合产品需求和设计规范

**工程经理协调执行**：
1. 对照 `docs/prd.md` 的功能列表，检查每个 Must Have 功能是否已实现
2. 对照 `docs/design.md` 的页面清单，检查布局和交互是否基本还原
3. 记录偏差项，决定是否需要返工

**如有重大偏差**：路由回 `frontend-developer` 或 `backend-developer` 修复

> 这相当于大厂的 "Design Review / 产品走查"，确保做出来的东西是用户想要的。

### 阶段 4：质量（并行）

**目标**：确保代码质量和安全合规

**并行派发**：
- `qa-engineer` — 编写并执行测试，输出 `docs/test-report.md`
- `security-auditor` — 扫描安全漏洞，输出 `docs/security-report.md`

**质量门控**：
- 核心 API 测试通过（不强制 80% 覆盖率，关注核心流程覆盖）
- 无 `Critical` 级别安全漏洞
- E2E 核心流程可跑通

**失败路由**：
- `code_bug` (来自 QA) → 路由到 `backend-developer` 或 `frontend-developer`
- `requirement_ambiguity` (来自 QA) → 路由回 `product-manager`
- `architectural_issue` (来自 Security) → 路由回 `backend-architect`

### 阶段 5：交付（顺序）

**目标**：完善部署配置，规划运营策略

**顺序执行**：
1. `devops-engineer` — 补充生产环境配置（CI/CD、生产 Dockerfile 优化），更新 `docs/deployment.md`
2. `operations-analyst` — 定义关键指标和监控方案，输出 `docs/operations-handbook.md`

**完成标准**：
- `docs/deployment.md` 已更新，包含完整启动命令
- 应用可在本地通过 `docker-compose up` 成功启动

> 注意：`docs/operations-handbook.md` 的存在性检查在 `operations-analyst` 完成后才执行，不在 `devops-engineer` 完成时检查。

**全部完成** → 工程经理更新 `project-state.md`，将 `current_phase` 设为 `completed`，向用户汇报完成情况

---

## 重试与升级策略

```
每个阶段的 retry_count 从 0 开始计数

失败时：
  retry_count += 1
  如果 retry_count < 3：
    按 failure_type 路由到对应 Agent 重新处理
  如果 retry_count >= 3：
    blocked_for_human = true
    向用户报告：当前阶段、失败原因、已尝试次数、请求人工决策
    暂停自动化，等待用户指示
```

---

## project-state.md 更新规则

### 精简原则

project-state.md 是项目的状态追踪文件，但**不是详细日志**。为避免文件膨胀占用上下文窗口，遵循以下原则：

1. **agent 记录**：只记录 agent 名称、状态、一句话 summary、artifacts。不需要复制 agent 返回的完整 issues 列表
2. **质量门控**：只记录每项的 result（✅/❌）和一句话 evidence。不需要大段引用
3. **timeline**：每个事件只需 time + event + 一句话 detail。重大决策才写详细说明
4. **路由记录**：记录 routed_to 和简短原因即可

### 更新时机

| 事件 | 必须更新的字段 |
|---|---|
| 工作流启动 | `idea`、`started_at`、`mode`、所有 phases 初始化为 pending |
| 阶段开始 | `current_phase`、`phases[阶段].status = in_progress` |
| Agent 返回 passed | `phases[阶段].agents` 追加简要记录、`completed_artifacts` |
| Agent 返回 failed | `retry_counts[阶段] += 1`、`pending_issues` 追加、timeline |
| 质量门控执行 | `phases[阶段].quality_gate` 填写 checks 的 result + evidence |
| 阶段通过 | `phases[阶段].status = passed`、`current_phase` 更新 |
| 升级给用户 | `blocked_for_human: true` |
| 全部完成 | `current_phase: completed` |

**禁止行为**：
- ❌ 不允许质量门控的 evidence 为空
- ❌ 不允许质量门控未执行就推进到下一阶段
- ❌ 不允许 timeline 中出现无意义的条目

---

## 向用户的汇报格式

工程经理在关键节点向用户汇报进展：

```
## CodeFlow 进展 — [阶段名称]

**模式**：[fast-track / standard]
**当前阶段**：[阶段名]（X/N）
**已完成**：产出物列表
**正在进行**：当前任务
**下一步**：即将启动的任务

---
[如有问题] ⚠️ 遇到阻塞：<问题描述>，需要您决策：<选项A> / <选项B>
```

---

## 跨会话续传

由于 Cursor 对话有上下文窗口限制，复杂项目可能需要多次对话才能完成。续传机制：

1. **project-state.md 是唯一真相来源**：每次新对话开始时，工程经理必须先读取 `docs/project-state.md`，从 `current_phase` 和 `phases` 状态恢复进度
2. **用户说「继续」即可恢复**：工程经理读取状态后自动从断点继续
3. **阶段间是天然的续传断点**：每个阶段通过质量门控后，状态已完整记录。新对话可以从下一阶段开始，无需了解之前阶段的对话上下文
4. **文档优于记忆**：所有决策和产出都在 `docs/` 目录中，不依赖对话历史

### 跳过阶段

工程经理可以根据实际情况跳过某些阶段：
- 在 `phases[阶段].status` 中标记为 `skipped`
- 在 `timeline` 中记录跳过原因
- 直接推进到下一阶段

常见跳过场景：
- BaaS 方案跳过环境搭建阶段
- fast-track 模式下自动跳过 UX/QA/Security/Ops 阶段
- 用户明确要求跳过某阶段

---

## 迭代工作流（追加功能）

当项目已完成（`current_phase: completed`）后，用户要求追加新功能时进入此工作流。

### 触发条件

- `docs/project-state.md` 存在且 `current_phase: completed`
- 用户描述新功能需求

### 迭代流程（轻量三步）

与新建流程不同，迭代工作流是一个轻量的三步循环：

```
Step 1: 需求分析（工程经理 + product-manager）
  → 更新 docs/prd.md，追加新功能到功能列表
  → 评估影响范围：仅前端 / 仅后端 / 前后端都改 / 需要新数据模型

Step 2: 实现（按影响范围调用对应开发者）
  → 仅前端变更：调用 frontend-developer 或 fullstack-developer
  → 仅后端变更：调用 backend-developer 或 fullstack-developer
  → 前后端都改：调用 fullstack-developer（全栈方案）或并行调用前后端开发者
  → 需要新数据模型：先更新 docs/architecture.md 和 api-contract.yaml，再实现

Step 3: 验证（工程经理验收）
  → 检查新功能是否实现
  → 检查原有功能是否被破坏（回归验证）
  → 更新 project-state.md
```

### project-state.md 迭代记录

迭代不改变 `current_phase`（保持 `completed`），而是在新的 `iterations` 字段中追踪：

```yaml
iterations:
  - id: 1
    feature: "新增导出书签为 CSV 功能"
    requested_at: "2026-03-15 10:00"
    status: completed  # pending | in_progress | completed | blocked
    impact: frontend_only  # frontend_only | backend_only | fullstack | new_model
    agents_called:
      - agent: frontend-developer
        result_status: passed
        summary: "新增导出按钮和 CSV 生成逻辑"
    completed_at: "2026-03-15 11:30"
```

### 迭代原则

1. **最小变更**：只修改与新功能相关的文件，不重构已有代码
2. **回归意识**：实现新功能后，验证至少 3 个已有核心功能仍正常工作
3. **文档同步**：每次迭代后更新 PRD（追加功能）和 API 合约（如有新端点）
4. **累积不清零**：迭代不创建新的 phases，而是追加到 iterations 列表
