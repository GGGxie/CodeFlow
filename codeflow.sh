#!/usr/bin/env bash
# CodeFlow — 数字研发团队 Agent 系统
# 用法: codeflow <命令> [选项]

set -euo pipefail

# ─── 颜色 ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'
YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# 输出函数只对固定部分解释颜色转义；用户输入一律走 %s，不会被当作转义序列解释。
info()    { printf '%b[CodeFlow]%b %s\n' "$BLUE" "$NC" "$*"; }
success() { printf '%b[✓]%b %s\n' "$GREEN" "$NC" "$*"; }
warn()    { printf '%b[!]%b %s\n' "$YELLOW" "$NC" "$*"; }
error()   { printf '%b[✗]%b %s\n' "$RED" "$NC" "$*" >&2; }
title()   { printf '\n%b%s%b\n' "${BOLD}${CYAN}" "$*" "$NC"; }

# ─── 全局选项 ─────────────────────────────────────────────────────────────────
YES_MODE=false

# ─── 路径 ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"

# ─── 交互输入 ─────────────────────────────────────────────────────────────────
# 确认提示：支持 --yes 跳过；输入结束（EOF）视为拒绝。
confirm_prompt() {
  local prompt="$1"
  local default="${2:-N}"
  local answer=""
  if [[ "$YES_MODE" == true ]]; then
    return 0
  fi
  if ! read -rp "$prompt" answer && [[ -z "$answer" ]]; then
    echo
    return 1
  fi
  if [[ "$default" == "Y" ]]; then
    [[ ! "$answer" =~ ^[Nn]$ ]]
  else
    [[ "$answer" =~ ^[Yy]$ ]]
  fi
}

# 读取一行输入到变量；输入结束时报错退出，避免无限重试。
# 用法: ask <变量名> <提示>
ask() {
  local __line=""
  if ! read -rp "$2" __line && [[ -z "$__line" ]]; then
    echo
    error "输入已结束"
    exit 1
  fi
  printf -v "$1" '%s' "$__line"
}

# ─── 帮助信息 ────────────────────────────────────────────────────────────────
usage() {
  echo -e "${BOLD}CodeFlow${NC} — 数字研发团队 Agent 系统\n"
  echo "用法: codeflow [选项] <命令>"
  echo ""
  echo "命令:"
  echo "  new         新建项目：输入项目名和想法，初始化团队配置"
  echo "  init        在当前目录初始化 CodeFlow 团队配置"
  echo "  uninstall   移除当前目录的 CodeFlow 配置（保留 docs/、src/ 和你自己的 Agent）"
  echo "  update      更新 Agent 定义到最新版本"
  echo "  status      查看当前目录的 CodeFlow 安装状态"
  echo "  help        显示此帮助信息"
  echo ""
  echo "选项:"
  echo "  -y, --yes   跳过所有确认提示（默认回答\"是\"）"
  echo ""
  echo "文件保护:"
  echo "  init/update/uninstall 会在覆盖或删除被修改过的同名文件前，"
  echo "  先备份到 .cursor/.codeflow-backup/<时间戳>/"
  echo ""
  echo "工作模式:"
  echo "  fast-track  简单项目（≤5 核心功能），4 阶段快速交付"
  echo "  standard    标准项目（>5 核心功能），完整 5+ 阶段流程"
  echo ""
  echo "示例:"
  echo "  codeflow new                      # 新建项目"
  echo "  cd my-project && codeflow init    # 在已有目录初始化"
}

# ─── 清单：CodeFlow 管理的文件（单一事实来源：templates/）─────────────────────
# MANIFEST_SRC[i] 是相对 templates/ 的源文件，MANIFEST_REL[i] 是相对项目根目录的目标文件。
# Agent 列表直接来自 templates/agents/*.md，不再硬编码。
MANIFEST_SRC=()
MANIFEST_REL=()
MANIFEST_AGENTS=()

