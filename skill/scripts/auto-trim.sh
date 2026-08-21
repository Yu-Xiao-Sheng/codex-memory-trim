#!/usr/bin/env bash
# Headless memory-trim runner for schedulers (systemd timer / launchd / cron).
# Portable across Linux and macOS: no flock, no GNU date, no timeout(1).
# Invokes codex exec with the codex-memory-trim skill procedure; backs up first,
# only deletes threads that meet the strict criteria, logs to the state dir.
set -uo pipefail

cd "$HOME"

# resolve the real codex binary; PATH may expose a desktop/gateway shim that needs X
if [ -n "${CODEX_BIN:-}" ]; then :
elif [ -x "$HOME/.codex/packages/standalone/current/codex" ]; then
  CODEX_BIN="$HOME/.codex/packages/standalone/current/codex"
else
  CODEX_BIN="$(command -v codex || echo codex)"
fi
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/codex-memory-trim"
LOG="$LOG_DIR/auto.log"
LOCK_DIR="$LOG_DIR/auto.lock"
MAX_SECONDS="${AUTO_TRIM_TIMEOUT:-1800}"
ts() { date +%Y-%m-%dT%H:%M:%S%z; }

PROMPT='使用 codex-memory-trim skill 自动整理全局记忆，按 trim 子技能流程单次执行：1) 先做时间戳备份（tar 全目录 + sqlite 单独备份到 ~/.codex/backups/），备份是硬性前置条件，若备份创建失败则立即停止并记录失败原因，禁止在没有新备份的情况下删除或修改任何记忆文件；2) 运行该 skill 的 scripts/collect.py 巡检；3) 仅当存在完全符合删除标准的候选（MEMORY.md 未引用的孤儿 + usage_count<20 + 会话完成超过两周 + 琐碎一次性工作）才执行三层一致删除并同步精简 MEMORY.md 与 memory_summary.md；4) 无合格候选则不修改任何文件；5) 全程不碰 extensions/ad_hoc/notes 与 sessions/；6) 若自动整理任务正在运行则直接结束；7) 结束时若有变更则按共享模板 git 提交，并输出一行中文摘要（日期、候选数、删除数、提交哈希或"无操作"）。效率优先，一次完成，不反复校验。'

mkdir -p "$LOG_DIR"

# schedulers run in clean environments; source the key file if present
# (create with: mkdir -p ~/.config/codex-memory-trim && echo 'CODEX_API_KEY=...' > ~/.config/codex-memory-trim/env && chmod 600 ~/.config/codex-memory-trim/env)
ENV_FILE="$HOME/.config/codex-memory-trim/env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"
export CODEX_API_KEY

# migrate: very old versions left a lock FILE at this path; a directory is required
[ -f "$LOCK_DIR" ] && rm -f "$LOCK_DIR"

# mkdir-based lock (portable); stale after 2x the max runtime
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  stale_min=$(( MAX_SECONDS / 60 * 2 ))
  if [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +$stale_min 2>/dev/null)" ]; then
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || { echo "$(ts) lock contention, skipped" >> "$LOG"; exit 0; }
  else
    echo "$(ts) another run is active, skipped" >> "$LOG"
    exit 0
  fi
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

echo "$(ts) run start (codex: $CODEX_BIN)" >> "$LOG"

# portable timeout: background job + watchdog
# danger-full-access is required: the default workspace-write sandbox marks CODEX_HOME
# (including ~/.codex/backups and ~/.codex/memories) read-only, which blocks the whole
# maintenance flow; the safety rails live in the skill itself (backup-first, deletion
# criteria, git rollback)
"$CODEX_BIN" exec --skip-git-repo-check --sandbox danger-full-access "$PROMPT" < /dev/null >> "$LOG" 2>&1 &
job=$!
( sleep "$MAX_SECONDS"; kill "$job" 2>/dev/null ) &
watchdog=$!
wait "$job"
rc=$?
kill "$watchdog" 2>/dev/null
echo "$(ts) run end (exit $rc)" >> "$LOG"
