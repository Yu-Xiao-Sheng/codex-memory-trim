#!/usr/bin/env bash
# codex-memory-trim installer: install / update / uninstall
set -euo pipefail

MODE="${1:-install}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
DEST="$CODEX_HOME/skills/codex-memory-trim"
SRC="$(cd "$(dirname "$0")/skill" && pwd)"

case "$MODE" in
  install|update)
    if ! command -v python3 >/dev/null 2>&1; then
      echo "error: python3 is required (for the read-only audit script)" >&2
      exit 1
    fi
    mkdir -p "$DEST/scripts" "$DEST/subskills"
    cp "$SRC/SKILL.md" "$DEST/SKILL.md"
    cp "$SRC/scripts/collect.py" "$DEST/scripts/collect.py"
    cp "$SRC/subskills/"*.md "$DEST/subskills/"
    chmod +x "$DEST/scripts/collect.py"
    echo "codex-memory-trim: $MODE done -> $DEST"
    echo
    echo "sanity check (read-only audit):"
    python3 "$DEST/scripts/collect.py" | head -12 || {
      echo "note: audit could not run here (no memories dir on this machine?)" >&2
      exit 0
    }
    echo
    echo "Next: start a new Codex session and say \"精简记忆\" (or 'trim memory')."
    echo "New skills may need a session restart or an inventory force-reload to appear."
    ;;
  uninstall)
    rm -rf "$DEST"
    echo "codex-memory-trim removed: $DEST"
    ;;
  *)
    echo "usage: $0 [install|update|uninstall]"
    echo "env:   CODEX_HOME  (default: \$HOME/.codex)"
    exit 1
    ;;
esac
