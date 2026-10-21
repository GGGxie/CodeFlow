#!/usr/bin/env bash
# CodeFlow 测试（纯 bash，无外部依赖）
#
# 用法: bash tests/run.sh [名称过滤]
#
# 安全约定：
#   - 每个用例在 mktemp -d 创建的临时目录中运行，HOME 指向其中的 home/；
#   - 每次调用 codeflow.sh 前都会检查 cwd 与 HOME 位于沙箱内，否则立即中止；
#   - 用 PATH 前置的假 cursor 命令避免真的启动编辑器；
#   - 清理使用 rm -r（不带 -f）。

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEFLOW="${ROOT}/codeflow.sh"
TEMPLATES="${ROOT}/templates"
EXPECTED_AGENT_COUNT=12
FILTER="${1:-}"

# ─── 沙箱 ─────────────────────────────────────────────────────────────────────
SANDBOX=""
SANDBOX_PREFIX="${TMPDIR:-/tmp}/codeflow-test."
OUT=""
RC=0
CF_SCRIPT="$CODEFLOW"
T_FAILS=0

setup_sandbox() {
  SANDBOX="$(mktemp -d "${SANDBOX_PREFIX}XXXXXX")" || exit 99
  export HOME="${SANDBOX}/home"
  mkdir -p "$HOME" "${SANDBOX}/work" "${SANDBOX}/bin"
  # 假 cursor：只记录调用，不启动任何东西
  printf '#!/bin/sh\necho "$@" >> "%s/cursor.log"\n' "$SANDBOX" > "${SANDBOX}/bin/cursor"
  chmod +x "${SANDBOX}/bin/cursor"
  export PATH="${SANDBOX}/bin:${PATH}"
  export XDG_CONFIG_HOME="${HOME}/.config"
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME="CodeFlow Test" GIT_AUTHOR_EMAIL="test@example.invalid"
  export GIT_COMMITTER_NAME="CodeFlow Test" GIT_COMMITTER_EMAIL="test@example.invalid"
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  cd "${SANDBOX}/work" || exit 99
}

cleanup_sandbox() {
  case "$SANDBOX" in
    "${SANDBOX_PREFIX}"?*)
      cd / && rm -r "$SANDBOX" </dev/null
      ;;
  esac
}

guard() {
  case "$PWD/" in
    "${SANDBOX}/"*) ;;
    *) echo "FATAL: cwd outside sandbox: $PWD" >&2; exit 99 ;;
  esac
  if [[ "$HOME" != "${SANDBOX}/home" ]]; then
    echo "FATAL: HOME is not redirected: $HOME" >&2
    exit 99
  fi
}

# cf <args...>        stdin 为空
# cf_in <text> <args> stdin 来自 here-string
cf() {
  guard
  OUT="$(bash "$CF_SCRIPT" "$@" </dev/null 2>&1)"
  RC=$?
}
cf_in() {
  local input="$1"; shift
  guard
  OUT="$(bash "$CF_SCRIPT" "$@" <<<"$input" 2>&1)"
  RC=$?
}
feed() { printf '%s\n' "$@"; }

# ─── 断言 ─────────────────────────────────────────────────────────────────────
fail() { printf '    ✗ %s\n' "$*"; T_FAILS=$((T_FAILS + 1)); }

assert_eq()           { [[ "$1" == "$2" ]] || fail "$3: expected [$2], got [$1]"; }
assert_rc()           { [[ "$RC" -eq "$1" ]] || fail "$2: expected exit $1, got $RC"; }
assert_rc_nonzero()   { [[ "$RC" -ne 0 ]] || fail "$1: expected non-zero exit"; }
assert_contains()     { [[ "$1" == *"$2"* ]] || fail "$3: missing [$2]"; }
assert_not_contains() { [[ "$1" != *"$2"* ]] || fail "$3: unexpected [$2]"; }
assert_exists()       { [[ -e "$1" ]] || fail "missing: ${1#"${SANDBOX}"/}"; }
assert_absent()       { [[ ! -e "$1" && ! -L "$1" ]] || fail "should not exist: ${1#"${SANDBOX}"/}"; }
assert_same()         { cmp -s "$1" "$2" || fail "${3:-content differs}: $1 vs $2"; }

template_agents() {
  local f
  for f in "${TEMPLATES}"/agents/*.md; do
    f="${f##*/}"
    printf '%s\n' "${f%.md}"
  done
}

