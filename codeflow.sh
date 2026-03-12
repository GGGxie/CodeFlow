#!/usr/bin/env bash
# CodeFlow — 数字研发团队 Agent 系统
# 用法: codeflow <命令> [选项]

set -euo pipefail

# ─── 颜色 ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'
YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[CodeFlow]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*" >&2; }
title()   { echo -e "\n${BOLD}${CYAN}$*${NC}"; }

# ─── 全局选项 ─────────────────────────────────────────────────────────────────
YES_MODE=false

# ─── 路径 ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"

# ─── 交互式确认（支持 --yes 跳过）──────────────────────────────────────────
confirm_prompt() {
  local prompt="$1"
  local default="${2:-N}"
  if [[ "$YES_MODE" == true ]]; then
    return 0
  fi
  read -rp "$prompt" answer
  if [[ "$default" == "Y" ]]; then
    [[ ! "$answer" =~ ^[Nn]$ ]]
  else
    [[ "$answer" =~ ^[Yy]$ ]]
  fi
}

# ─── 帮助信息 ────────────────────────────────────────────────────────────────
usage() {
  echo -e "${BOLD}CodeFlow${NC} — 数字研发团队 Agent 系统\n"
  echo "用法: codeflow <命令> [选项]"
  echo ""
  echo "命令:"
  echo "  new         新建项目：输入项目名和想法，初始化团队配置"
  echo "  init        在当前目录初始化 CodeFlow 团队配置"
  echo "  uninstall   移除当前目录的 CodeFlow 配置（保留 docs/ 和 src/）"
  echo "  update      更新 Agent 定义到最新版本"
  echo "  status      查看当前目录的 CodeFlow 安装状态"
  echo "  help        显示此帮助信息"
  echo ""
  echo "工作模式:"
  echo "  fast-track  简单项目（≤5 核心功能），4 阶段快速交付"
  echo "  standard    标准项目（>5 核心功能），完整 5+ 阶段流程"
  echo ""
  echo "示例:"
  echo "  codeflow new                      # 新建项目"
  echo "  cd my-project && codeflow init    # 在已有目录初始化"
}

# ─── 安装核心 ────────────────────────────────────────────────────────────────
do_install() {
  local target_dir="$1"

  # 检查模板目录
  if [[ ! -d "$TEMPLATES_DIR" ]]; then
    error "找不到模板目录: ${TEMPLATES_DIR}"
    error "请确保在 CodeFlow 仓库根目录下运行此脚本"
    exit 1
  fi

  # 检查是否已安装
  if [[ -d "${target_dir}/.cursor/agents" ]]; then
    warn "检测到已有 CodeFlow 配置"
    if ! confirm_prompt "是否覆盖安装？(y/N): " "N"; then
      info "已取消安装"
      exit 0
    fi
  fi

  info "正在安装 CodeFlow 团队配置..."

  # 创建目录结构
  mkdir -p "${target_dir}/.cursor/agents"
  mkdir -p "${target_dir}/.cursor/rules"
  mkdir -p "${target_dir}/.cursor/skills/idea-to-app"

  # 复制 Rules
  cp "${TEMPLATES_DIR}/rules/codeflow-team.mdc" \
     "${target_dir}/.cursor/rules/codeflow-team.mdc"
  success "团队规范 (.cursor/rules/codeflow-team.mdc)"

  # 复制 Skills
  cp "${TEMPLATES_DIR}/skills/idea-to-app/SKILL.md" \
     "${target_dir}/.cursor/skills/idea-to-app/SKILL.md"
  success "全流程技能 (.cursor/skills/idea-to-app/SKILL.md)"

  # 复制所有 Agents
  local agents=(
    "engineering-manager"
    "product-manager"
    "ux-designer"
    "backend-architect"
    "frontend-architect"
    "backend-developer"
    "frontend-developer"
    "fullstack-developer"
    "qa-engineer"
    "security-auditor"
    "devops-engineer"
    "operations-analyst"
  )

  for agent in "${agents[@]}"; do
    cp "${TEMPLATES_DIR}/agents/${agent}.md" \
       "${target_dir}/.cursor/agents/${agent}.md"
    success "Agent: ${agent}"
  done

  # 创建 docs 目录
  mkdir -p "${target_dir}/docs"

  success "\nCodeFlow 安装完成！"
}

