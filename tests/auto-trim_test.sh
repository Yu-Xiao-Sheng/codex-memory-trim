#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/home"
set +e
HOME="$tmp_dir/home" CODEX_BIN="$repo_root/tests/fixtures/failing-codex" AUTO_TRIM_TIMEOUT=2 "$repo_root/skill/scripts/auto-trim.sh" >/dev/null 2>&1
status=$?
set -e

if [ "$status" -ne 23 ]; then
  echo "expected auto-trim.sh to propagate codex exit 23, got $status" >&2
  exit 1
fi
