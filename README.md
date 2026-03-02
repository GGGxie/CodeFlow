# CodeFlow

> 数字研发团队 Agent 系统 — 在 Cursor 中一句话想法全自动生成应用

## 简介

CodeFlow 是一套部署在 Cursor IDE 中的数字研发团队 Agent 系统。由 11 个专业角色 Agent 组成，以工程经理（Engineering Manager）为核心调度，支持多阶段并行协作、质量门控和动态反馈路由。

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
| qa-engineer | 测试工程师 |
| security-auditor | 安全审计 |
| devops-engineer | DevOps |
| operations-analyst | 运营分析 |

## 工作流程

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

MIT