count_files() { find "$1" -type f | wc -l | tr -d ' '; }

# 断言 git 仓库中被跟踪的文件只来自 .cursor / docs / .gitignore
assert_only_allowed_tracked() {
  local dir="$1" f bad=""
  while IFS= read -r f; do
    case "$f" in
      .cursor/*|docs/*|.gitignore) ;;
      *) bad+=" ${f}" ;;
    esac
  done < <(git -C "$dir" ls-files)
  [[ -z "$bad" ]] || fail "unexpected tracked files:${bad}"
}

# 取唯一的备份目录（相对路径，无尾部斜杠）
BACKUP_DIR=""
find_single_backup() {
  shopt -s nullglob
  local dirs=(.cursor/.codeflow-backup/*/)
  shopt -u nullglob
  assert_eq "${#dirs[@]}" 1 "number of backup dirs"
  BACKUP_DIR="${dirs[0]:-.cursor/.codeflow-backup/MISSING}"
  BACKUP_DIR="${BACKUP_DIR%/}"
}

# ═════════════════════════════════════════════════════════════════════════════
# 1. 安装（init / update）
# ═════════════════════════════════════════════════════════════════════════════

t_init_empty_dir_installs_rule_skill_and_all_agents() {
  cf init
  assert_rc 0 "init"
  assert_same "${TEMPLATES}/rules/codeflow-team.mdc" .cursor/rules/codeflow-team.mdc "rule"
  assert_same "${TEMPLATES}/skills/idea-to-app/SKILL.md" .cursor/skills/idea-to-app/SKILL.md "skill"
  local a n=0
  for a in $(template_agents); do
    assert_same "${TEMPLATES}/agents/${a}.md" ".cursor/agents/${a}.md" "agent ${a}"
    n=$((n + 1))
  done
  assert_eq "$n" "$EXPECTED_AGENT_COUNT" "agent templates"
  assert_eq "$(count_files .cursor/agents)" "$EXPECTED_AGENT_COUNT" "installed agents"
  assert_exists docs
  assert_absent .cursor/.codeflow-backup
}

t_init_keeps_user_custom_agent() {
  mkdir -p .cursor/agents
  printf 'my own agent\n' > .cursor/agents/my-agent.md
  cf init
  assert_rc 0 "init"
  assert_eq "$(cat .cursor/agents/my-agent.md)" "my own agent" "custom agent content"
  assert_eq "$(count_files .cursor/agents)" "$((EXPECTED_AGENT_COUNT + 1))" "agents incl. custom"
  assert_absent .cursor/.codeflow-backup
}

t_init_twice_is_idempotent_without_backup_or_prompt() {
  cf init
  cf init
  assert_rc 0 "second init (no stdin)"
  assert_absent .cursor/.codeflow-backup
}

t_init_backs_up_modified_agent_and_prints_path() {
  cf init
  printf 'my edited qa\n' > .cursor/agents/qa-engineer.md
  cf_in "y" init
  assert_rc 0 "init"
  find_single_backup
  assert_eq "$(cat "${BACKUP_DIR}/agents/qa-engineer.md")" "my edited qa" "backed-up content"
  assert_same "${TEMPLATES}/agents/qa-engineer.md" .cursor/agents/qa-engineer.md "agent restored from template"
  assert_eq "$(count_files "$BACKUP_DIR")" 1 "only the modified file is backed up"
  assert_contains "$OUT" "${PWD}/${BACKUP_DIR}" "printed backup path"
  [[ "${BACKUP_DIR##*/}" =~ ^[0-9]{8}-[0-9]{6} ]] || fail "backup dir is not timestamped: ${BACKUP_DIR}"
}

t_init_backs_up_when_only_user_rule_exists() {
  mkdir -p .cursor/rules
  printf 'my rule\n' > .cursor/rules/codeflow-team.mdc
  cf_in "y" init
  assert_rc 0 "init"
  find_single_backup
  assert_eq "$(cat "${BACKUP_DIR}/rules/codeflow-team.mdc")" "my rule" "backed-up rule"
  assert_same "${TEMPLATES}/rules/codeflow-team.mdc" .cursor/rules/codeflow-team.mdc "rule installed"
  assert_contains "$OUT" "${PWD}/${BACKUP_DIR}" "printed backup path"
}