build_manifest() {
  if [[ ! -d "$TEMPLATES_DIR" ]]; then
    error "找不到模板目录: ${TEMPLATES_DIR}"
    error "请确保在 CodeFlow 仓库根目录下运行此脚本"
    exit 1
  fi

  MANIFEST_SRC=("rules/codeflow-team.mdc" "skills/idea-to-app/SKILL.md")
  MANIFEST_REL=(".cursor/rules/codeflow-team.mdc" ".cursor/skills/idea-to-app/SKILL.md")
  MANIFEST_AGENTS=()

  local f name
  for f in "${TEMPLATES_DIR}"/agents/*.md; do
    [[ -f "$f" ]] || continue
    name="${f##*/}"
    MANIFEST_SRC+=("agents/${name}")
    MANIFEST_REL+=(".cursor/agents/${name}")
    MANIFEST_AGENTS+=("${name%.md}")
  done

  if [[ ${#MANIFEST_AGENTS[@]} -eq 0 ]]; then
    error "模板目录中没有 Agent 定义: ${TEMPLATES_DIR}/agents/*.md"
    exit 1
  fi

  local src
  for src in "${MANIFEST_SRC[@]}"; do
    if [[ ! -f "${TEMPLATES_DIR}/${src}" ]]; then
      error "缺少模板文件: ${TEMPLATES_DIR}/${src}"
      exit 1
    fi
  done
}

# ─── 备份 ────────────────────────────────────────────────────────────────────
# 被覆盖/删除前的文件备份到 <项目>/.cursor/.codeflow-backup/<时间戳>/<相对 .cursor 的路径>
BACKUP_ROOT=""

make_backup_root() {
  local target_dir="$1"
  local base="${target_dir}/.cursor/.codeflow-backup"
  local ts candidate n=0
  ts="$(date '+%Y%m%d-%H%M%S')"
  candidate="${base}/${ts}"
  while [[ -e "$candidate" ]]; do
    n=$((n + 1))
    candidate="${base}/${ts}-${n}"
  done
  mkdir -p "$candidate"
  BACKUP_ROOT="$candidate"
}

# 用法: backup_file <项目根目录> <相对路径，如 .cursor/agents/x.md>
backup_file() {
  local target_dir="$1"
  local rel="$2"
  if [[ -z "$BACKUP_ROOT" ]]; then
    make_backup_root "$target_dir"
  fi
  local dest="${BACKUP_ROOT}/${rel#.cursor/}"
  if ! { mkdir -p "$(dirname "$dest")" && cp -p "${target_dir}/${rel}" "$dest"; }; then
    error "备份失败，已中止（未修改任何文件）: ${rel}"
    exit 1
  fi
  echo "  备份: ${rel} → ${dest}"
}

# ─── 安装核心 ────────────────────────────────────────────────────────────────
do_install() {
  local target_dir="$1"
  local i rel src dest
  local conflicts=()

  build_manifest
  BACKUP_ROOT=""

  # 找出"已存在且与内置版本不同"的文件（内容相同的文件无需备份）
  for i in "${!MANIFEST_REL[@]}"; do
    rel="${MANIFEST_REL[$i]}"
    src="${TEMPLATES_DIR}/${MANIFEST_SRC[$i]}"
    dest="${target_dir}/${rel}"
    if [[ -d "$dest" && ! -L "$dest" ]]; then
      error "目标路径是目录，无法写入文件: ${dest}"
      exit 1
    fi
    if [[ -e "$dest" || -L "$dest" ]] && ! cmp -s "$src" "$dest"; then
      conflicts+=("$i")
    fi
  done

  if [[ ${#conflicts[@]} -gt 0 ]]; then
    warn "以下文件已存在且与内置版本不同，覆盖前会先备份："
    for i in "${conflicts[@]}"; do
      echo "  - ${MANIFEST_REL[$i]}"
    done
    if ! confirm_prompt "是否备份并覆盖？(y/N): " "N"; then
      info "已取消安装（未修改任何文件）"
      exit 0
    fi
    for i in "${conflicts[@]}"; do
      backup_file "$target_dir" "${MANIFEST_REL[$i]}"
    done
    info "已备份 ${#conflicts[@]} 个文件到: ${BACKUP_ROOT}"
  fi

  info "正在安装 CodeFlow 团队配置..."

  mkdir -p "${target_dir}/.cursor/agents"
  mkdir -p "${target_dir}/.cursor/rules"
  mkdir -p "${target_dir}/.cursor/skills/idea-to-app"

  for i in "${!MANIFEST_REL[@]}"; do
    rel="${MANIFEST_REL[$i]}"
    cp "${TEMPLATES_DIR}/${MANIFEST_SRC[$i]}" "${target_dir}/${rel}"
    case "$rel" in
      .cursor/rules/*)  success "团队规范 (${rel})" ;;
      .cursor/skills/*) success "全流程技能 (${rel})" ;;
      *)                success "Agent: $(basename "$rel" .md)" ;;
    esac
  done

  mkdir -p "${target_dir}/docs"

  echo
  success "CodeFlow 安装完成！"
}

# ─── new 的辅助函数 ───────────────────────────────────────────────────────────
# 项目名校验：用作目录名，拒绝路径分隔符、./..、前导 -、换行与控制字符。
validate_project_name() {
  local name="$1"
  if [[ "$name" == *[[:cntrl:]]* ]]; then
    warn "项目名称无效：不能包含换行或其它控制字符"
    return 1
  fi
  if [[ "$name" == "." || "$name" == ".." ]]; then
    warn "项目名称无效：不能是 . 或 .."
    return 1
  fi
  if [[ "$name" == */* ]]; then
    warn "项目名称无效：不能包含 /"
    return 1
  fi
  if [[ "$name" == -* ]]; then
    warn "项目名称无效：不能以 - 开头"
    return 1
  fi
  if [[ ${#name} -lt 2 ]]; then
    warn "项目名称无效：名称至少 2 个字符"
    return 1
  fi
  return 0
}

# 转义为 YAML 双引号标量的内容（不含外层引号）
yaml_escape() {
  local s="$1"
  local bs='\' dq='"'
  s="${s//"$bs"/"$bs$bs"}"
  s="${s//"$dq"/"$bs$dq"}"
  s="${s//$'\n'/"${bs}n"}"
  s="${s//$'\r'/"${bs}r"}"
  s="${s//$'\t'/"${bs}t"}"
  printf '%s' "$s"
}

# 向 .gitignore 追加缺失的条目（保留已有内容，不重复）
ensure_gitignore() {
  local file="$1"
  local entries=("node_modules/" ".env" ".env.local" "dist/" "build/" "*.log" ".DS_Store")
  local entry added=0

  for entry in "${entries[@]}"; do
    if [[ -f "$file" ]] && grep -qxF -- "$entry" "$file"; then
      continue
    fi
    # 已有文件末尾没有换行时先补一个，避免和上一行粘在一起
    if [[ -s "$file" && -n "$(tail -c1 "$file")" ]]; then
      printf '\n' >> "$file"
    fi
    printf '%s\n' "$entry" >> "$file"
    added=$((added + 1))
  done

  if [[ $added -gt 0 ]]; then
    success ".gitignore 已追加 ${added} 条忽略规则"
  else
    info ".gitignore 已包含所需规则"
  fi
}

# 只提交 CodeFlow 相关路径，不使用 git add -A，避免把目录中其它文件（可能含密钥）带进提交
commit_codeflow_files() {
  local dir="$1"
  local paths=(.cursor docs .gitignore)

  if ! git -C "$dir" add -- "${paths[@]}"; then
    warn "git add 失败（可能被 .gitignore 忽略），已跳过提交，请手动检查"
    return 0
  fi
  if git -C "$dir" diff --cached --quiet -- "${paths[@]}"; then
    info "没有需要提交的变更"
    return 0
  fi
  # 带路径提交：用户已暂存的其它文件不会被包含进来
  if git -C "$dir" commit -q -m "chore: initialize CodeFlow project" -- "${paths[@]}"; then
    success "已提交 CodeFlow 配置（仅 .cursor、docs、.gitignore）"
  else
    warn "git commit 失败（可能未配置 user.name / user.email），请手动提交"
  fi
}

# ─── 命令：new ────────────────────────────────────────────────────────────────
cmd_new() {
  title "CodeFlow — 新建项目"
  echo ""

  # 确定父目录
  local parent_dir="${HOME}/Document"
  local custom_dir=""
  ask custom_dir "项目将创建在哪个目录下？[${parent_dir}]: "
  if [[ -n "$custom_dir" ]]; then
    parent_dir="$custom_dir"
  fi
  mkdir -p -- "$parent_dir"

  # 输入项目名
  echo ""
  local project_name
  while true; do
    ask project_name "项目名称: "
    # 去除首尾空白（不使用 echo，避免名称被当作选项/转义解释）
    project_name="${project_name#"${project_name%%[![:space:]]*}"}"
    project_name="${project_name%"${project_name##*[![:space:]]}"}"
    if validate_project_name "$project_name"; then
      break
    fi
  done

  # 检查目录冲突
  local project_dir="${parent_dir}/${project_name}"
  if [[ -e "$project_dir" && ! -d "$project_dir" ]]; then
    error "路径已存在且不是目录: ${project_dir}"
    exit 1
  fi
  if [[ -d "$project_dir" ]]; then
    warn "目录已存在: ${project_dir}"
    echo "  已有文件不会被覆盖；被修改过的同名 CodeFlow 文件会先备份。"
    if ! confirm_prompt "是否继续在该目录初始化 CodeFlow？(y/N): " "N"; then
      info "已取消"
      exit 0
    fi
  fi

  # 采集想法
  echo ""
  printf '%b请用一句话描述你的产品想法：%b\n' "$BOLD" "$NC"
  printf '%b（例如：一个帮助远程团队追踪每日目标的 SaaS 工具）%b\n' "$YELLOW" "$NC"
  echo ""
  local idea=""
  ask idea "> "
  if [[ -z "$idea" ]]; then
    error "想法不能为空"
    exit 1
  fi

  # 确认
  echo ""
  title "确认信息"
  printf '  项目名称: %b%s%b\n' "$BOLD" "$project_name" "$NC"
  printf '  项目路径: %b%s%b\n' "$BOLD" "$project_dir" "$NC"
  printf '  产品想法: %s\n' "$idea"
  echo ""
  if ! confirm_prompt "确认创建？(Y/n): " "Y"; then
    info "已取消"
    exit 0
  fi

  # 创建目录并安装
  mkdir -p -- "$project_dir"
  do_install "$project_dir"

  # 写入初始 project-state.md（完整 phases 结构，与 engineering-manager 期望格式一致）
  # 已存在时不覆盖，避免丢失旧的项目状态。
  local state_file="${project_dir}/docs/project-state.md"
  if [[ -e "$state_file" ]]; then
    warn "docs/project-state.md 已存在，已跳过（未覆盖）"
  else
    local now name_yaml idea_yaml
    now=$(date '+%Y-%m-%d %H:%M')
    name_yaml="$(yaml_escape "$project_name")"
    idea_yaml="$(yaml_escape "$idea")"
    cat > "$state_file" << STATEOF
project_name: "${name_yaml}"
current_phase: discovery
idea: "${idea_yaml}"
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
    detail: "用户想法：${idea_yaml}"
STATEOF
    success "项目状态文档已创建 (docs/project-state.md)"
  fi

  # 初始化 git
  if command -v git &>/dev/null; then
    if [[ -e "${project_dir}/.git" ]]; then
      info "检测到已有 Git 仓库，跳过 git init"
    else
      git -C "$project_dir" init -q
      success "Git 仓库已初始化"
    fi
    ensure_gitignore "${project_dir}/.gitignore"
    commit_codeflow_files "$project_dir"
  else
    warn "未检测到 git，已跳过 Git 初始化"
  fi

  # 完成提示
  echo ""
  title "准备就绪！"
  echo ""
  printf '  项目路径: %b%s%b\n' "$BOLD" "$project_dir" "$NC"
  echo ""
  printf '  %b下一步：%b\n' "$BOLD" "$NC"
  printf '  1. 在 Cursor 中打开项目目录\n'
  printf '  2. 在对话框中输入：%b开始%b\n' "$BOLD" "$NC"
  printf '  3. 工程经理将自动协调团队为你生成完整应用\n'
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
  printf '  %b下一步：%b\n' "$BOLD" "$NC"
  printf '  在 Cursor 中打开此目录，输入 %b开始%b 启动团队协作\n' "$BOLD" "$NC"
}

# ─── 命令：uninstall ──────────────────────────────────────────────────────────
cmd_uninstall() {
  local target_dir="${1:-$(pwd)}"
  local i rel src dest
  local existing=()

  build_manifest
  BACKUP_ROOT=""

  title "CodeFlow — 卸载"
  echo ""

  for i in "${!MANIFEST_REL[@]}"; do
    dest="${target_dir}/${MANIFEST_REL[$i]}"
    if [[ ( -e "$dest" || -L "$dest" ) && ! ( -d "$dest" && ! -L "$dest" ) ]]; then
      existing+=("$i")
    fi
  done

  if [[ ${#existing[@]} -eq 0 ]]; then
    warn "当前目录未安装 CodeFlow"
    exit 0
  fi

  warn "将删除以下 CodeFlow 文件（docs/、src/ 以及你自己的其它 Agent、规则、技能不受影响）："
  echo ""
  for i in "${existing[@]}"; do
    rel="${MANIFEST_REL[$i]}"
    if cmp -s "${TEMPLATES_DIR}/${MANIFEST_SRC[$i]}" "${target_dir}/${rel}"; then
      echo "  - ${rel}"
    else
      echo "  - ${rel}  (已修改，删除前会先备份)"
    fi
  done

  echo ""
  if ! confirm_prompt "确认卸载？(y/N): " "N"; then
    info "已取消"
    exit 0
  fi

  # 先备份被修改过的文件，全部备份成功后才开始删除
  local backed_up=0
  for i in "${existing[@]}"; do
    rel="${MANIFEST_REL[$i]}"
    if ! cmp -s "${TEMPLATES_DIR}/${MANIFEST_SRC[$i]}" "${target_dir}/${rel}"; then
      backup_file "$target_dir" "$rel"
      backed_up=$((backed_up + 1))
    fi
  done
  if [[ $backed_up -gt 0 ]]; then
    info "已备份 ${backed_up} 个修改过的文件到: ${BACKUP_ROOT}"
  fi

  for i in "${existing[@]}"; do
    rm -f -- "${target_dir}/${MANIFEST_REL[$i]}"
  done

  # 仅删除变空的目录（rmdir 遇到非空目录会失败，保留用户文件）
  local d
  for d in .cursor/agents .cursor/skills/idea-to-app .cursor/skills .cursor/rules .cursor; do
    rmdir -- "${target_dir}/${d}" 2>/dev/null || true
  done

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
# 从 Agent 模板的 description 里取简短中文名（"CodeFlow 后端架构师。……" → "后端架构师"）
agent_label() {
  local raw=""
  raw="$(sed -n 's/^description:[[:space:]]*//p' "$1" | head -n 1)" || true
  if [[ "$raw" == *。* ]]; then
    raw="${raw%%。*}"
    printf '%s' "${raw#CodeFlow }"
  fi
}

cmd_status() {
  local target_dir="${1:-$(pwd)}"

  build_manifest

  title "CodeFlow — 状态"
  echo ""

  local installed=true

  check_component() {
    local path="$1"
    local name="$2"
    if [[ -e "${target_dir}/${path}" ]]; then
      printf '  %b✓%b %s\n' "$GREEN" "$NC" "$name"
    else
      printf '  %b✗%b %s %b(缺失)%b\n' "$RED" "$NC" "$name" "$YELLOW" "$NC"
      installed=false
    fi
  }

  printf '%b配置文件：%b\n' "$BOLD" "$NC"
  check_component ".cursor/rules/codeflow-team.mdc" "Team Rule"
  check_component ".cursor/skills/idea-to-app/SKILL.md" "Skill: idea-to-app"
  echo ""

  printf '%bAgent 团队：%b\n' "$BOLD" "$NC"
  local agent label
  for agent in "${MANIFEST_AGENTS[@]}"; do
    label="$(agent_label "${TEMPLATES_DIR}/agents/${agent}.md")"
    if [[ -n "$label" ]]; then
      check_component ".cursor/agents/${agent}.md" "${label} (${agent})"
    else
      check_component ".cursor/agents/${agent}.md" "${agent}"
    fi
  done

  echo ""
  if [[ "$installed" == true ]]; then
    success "CodeFlow 已完整安装 ✓"
  else
    warn "CodeFlow 安装不完整，请运行: codeflow init"
  fi

  if [[ -f "${target_dir}/docs/project-state.md" ]]; then
    echo ""
    printf '%b项目状态：%b\n' "$BOLD" "$NC"
    local phase name
    phase=$(grep "^current_phase:" "${target_dir}/docs/project-state.md" | awk '{print $2}' || echo "未知")
    name=$(grep "^project_name:" "${target_dir}/docs/project-state.md" | sed 's/project_name: *"\?\([^"]*\)"\?/\1/' || echo "未知")
    printf '  项目名称: %b%s%b\n' "$BOLD" "$name" "$NC"
    printf '  当前阶段: %b%s%b\n' "$BOLD" "$phase" "$NC"
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

# 仅在直接执行时运行 main；被 source（如测试）时只加载函数。
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
