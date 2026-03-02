---
name: idea-to-app
description: CodeFlow 全流程工作流技能。将用户的产品想法转化为完整应用。当用户描述新产品想法时，工程经理读取此 Skill 来协调整个团队完成五个阶段的研发工作。
---

# Idea to App — 全流程工作流

## 触发条件

当用户以以下方式表达意图时启动此工作流：
- 「我想做一个...」「帮我做...」「新建一个...」「我有个想法...」
- 或在 CodeFlow 初始化的项目中输入「开始」「Start」「继续」

## 核心原则

1. **有状态**：所有决策和进度记录在 `docs/project-state.md`，支持中断续传
2. **并行优先**：同一阶段内的独立任务并行派发，提升效率
3. **质量门控**：每阶段有明确完成标准，不达标不进入下一阶段
4. **反馈回路**：Agent 失败时根据 `failure_type` 路由到正确的修复者
5. **升级机制**：超过重试上限时暂停，向用户请求决策

---

## 工作流阶段

### 阶段 0：初始化

工程经理在启动时执行：

1. 检查 `docs/project-state.md` 是否存在
   - 存在 → 读取当前阶段，从断点继续
   - 不存在 → 创建初始状态文档，从阶段 1 开始
2. 确认用户的想法已记录到 `idea` 字段
3. 更新 `timeline`，记录启动事件

---

### 阶段 1：发现（并行）

**目标**：理解用户需求，产出产品规格和设计规范

**并行派发**：
- `product-manager` — 分析想法，编写 PRD，输出 `docs/prd.md`
- `ux-designer` — 设计页面结构和交互流程，输出 `docs/design.md`

**质量门控**（两者均完成后检查）：
- `docs/prd.md` 存在，且包含：用户故事、功能列表、验收标准
- `docs/design.md` 存在，且包含：页面清单、组件清单、交互规范

**失败路由**：
- `requirement_ambiguity` → 重新派发 `product-manager` 澄清
- `design_issue` → 重新派发 `ux-designer` 修正

**通过条件满足** → 进入阶段 2

---

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

**通过条件满足** → 进入阶段 3

---

### 阶段 3：实现（并行）

**目标**：基于架构文档实现完整的前后端代码

**并行派发**：
- `backend-developer` — 实现所有 API 端点、业务逻辑、数据模型，输出到 `src/backend/`
- `frontend-developer` — 实现所有页面、组件、状态管理，输出到 `src/frontend/`

**质量门控**：
- 后端：所有 `api-contract.yaml` 中的端点均可访问，基本功能测试通过
- 前端：所有 `design.md` 中列出的页面均可渲染，无控制台错误

**失败路由**：
- `code_bug` → 重新派发对应 developer 修复
- `requirement_ambiguity` → 路由回 `product-manager`
- `architectural_issue` → 路由回 `backend-architect`
- `env_issue` → 路由到 `devops-engineer` 解决环境问题

**通过条件满足** → 进入阶段 4

---

### 阶段 4：质量（并行）

**目标**：确保代码质量、测试覆盖和安全合规

**并行派发**：
- `qa-engineer` — 编写并执行单元测试、集成测试、E2E 测试，输出 `docs/test-report.md`
- `security-auditor` — 扫描安全漏洞，输出 `docs/security-report.md`（按 Critical/High/Medium 分级）

**质量门控**：
- 测试覆盖率 ≥ 80%
- 无 `Critical` 级别安全漏洞
- 所有 E2E 测试通过

**失败路由**：
- `code_bug` (来自 QA) → 路由到 `backend-developer` 或 `frontend-developer`
- `requirement_ambiguity` (来自 QA) → 路由回 `product-manager`
- `architectural_issue` (来自 Security) → 路由回 `backend-architect`

**通过条件满足** → 进入阶段 5

---

### 阶段 5：交付（顺序）

**目标**：完成部署配置，启动运营分析

**顺序执行**：
1. `devops-engineer` — 创建 Docker Compose、CI/CD 配置、环境文档，输出 `docs/deployment.md`
2. `operations-analyst` — 设置监控指标、定义关键 KPI、规划运营策略

**完成标准**：
- `docs/deployment.md` 存在，包含启动命令
- 应用可在本地成功启动

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

## project-state.md 更新时机

| 事件 | 更新内容 |
|---|---|
| 工作流启动 | 创建文档，记录 idea、started_at |
| 阶段开始 | 更新 `current_phase`，添加 timeline 事件 |
| Agent 完成任务 | 添加 artifact 到 `completed_artifacts` |
| Agent 返回失败 | 添加到 `pending_issues`，更新 retry_count |
| 问题解决 | 从 `pending_issues` 移除 |
| 阶段通过质量门控 | 添加 timeline 事件，更新 current_phase |
| 升级给用户 | 设置 `blocked_for_human: true` |
| 全部完成 | `current_phase: completed` |

---

## 向用户的汇报格式

工程经理在关键节点向用户汇报进展：

```
# CodeFlow 进展更新

**当前阶段**：实现阶段（3/5）
**完成产出**：PRD、设计规范、后端架构、前端架构
**正在进行**：后端开发 + 前端开发（并行）
**预计下一步**：质量测试阶段

---
[如有问题] ⚠️ 遇到阻塞：<问题描述>，需要您决策：<选项A> / <选项B>
```