t_init_backs_up_when_only_user_skill_exists() {
  mkdir -p .cursor/skills/idea-to-app
  printf 'my skill\n' > .cursor/skills/idea-to-app/SKILL.md
  cf_in "y" init
  assert_rc 0 "init"
  find_single_backup
  assert_eq "$(cat "${BACKUP_DIR}/skills/idea-to-app/SKILL.md")" "my skill" "backed-up skill"
  assert_same "${TEMPLATES}/skills/idea-to-app/SKILL.md" .cursor/skills/idea-to-app/SKILL.md "skill installed"
}

t_init_decline_leaves_everything_untouched() {
  mkdir -p .cursor/rules
  printf 'my rule\n' > .cursor/rules/codeflow-team.mdc
  cf_in "n" init
  assert_rc 0 "declined init"
  assert_eq "$(cat .cursor/rules/codeflow-team.mdc)" "my rule" "rule untouched"
  assert_absent .cursor/agents
  assert_absent .cursor/.codeflow-backup
}

t_init_without_answer_does_not_overwrite_user_rule() {
  mkdir -p .cursor/rules
  printf 'my rule\n' > .cursor/rules/codeflow-team.mdc
  cf init
  assert_eq "$(cat .cursor/rules/codeflow-team.mdc)" "my rule" "rule untouched when stdin is closed"
  assert_absent .cursor/.codeflow-backup
}

t_init_yes_flag_backs_up_without_prompt() {
  mkdir -p .cursor/rules
  printf 'my rule\n' > .cursor/rules/codeflow-team.mdc
  cf --yes init
  assert_rc 0 "init --yes"
  find_single_backup
  assert_eq "$(cat "${BACKUP_DIR}/rules/codeflow-team.mdc")" "my rule" "backed-up rule"
  assert_same "${TEMPLATES}/rules/codeflow-team.mdc" .cursor/rules/codeflow-team.mdc "rule installed"
}

t_update_backs_up_modified_agent() {
  cf init
  printf 'edited\n' > .cursor/agents/ux-designer.md
  cf_in "y" update
  assert_rc 0 "update"
  find_single_backup
  assert_eq "$(cat "${BACKUP_DIR}/agents/ux-designer.md")" "edited" "backed-up agent"
  assert_same "${TEMPLATES}/agents/ux-designer.md" .cursor/agents/ux-designer.md "agent updated"
}

t_update_requires_existing_install() {
  cf update
  assert_rc 1 "update on empty dir"
  assert_absent .cursor
}

# ═════════════════════════════════════════════════════════════════════════════
# 2. 卸载
# ═════════════════════════════════════════════════════════════════════════════

t_uninstall_removes_only_codeflow_files() {
  cf init
  mkdir -p .cursor/skills/other
  printf 'mine\n' > .cursor/agents/my-agent.md
  printf 'mine\n' > .cursor/rules/mine.mdc
  printf 'mine\n' > .cursor/skills/other/SKILL.md
  mkdir -p src
  printf 'keep\n' > docs/notes.md
  printf 'keep\n' > src/app.js
  cf_in "y" uninstall
  assert_rc 0 "uninstall"
  local a
  for a in $(template_agents); do assert_absent ".cursor/agents/${a}.md"; done
  assert_absent .cursor/rules/codeflow-team.mdc
  assert_absent .cursor/skills/idea-to-app
  assert_eq "$(cat .cursor/agents/my-agent.md)" "mine" "custom agent kept"
  assert_eq "$(cat .cursor/rules/mine.mdc)" "mine" "custom rule kept"
  assert_eq "$(cat .cursor/skills/other/SKILL.md)" "mine" "custom skill kept"
  assert_exists docs/notes.md
  assert_exists src/app.js
}

t_uninstall_keeps_files_added_inside_codeflow_skill_dir() {
  cf init
  printf 'extra\n' > .cursor/skills/idea-to-app/notes.md
  cf_in "y" uninstall
  assert_absent .cursor/skills/idea-to-app/SKILL.md
  assert_eq "$(cat .cursor/skills/idea-to-app/notes.md)" "extra" "extra file in skill dir kept"
}

t_uninstall_removes_empty_dirs() {
  cf init
  cf_in "y" uninstall
  assert_rc 0 "uninstall"
  assert_absent .cursor
  assert_exists docs
}

t_uninstall_yes_flag_skips_prompt() {
  cf init
  cf --yes uninstall
  assert_rc 0 "uninstall --yes with closed stdin"
  assert_absent .cursor
}