# ─── 命令：new ────────────────────────────────────────────────────────────────
cmd_new() {
  title "CodeFlow — 新建项目"
  echo ""

  # 确定父目录
  local parent_dir="${HOME}/Document"
  read -rp "项目将创建在哪个目录下？[${parent_dir}]: " custom_dir
  if [[ -n "$custom_dir" ]]; then
    parent_dir="$custom_dir"
  fi
  mkdir -p "$parent_dir"

  # 输入项目名
  echo ""
  local project_name
  while true; do
    read -rp "项目名称: " project_name
    # 去除首尾空格，不强制转换大小写
    project_name=$(echo "$project_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ ${#project_name} -ge 2 ]]; then
      break
    fi
    warn "名称至少 2 个字符"
  done

  # 检查目录冲突
  local project_dir="${parent_dir}/${project_name}"
  if [[ -d "$project_dir" ]]; then
    warn "目录已存在: ${project_dir}"
    if ! confirm_prompt "是否继续在该目录初始化 CodeFlow？(y/N): " "N"; then
      info "已取消"
      exit 0
    fi
  fi

  # 采集想法
  echo ""
  echo -e "${BOLD}请用一句话描述你的产品想法：${NC}"
  echo -e "${YELLOW}（例如：一个帮助远程团队追踪每日目标的 SaaS 工具）${NC}"
  echo ""
  local idea
  read -rp "> " idea
  if [[ -z "$idea" ]]; then
    error "想法不能为空"
    exit 1
  fi

  # 确认
  echo ""
  title "确认信息"
  echo -e "  项目名称: ${BOLD}${project_name}${NC}"
  echo -e "  项目路径: ${BOLD}${project_dir}${NC}"
  echo -e "  产品想法: ${idea}"
  echo ""
  if ! confirm_prompt "确认创建？(Y/n): " "Y"; then
    info "已取消"
    exit 0
  fi

  # 创建目录并安装
  mkdir -p "$project_dir"
  do_install "$project_dir"

  # 写入初始 project-state.md（完整 phases 结构，与 engineering-manager 期望格式一致）
  local now
  now=$(date '+%Y-%m-%d %H:%M')
  cat > "${project_dir}/docs/project-state.md" << STATEOF
project_name: "${project_name}"
current_phase: discovery
idea: "${idea}"
started_at: "${now}"
mode: standard  # standard | fast-track
retry_counts:
  discovery: 0
  architecture: 0
  implementation: 0
  quality: 0
  delivery: 0

phases:
  discovery:
    status: pending
    agents: []
    quality_gate:
      checked_at: ""
      checks: []
      verdict: pending
      notes: ""
  architecture:
    status: pending
    agents: []
    quality_gate:
      checked_at: ""
      checks: []
      verdict: pending
      notes: ""
  implementation:
    status: pending
    agents: []
    quality_gate:
      checked_at: ""
      checks: []
      verdict: pending
      notes: ""
  quality:
    status: pending
    agents: []
    quality_gate:
      checked_at: ""
      checks: []
      verdict: pending
      notes: ""
  delivery:
    status: pending
    agents: []
    quality_gate:
      checked_at: ""
      checks: []
      verdict: pending
      notes: ""

completed_artifacts: []
pending_issues: []
blocked_for_human: false

timeline:
  - time: "${now}"
    event: "项目创建"
    detail: "用户想法：${idea}"
STATEOF

  success "项目状态文档已创建 (docs/project-state.md)"

  # 初始化 git
  if command -v git &>/dev/null; then
    cd "$project_dir"
    git init -q
    cat > .gitignore << 'GITEOF'
node_modules/
.env
.env.local
dist/
build/
*.log
.DS_Store
GITEOF
    git add -A
    git commit -q -m "chore: initialize CodeFlow project"
    success "Git 仓库已初始化"
  fi

  # 完成提示
  echo ""
  title "准备就绪！"
  echo ""
  echo -e "  项目路径: ${BOLD}${project_dir}${NC}"
  echo ""
  echo -e "  ${BOLD}下一步：${NC}"
  echo -e "  1. 在 Cursor 中打开项目目录"
  echo -e "  2. 在对话框中输入：${BOLD}开始${NC}"
  echo -e "  3. 工程经理将自动协调团队为你生成完整应用"
  echo ""

  if command -v cursor &>/dev/null; then
    if confirm_prompt "是否立即用 Cursor 打开项目？(Y/n): " "Y"; then
      cursor "$project_dir"
    fi
  else
    info "请手动在 Cursor 中打开: ${project_dir}"
  fi
}

# ─── 命令：init ───────────────────────────────────────────────────────────────
cmd_init() {
  local target_dir="${1:-$(pwd)}"
  title "CodeFlow — 初始化"
  echo ""
  info "目标目录: ${target_dir}"
  do_install "$target_dir"
  echo ""
  echo -e "  ${BOLD}下一步：${NC}"
  echo -e "  在 Cursor 中打开此目录，输入 ${BOLD}开始${NC} 启动团队协作"
}

# ─── 命令：uninstall ──────────────────────────────────────────────────────────
cmd_uninstall() {
  local target_dir="${1:-$(pwd)}"

  title "CodeFlow — 卸载"
  echo ""
  warn "将删除以下 CodeFlow 配置文件（docs/ 和 src/ 不受影响）："
  echo ""

  local has_files=false
  for path in \
    "${target_dir}/.cursor/rules/codeflow-team.mdc" \
    "${target_dir}/.cursor/skills/idea-to-app" \
    "${target_dir}/.cursor/agents"; do
    if [[ -e "$path" ]]; then
      echo "  - ${path#${target_dir}/}"
      has_files=true
    fi
  done

  if [[ "$has_files" == false ]]; then
    warn "当前目录未安装 CodeFlow"
    exit 0
  fi

  echo ""
  read -rp "确认卸载？(y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    info "已取消"
    exit 0
  fi

  rm -f "${target_dir}/.cursor/rules/codeflow-team.mdc"
  rm -rf "${target_dir}/.cursor/skills/idea-to-app"
  rm -rf "${target_dir}/.cursor/agents"

  if [[ -d "${target_dir}/.cursor" ]] && [[ -z "$(ls -A "${target_dir}/.cursor")" ]]; then
    rmdir "${target_dir}/.cursor"
  fi

  success "CodeFlow 已卸载（docs/ 和 src/ 保持不变）"
}

# ─── 命令：update ─────────────────────────────────────────────────────────────
cmd_update() {
  local target_dir="${1:-$(pwd)}"

  if [[ ! -d "${target_dir}/.cursor/agents" ]]; then
    error "当前目录未安装 CodeFlow，请先运行: codeflow init"
    exit 1
  fi

  title "CodeFlow — 更新"
  echo ""
  info "从模板更新 Agent 定义..."
  do_install "$target_dir"
  success "更新完成"
}

# ─── 命令：status ─────────────────────────────────────────────────────────────
cmd_status() {
  local target_dir="${1:-$(pwd)}"

  title "CodeFlow — 状态"
  echo ""

  local installed=true

  check_component() {
    local path="$1"
    local name="$2"
    if [[ -e "${target_dir}/${path}" ]]; then
      echo -e "  ${GREEN}✓${NC} ${name}"
    else
      echo -e "  ${RED}✗${NC} ${name} ${YELLOW}(缺失)${NC}"
      installed=false
    fi
  }

  echo -e "${BOLD}配置文件：${NC}"
  check_component ".cursor/rules/codeflow-team.mdc" "Team Rule"
  check_component ".cursor/skills/idea-to-app/SKILL.md" "Skill: idea-to-app"
  echo ""

  echo -e "${BOLD}Agent 团队：${NC}"
  local agents=(
    "engineering-manager:工程经理"
    "product-manager:产品经理"
    "ux-designer:UX 设计师"
    "backend-architect:后端架构师"
    "frontend-architect:前端架构师"
    "backend-developer:后端开发"
    "frontend-developer:前端开发"
    "fullstack-developer:全栈开发"
    "qa-engineer:测试工程师"
    "security-auditor:安全审计"
    "devops-engineer:DevOps"
    "operations-analyst:运营分析"
  )

  for entry in "${agents[@]}"; do
    local file="${entry%%:*}"
    local label="${entry##*:}"
    check_component ".cursor/agents/${file}.md" "${label} (${file})"
  done

  echo ""
  if [[ "$installed" == true ]]; then
    success "CodeFlow 已完整安装 ✓"
  else
    warn "CodeFlow 安装不完整，请运行: codeflow init"
  fi

  if [[ -f "${target_dir}/docs/project-state.md" ]]; then
    echo ""
    echo -e "${BOLD}项目状态：${NC}"
    local phase
    phase=$(grep "^current_phase:" "${target_dir}/docs/project-state.md" | awk '{print $2}' || echo "未知")
    local name
    name=$(grep "^project_name:" "${target_dir}/docs/project-state.md" | sed 's/project_name: *"\?\([^"]*\)"\?/\1/' || echo "未知")
    echo -e "  项目名称: ${BOLD}${name}${NC}"
    echo -e "  当前阶段: ${BOLD}${phase}${NC}"
  fi

  echo ""
}

# ─── 入口 ────────────────────────────────────────────────────────────────────
main() {
  # 解析全局选项
  local args=()
  for arg in "$@"; do
    case "$arg" in
      --yes|-y) YES_MODE=true ;;
      *) args+=("$arg") ;;
    esac
  done

  local cmd="${args[0]:-help}"
  local rest=("${args[@]:1}")

  case "$cmd" in
    new)       cmd_new "${rest[@]}" ;;
    init)      cmd_init "${rest[@]}" ;;
    uninstall) cmd_uninstall "${rest[@]}" ;;
    update)    cmd_update "${rest[@]}" ;;
    status)    cmd_status "${rest[@]}" ;;
    help|--help|-h) usage ;;
    *)
      error "未知命令: ${cmd}"
      echo ""
      usage
      exit 1
      ;;
  esac
}

main "$@"
