# CodeFlow

> 数字研发团队 Agent 系统 — 在 Cursor 中一句话想法全自动生成应用

## 简介

CodeFlow 是一套部署在 Cursor IDE 中的数字研发团队 Agent 系统。由 12 个专业角色 Agent 组成，以工程经理（Engineering Manager）为核心调度，支持多阶段并行协作、质量门控和动态反馈路由。

用户只需一句话描述产品想法，团队自动完成：需求分析 → 架构设计 → 代码实现 → 测试 → 安全审计 → 部署配置。

## 快速开始

```bash
# 克隆仓库
git clone https://github.com/GGGxie/CodeFlow.git
cd CodeFlow
chmod +x codeflow.sh

# 可选：设置全局别名
echo 'alias codeflow="bash /path/to/CodeFlow/codeflow.sh"' >> ~/.bashrc
source ~/.bashrc

# 新建项目
codeflow new
```

## 命令

| 命令 | 说明 |
|---|---|
| `codeflow new` | 新建项目：输入项目名和想法，初始化团队配置 |
| `codeflow init` | 在当前目录初始化 CodeFlow 团队配置 |
| `codeflow uninstall` | 移除 CodeFlow 配置（保留 docs/ 和 src/） |
| `codeflow update` | 更新 Agent 定义到最新版本 |
| `codeflow status` | 查看当前目录的安装状态 |
| `codeflow help` | 显示帮助信息 |

### 选项

| 选项 | 说明 |
|---|---|
| `-y`, `--yes` | 跳过所有确认提示（默认回答"是"）。可放在命令前后，例如 `codeflow --yes uninstall` |

没有 `--yes` 时，提示的默认值保持保守：覆盖、卸载等操作默认回答"否"；输入结束（EOF）视为拒绝。

### 文件保护与备份

- `init` / `update` 只会改动 CodeFlow 自带的文件：`.cursor/rules/codeflow-team.mdc`、`.cursor/skills/idea-to-app/SKILL.md` 和 `.cursor/agents/` 下与内置 Agent 同名的文件。你自己的其它 Agent、规则、技能不会被改动。
- 如果上述文件已存在且内容与内置版本不同，会先列出并询问；确认后（或使用 `--yes`）把原文件备份到 `.cursor/.codeflow-backup/<时间戳>/`（保持相对 `.cursor/` 的目录结构），并打印备份路径，然后再覆盖。内容相同的文件不会备份。
- `uninstall` 只删除上述 CodeFlow 文件（被修改过的会先备份），目录只有在变空时才会删除；`docs/`、`src/` 和你自己的 Agent 保持不变。
- `new` 在已有目录中运行时：不会覆盖已有的 `docs/project-state.md`（提示并跳过）；只向 `.gitignore` 追加缺失的条目；仅提交 `.cursor`、`docs`、`.gitignore`，其它文件（例如 `.env`）不会被提交；目录已是 Git 仓库时不会重复 `git init`。
- `new` 会校验项目名：不能包含 `/`、控制字符（含换行），不能是 `.` / `..`，不能以 `-` 开头。

## 工作模式

工程经理根据项目复杂度选择模式，并记录在 `docs/project-state.md` 的 `mode` 字段：

| 模式 | 适用场景 | 流程 |
|---|---|---|
| `fast-track` | 简单项目（≤5 个核心功能） | 4 阶段快速交付 |
| `standard` | 标准项目（>5 个核心功能） | 完整 5+ 阶段流程，包含 UX 设计、测试、安全审计和运营分析 |

## 团队成员

| Agent | 角色 |
|---|---|
| engineering-manager | 工程经理（核心调度，有状态编排） |
| product-manager | 产品经理 |
| ux-designer | UX 设计师 |
| backend-architect | 后端架构师 |
| frontend-architect | 前端架构师 |
| backend-developer | 后端开发 |
| frontend-developer | 前端开发 |
| fullstack-developer | 全栈开发（Next.js / Nuxt.js 等全栈方案） |
| qa-engineer | 测试工程师 |
| security-auditor | 安全审计 |
| devops-engineer | DevOps |
| operations-analyst | 运营分析 |

## 工作流程（standard 模式示意）

```
用户输入想法
  → 阶段1（并行）：product-manager + ux-designer
  → 阶段2（并行）：backend-architect + frontend-architect
  → 阶段3（并行）：backend-developer + frontend-developer
  → 阶段4（并行）：qa-engineer + security-auditor
  → 阶段5：devops-engineer → operations-analyst
```

工程经理全程维护 `docs/project-state.md`，支持中断续传和动态反馈路由。

## 许可证

MIT，详见 [LICENSE](LICENSE)。

## 开发与测试

测试为纯 bash，无需安装任何依赖。每个用例都在 `mktemp -d` 创建的临时目录中运行，并把 `HOME` 重定向到其中，不会触碰真实目录：

```bash
bash tests/run.sh            # 运行全部用例
bash tests/run.sh uninstall  # 只运行名称包含 uninstall 的用例
```