t_uninstall_decline_keeps_everything() {
  cf init
  cf_in "n" uninstall
  assert_rc 0 "declined uninstall"
  assert_eq "$(count_files .cursor/agents)" "$EXPECTED_AGENT_COUNT" "agents kept"
  assert_exists .cursor/rules/codeflow-team.mdc
  assert_exists .cursor/skills/idea-to-app/SKILL.md
}

t_uninstall_without_answer_keeps_everything() {
  cf init
  cf uninstall
  assert_eq "$(count_files .cursor/agents)" "$EXPECTED_AGENT_COUNT" "agents kept when stdin is closed"
}

t_uninstall_when_only_user_agents_exist_is_noop() {
  mkdir -p .cursor/agents
  printf 'mine\n' > .cursor/agents/my-agent.md
  cf --yes uninstall
  assert_rc 0 "uninstall"
  assert_contains "$OUT" "未安装" "not-installed message"
  assert_eq "$(cat .cursor/agents/my-agent.md)" "mine" "custom agent kept"
}

t_uninstall_backs_up_modified_files_before_deleting() {
  cf init
  printf 'my tuned manager\n' > .cursor/agents/engineering-manager.md
  cf --yes uninstall
  assert_rc 0 "uninstall"
  find_single_backup
  assert_eq "$(cat "${BACKUP_DIR}/agents/engineering-manager.md")" "my tuned manager" "backed-up agent"
  assert_absent .cursor/agents/engineering-manager.md
  assert_contains "$OUT" "${PWD}/${BACKUP_DIR}" "printed backup path"
  assert_eq "$(count_files "$BACKUP_DIR")" 1 "only the modified file is backed up"
}

# ═════════════════════════════════════════════════════════════════════════════
# 3. new：已有目录、git、提交范围
# ═════════════════════════════════════════════════════════════════════════════

t_new_creates_project_with_single_clean_commit() {
  local P="${PWD}/projects" D="${PWD}/projects/demo"
  cf_in "$(feed "$P" demo "a todo app" y n)" new
  assert_rc 0 "new"
  assert_exists "${D}/docs/project-state.md"
  assert_exists "${D}/.git"
  assert_eq "$(git -C "$D" rev-list --count HEAD)" 1 "commit count"
  assert_only_allowed_tracked "$D"
  assert_eq "$(git -C "$D" status --porcelain)" "" "clean tree after commit"
  assert_eq "$(grep -c '^project_name: "demo"$' "${D}/docs/project-state.md")" 1 "project_name line"
}

t_new_yes_flag_skips_confirmations() {
  local P="${PWD}/projects"
  cf_in "$(feed "$P" demo "a todo app")" --yes new
  assert_rc 0 "new --yes"
  assert_exists "${P}/demo/docs/project-state.md"
}

t_new_in_existing_dir_preserves_user_files_and_does_not_commit_secrets() {
  local P="${PWD}/projects" D="${PWD}/projects/legacy" state
  mkdir -p "${D}/docs" "${D}/src"
  printf 'my-private/\n*.pem\n' > "${D}/.gitignore"
  printf 'current_phase: implementation\nnote: keep me\n' > "${D}/docs/project-state.md"
  printf 'TOPSECRET\n' > "${D}/secret.txt"
  printf 'API_KEY=abc\n' > "${D}/.env"
  printf 'console.log(1)\n' > "${D}/src/app.js"
  state="$(cat "${D}/docs/project-state.md")"

  cf_in "$(feed "$P" legacy y "some idea" y n)" new
  assert_rc 0 "new in existing dir"

  assert_eq "$(cat "${D}/docs/project-state.md")" "$state" "existing project-state.md untouched"
  assert_contains "$OUT" "docs/project-state.md" "skip notice mentions the file"
  assert_contains "$OUT" "已存在" "skip notice"

  local line
  for line in 'my-private/' '*.pem' '.env' 'node_modules/' '.env.local' '*.log'; do
    assert_eq "$(grep -cxF -- "$line" "${D}/.gitignore")" 1 ".gitignore has [${line}] exactly once"
  done

  assert_eq "$(git -C "$D" rev-list --count HEAD)" 1 "commit count"
  assert_only_allowed_tracked "$D"
  assert_eq "$(git -C "$D" ls-files secret.txt .env src | wc -l | tr -d ' ')" 0 "secrets/src not tracked"
  assert_contains "$(git -C "$D" status --porcelain)" "?? secret.txt" "secret.txt stays untracked"
  assert_eq "$(cat "${D}/secret.txt")" "TOPSECRET" "secret.txt content"
  assert_eq "$(cat "${D}/.env")" "API_KEY=abc" ".env content"
}

t_new_appends_to_gitignore_without_trailing_newline_and_is_idempotent() {
  local P="${PWD}/projects" D="${PWD}/projects/proj"
  mkdir -p "$D"
  printf 'foo' > "${D}/.gitignore"
  cf_in "$(feed "$P" proj y idea y n)" new
  assert_rc 0 "first new"
  assert_eq "$(grep -cxF -- foo "${D}/.gitignore")" 1 "original line kept intact"
  assert_eq "$(grep -cxF -- 'node_modules/' "${D}/.gitignore")" 1 "node_modules/ on its own line"

  cf_in "$(feed "$P" proj y idea y n)" new
  assert_rc 0 "second new"
  assert_eq "$(grep -cxF -- 'node_modules/' "${D}/.gitignore")" 1 "no duplicate entries"
  assert_eq "$(grep -cxF -- '.env' "${D}/.gitignore")" 1 "no duplicate .env"
  assert_eq "$(git -C "$D" rev-list --count HEAD)" 1 "no empty second commit"
}

t_new_in_existing_git_repo_does_not_reinit_or_commit_staged_files() {
  local P="${PWD}/projects" D="${PWD}/projects/existing" first
  mkdir -p "$D"
  git -C "$D" init -q
  printf 'hello\n' > "${D}/README.txt"
  git -C "$D" add README.txt
  git -C "$D" commit -q -m "user first commit"
  first="$(git -C "$D" rev-parse HEAD)"
  printf 'staged\n' > "${D}/staged.txt"
  git -C "$D" add staged.txt
  printf 'secret\n' > "${D}/secret.txt"

  cf_in "$(feed "$P" existing y idea y n)" new
  assert_rc 0 "new in existing repo"
  assert_not_contains "$OUT" "Git 仓库已初始化" "must not report re-init"
  assert_contains "$OUT" "已有 Git 仓库" "existing repo notice"
  assert_eq "$(git -C "$D" rev-list --count HEAD)" 2 "commit count"
  assert_eq "$(git -C "$D" rev-parse HEAD~1)" "$first" "user history preserved"
  local files
  files="$(git -C "$D" show --name-only --format= HEAD)"
  assert_not_contains "$files" "staged.txt" "pre-staged user file not swept into commit"
  assert_not_contains "$files" "secret.txt" "secret not committed"
  assert_contains "$(git -C "$D" diff --cached --name-only)" "staged.txt" "user's staged file still staged"
}

# ═════════════════════════════════════════════════════════════════════════════
# 4. 输入校验与转义
# ═════════════════════════════════════════════════════════════════════════════

has_function() {
  ( source "$CODEFLOW" >/dev/null 2>&1; declare -F "$1" >/dev/null )
}

name_is_valid() {
  ( set +e; source "$CODEFLOW" >/dev/null 2>&1; validate_project_name "$1" >/dev/null 2>&1 )
}

t_validate_project_name_function() {
  if ! has_function validate_project_name; then
    fail "validate_project_name is not defined (or sourcing runs main)"
    return
  fi
  local ok bad
  for ok in 'my-app' '项目一' 'a.b' 'my app' 'ab' 'app_2'; do
    name_is_valid "$ok" || fail "should accept [${ok}]"
  done
  for bad in 'a/b' '..' '.' '-x' '--yes' $'a\nb' $'a\tb' $'\e[31mx' 'a' ''; do
    name_is_valid "$bad" && fail "should reject [$(printf '%q' "$bad")]"
  done
}

t_new_rejects_invalid_project_names_and_reprompts() {
  local P="${PWD}/projects" bad i=0 expected=""
  for bad in 'a/b' '..' '-x' '.' $'a\tb' $'\e[31mred'; do
    i=$((i + 1))
    cf_in "$(feed "$P" "$bad" "ok${i}" "idea" y n)" new
    assert_rc 0 "new after invalid name $(printf '%q' "$bad")"
    assert_contains "$OUT" "项目名称无效" "warning for $(printf '%q' "$bad")"
    assert_exists "${P}/ok${i}/docs/project-state.md"
    expected+="ok${i} "
  done
  assert_eq "$(ls -A "$P" | sort | tr '\n' ' ')" "$expected" "only valid projects were created"
  assert_absent "${PWD}/.cursor"
}

t_new_trims_surrounding_whitespace_in_name() {
  local P="${PWD}/projects"
  cf_in "$(feed "$P" "   trim-me  " idea y n)" new
  assert_rc 0 "new"
  assert_exists "${P}/trim-me/docs/project-state.md"
}

t_new_escapes_quotes_and_backslashes_in_yaml() {
  local P="${PWD}/projects" name='my"app' idea='say "hi" and C:\temp\new' f
  cf_in "$(feed "$P" "$name" "$idea" y n)" new
  assert_rc 0 "new"
  f="${P}/${name}/docs/project-state.md"
  assert_eq "$(grep '^idea:' "$f")" 'idea: "say \"hi\" and C:\\temp\\new"' "idea line"
  assert_eq "$(grep '^project_name:' "$f")" 'project_name: "my\"app"' "project_name line"
  assert_eq "$(grep -c 'detail:' "$f")" 1 "detail line count"
  assert_contains "$(grep 'detail:' "$f")" 'say \"hi\" and C:\\temp\\new' "timeline detail escaped"
}

t_new_does_not_interpret_escape_sequences_in_user_input() {
  local P="${PWD}/projects" name='x\ny' idea='a\tb\nc \e[31mRED' f
  cf_in "$(feed "$P" "$name" "$idea" y n)" new
  assert_rc 0 "new"
  assert_contains "$OUT" 'x\ny' "project name printed literally"
  assert_contains "$OUT" 'a\tb\nc' "idea printed literally"
  assert_not_contains "$OUT" $'\e[31mRED' "no raw ESC from user input"
  f="${P}/${name}/docs/project-state.md"
  assert_exists "$f"
  assert_eq "$(grep '^idea:' "$f")" 'idea: "a\\tb\\nc \\e[31mRED"' "idea line keeps backslashes"
}

# ═════════════════════════════════════════════════════════════════════════════
# 5. status、单一事实来源、帮助
# ═════════════════════════════════════════════════════════════════════════════

t_status_full_vs_incomplete_install() {
  local full
  cf init
  cf status
  full="$OUT"
  assert_contains "$full" "已完整安装" "full install message"
  assert_not_contains "$full" "不完整" "full install has no warning"
  assert_not_contains "$full" "缺失" "full install has no missing marker"

  rm .cursor/agents/fullstack-developer.md
  cf status
  assert_contains "$OUT" "不完整" "incomplete message"
  assert_contains "$OUT" "缺失" "missing marker"
  assert_contains "$OUT" "fullstack-developer" "lists the missing agent"
  assert_not_contains "$OUT" "已完整安装" "no full-install message"
  [[ "$full" != "$OUT" ]] || fail "status output should differ"
}

t_status_on_empty_dir_reports_incomplete() {
  cf status
  assert_contains "$OUT" "不完整" "incomplete message"
}

t_agent_list_comes_from_templates_directory() {
  local repo="${SANDBOX}/repo"
  mkdir -p "$repo" "${SANDBOX}/work/proj"
  cp "$CODEFLOW" "${repo}/codeflow.sh"
  cp -r "$TEMPLATES" "${repo}/templates"
  printf -- '---\nname: zz-extra\ndescription: CodeFlow 额外角色。测试用。\n---\nbody\n' \
    > "${repo}/templates/agents/zz-extra.md"
  cd "${SANDBOX}/work/proj" || return
  CF_SCRIPT="${repo}/codeflow.sh"

  cf init
  assert_rc 0 "init with extra template"
  assert_exists .cursor/agents/zz-extra.md
  cf status
  assert_contains "$OUT" "zz-extra" "status lists the extra agent"
  assert_contains "$OUT" "已完整安装" "status complete"
  cf --yes uninstall
  assert_absent .cursor/agents/zz-extra.md
  assert_absent .cursor
  CF_SCRIPT="$CODEFLOW"
}

t_help_documents_yes_flag_and_modes() {
  cf help
  assert_rc 0 "help"
  assert_contains "$OUT" "--yes" "help mentions --yes"
  assert_contains "$OUT" "fast-track" "help mentions fast-track"
  assert_contains "$OUT" "standard" "help mentions standard"
}

t_unknown_command_fails() {
  cf bogus
  assert_rc 1 "unknown command"
}

# ═════════════════════════════════════════════════════════════════════════════
# 6. 仓库元数据：语法、README、LICENSE、CI
# ═════════════════════════════════════════════════════════════════════════════

t_scripts_pass_bash_syntax_check() {
  bash -n "$CODEFLOW" || fail "bash -n codeflow.sh"
  bash -n "${ROOT}/tests/run.sh" || fail "bash -n tests/run.sh"
}

t_readme_agent_table_matches_templates() {
  local in_section=false line cell readme_agents="" template_names
  while IFS= read -r line; do
    if [[ "$line" == "## "* ]]; then
      if [[ "$line" == "## 团队成员"* ]]; then in_section=true; else in_section=false; fi
      continue
    fi
    [[ "$in_section" == true && "$line" == "|"* ]] || continue
    cell="${line#|}"; cell="${cell%%|*}"
    cell="${cell//\`/}"
    cell="${cell#"${cell%%[![:space:]]*}"}"; cell="${cell%"${cell##*[![:space:]]}"}"
    [[ "$cell" =~ ^[a-z][a-z0-9-]*$ ]] && readme_agents+="${cell}"$'\n'
  done < "${ROOT}/README.md"
  readme_agents="$(printf '%s' "$readme_agents" | sort)"
  template_names="$(template_agents | sort)"
  assert_eq "$readme_agents" "$template_names" "README agent table vs templates/agents/*.md"
}

t_readme_documents_options_modes_and_backup() {
  local readme
  readme="$(cat "${ROOT}/README.md")"
  assert_contains "$readme" "12 个" "README states 12 agents"
  assert_not_contains "$readme" "11 个" "README no longer says 11 agents"
  assert_contains "$readme" "--yes" "README documents --yes"
  assert_contains "$readme" "codeflow help" "README documents help"
  assert_contains "$readme" "fast-track" "README documents fast-track"
  assert_contains "$readme" "standard" "README documents standard"
  assert_contains "$readme" ".codeflow-backup" "README documents backup location"
}

t_license_file_matches_readme_claim() {
  assert_exists "${ROOT}/LICENSE"
  local text
  text="$(cat "${ROOT}/LICENSE" 2>/dev/null)"
  assert_contains "$text" "MIT License" "LICENSE title"
  assert_contains "$text" "Copyright (c) 2026 GGGxie" "LICENSE copyright line"
  assert_contains "$text" "Permission is hereby granted, free of charge" "LICENSE grant"
}

t_ci_workflow_runs_tests_with_pinned_actions() {
  local wf="${ROOT}/.github/workflows/test.yml" line n=0
  assert_exists "$wf"
  [[ -f "$wf" ]] || return
  assert_contains "$(cat "$wf")" "bash tests/run.sh" "workflow runs the test script"
  assert_contains "$(cat "$wf")" "push" "workflow triggers on push"
  assert_contains "$(cat "$wf")" "pull_request" "workflow triggers on pull_request"
  while IFS= read -r line; do
    n=$((n + 1))
    [[ "$line" =~ uses:[[:space:]]+[^@[:space:]]+@[0-9a-f]{40}([[:space:]]|$) ]] \
      || fail "action not pinned to a 40-char commit: ${line}"
  done < <(grep -E '^[[:space:]-]*uses:' "$wf")
  [[ "$n" -ge 1 ]] || fail "workflow has no 'uses:' step"
}

# ═════════════════════════════════════════════════════════════════════════════
# 运行器
# ═════════════════════════════════════════════════════════════════════════════

main() {
  local t pass=0 failed=0 failed_names=()
  for t in $(compgen -A function t_); do
    if [[ -n "$FILTER" && "$t" != *"$FILTER"* ]]; then continue; fi
    printf '• %s\n' "${t#t_}"
    (
      setup_sandbox
      trap cleanup_sandbox EXIT
      T_FAILS=0
      "$t"
      if [[ "$T_FAILS" -gt 0 ]]; then
        printf '    --- last output ---\n'
        printf '%s\n' "$OUT" | head -n 15 | sed 's/^/    | /'
        exit 1
      fi
      exit 0
    )
    if [[ $? -eq 0 ]]; then
      pass=$((pass + 1))
    else
      failed=$((failed + 1))
      failed_names+=("${t#t_}")
    fi
  done

  printf '\n通过: %d  失败: %d  共: %d\n' "$pass" "$failed" "$((pass + failed))"
  if [[ "$failed" -gt 0 ]]; then
    printf '失败用例:\n'
    printf '  - %s\n' "${failed_names[@]}"
    exit 1
  fi
}

main
