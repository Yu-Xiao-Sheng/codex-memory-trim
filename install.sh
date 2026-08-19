#!/usr/bin/env bash
# codex-memory-trim installer: install / update / uninstall / schedule / unschedule
# Scheduling works on Linux (systemd user timer) and macOS (launchd LaunchAgent);
# other systems get a crontab line to add manually.
set -euo pipefail

MODE="${1:-install}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
DEST="$CODEX_HOME/skills/codex-memory-trim"
SRC="$(cd "$(dirname "$0")/skill" && pwd)"
TIMER_NAME="codex-memory-trim"
LAUNCHD_LABEL="com.codex-memory-trim"
OS="$(uname -s)"

install_or_update() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 is required (for the read-only audit script)" >&2
    exit 1
  fi
  mkdir -p "$DEST/scripts" "$DEST/subskills"
  cp "$SRC/SKILL.md" "$DEST/SKILL.md"
  cp "$SRC/scripts/collect.py" "$DEST/scripts/collect.py"
  cp "$SRC/scripts/auto-trim.sh" "$DEST/scripts/auto-trim.sh"
  cp "$SRC/subskills/"*.md "$DEST/subskills/"
  chmod +x "$DEST/scripts/auto-trim.sh"
  echo "codex-memory-trim: $1 done -> $DEST"
  echo
  echo "sanity check (read-only audit):"
  local audit_out
  if audit_out="$(python3 "$DEST/scripts/collect.py" 2>/dev/null)"; then
    echo "$audit_out" | head -12
  else
    echo "note: audit could not run here (no memories dir on this machine?)"
    exit 0
  fi
  echo
  echo "Next: start a new Codex session and say \"精简记忆\" (or 'trim memory')."
  echo "Scheduled runs: $0 schedule daily 09:30 [--random 2h]"
}

# ---- Linux: systemd user timer -------------------------------------------------

write_systemd_units() {  # $1=OnCalendar $2=RandomizedDelaySec("" if none)
  mkdir -p "$HOME/.config/systemd/user"
  cat > "$HOME/.config/systemd/user/${TIMER_NAME}.service" <<EOF
[Unit]
Description=codex-memory-trim automated memory maintenance

[Service]
Type=oneshot
ExecStart=$DEST/scripts/auto-trim.sh
EOF
  {
    echo "[Unit]"
    echo "Description=Schedule codex-memory-trim"
    echo
    echo "[Timer]"
    echo "OnCalendar=$1"
    [ -n "$2" ] && echo "RandomizedDelaySec=$2"
    echo "Persistent=true"
    echo
    echo "[Install]"
    echo "WantedBy=timers.target"
  } > "$HOME/.config/systemd/user/${TIMER_NAME}.timer"
}

# ---- macOS: launchd LaunchAgent ------------------------------------------------

weekday_to_launchd() {  # mon..sun -> 1..5, 6, 0
  case "$1" in
    sun) echo 0 ;; mon) echo 1 ;; tue) echo 2 ;; wed) echo 3 ;;
    thu) echo 4 ;; fri) echo 5 ;; sat) echo 6 ;;
    *) echo "error: bad weekday '$1'" >&2; exit 1 ;;
  esac
}

write_launchd_plist() {  # $1=weekday("" if daily) $2=hour $3=minute
  local extra=""
  [ -n "$1" ] && extra="    <key>Weekday</key><integer>$1</integer>"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$HOME/Library/LaunchAgents/${LAUNCHD_LABEL}.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LAUNCHD_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${DEST}/scripts/auto-trim.sh</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer>$2</integer>
    <key>Minute</key><integer>$3</integer>
$extra
  </dict>
</dict>
</plist>
EOF
  launchctl unload "$HOME/Library/LaunchAgents/${LAUNCHD_LABEL}.plist" 2>/dev/null || true
  launchctl load "$HOME/Library/LaunchAgents/${LAUNCHD_LABEL}.plist"
}

# ---- shared schedule/unschedule -------------------------------------------------

schedule() {
  local kind="${1:-daily}"; shift || true
  local day="" time="09:30" rnd=""
  if [ "$kind" = "weekly" ]; then
    day="${1:-sat}"; shift || true
  fi
  if [ "${1:-}" != "" ] && [[ "$1" != --* ]]; then time="$1"; shift; fi
  while [ $# -gt 0 ]; do
    case "$1" in
      --random) rnd="${2:?--random needs a value like 30m or 2h}"; shift 2 ;;
      *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
  done
  [[ "$time" =~ ^[0-2][0-9]:[0-5][0-9]$ ]] || { echo "error: time must be HH:MM, got '$time'" >&2; exit 1; }
  local hour=$((10#${time%%:*})) minute=$((10#${time#*:}))

  case "$kind" in
    daily) : ;;
    weekly) : ;;
    *) echo "error: kind must be 'daily' or 'weekly', got '$kind'" >&2; exit 1 ;;
  esac

  if [ "$OS" = "Linux" ] && command -v systemctl >/dev/null 2>&1; then
    local cal
    if [ "$kind" = "daily" ]; then
      cal="*-*-* ${time}:00"
    else
      local cap="$(printf '%s' "${day:0:1}" | tr '[:lower:]' '[:upper:]')${day:1}"
      cal="${cap} *-*-* ${time}:00"
    fi
    write_systemd_units "$cal" "$rnd"
    systemctl --user daemon-reload
    systemctl --user enable --now "${TIMER_NAME}.timer"
    echo "scheduled (systemd): $cal${rnd:+ (+random $rnd)}"
    systemctl --user list-timers "${TIMER_NAME}.timer" --no-pager | head -3 || true
  elif [ "$OS" = "Darwin" ]; then
    # launchd has no randomized delay; randomize the time point at install time
    if [ -n "$rnd" ]; then
      local unit="${rnd: -1}" amount="${rnd%?}"
      [[ "$amount" =~ ^[0-9]+$ ]] || { echo "error: bad --random value '$rnd'" >&2; exit 1; }
      if [ "$unit" = "h" ]; then
        hour=$(( (hour + RANDOM % (amount + 1)) % 24 )); minute=$(( RANDOM % 60 ))
      elif [ "$unit" = "m" ]; then
        local total=$(( minute + RANDOM % (amount + 1) ))
        hour=$(( (hour + total / 60) % 24 )); minute=$(( total % 60 ))
      else
        echo "error: --random supports m or h units, got '$rnd'" >&2; exit 1
      fi
    fi
    local wd=""
    [ "$kind" = "weekly" ] && wd="$(weekday_to_launchd "$day")"
    write_launchd_plist "$wd" "$hour" "$minute"
    printf 'scheduled (launchd): %s at %02d:%02d%s\n' \
      "$([ "$kind" = weekly ] && echo "every $day" || echo "daily")" \
      "$hour" "$minute" "${rnd:+ (randomized at install)}"
  else
    local rnd_min=$(( RANDOM % 60 ))
    echo "no systemd/launchd found; add this crontab line instead (minute randomized):"
    if [ "$kind" = "daily" ]; then
      echo "  ${rnd_min} ${hour} * * * $DEST/scripts/auto-trim.sh"
    else
      echo "  ${rnd_min} ${hour} * * $([ "$day" = sun ] && echo 0 || echo 1) $DEST/scripts/auto-trim.sh  # adjust day"
    fi
  fi
}

unschedule() {
  if [ "$OS" = "Linux" ] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable --now "${TIMER_NAME}.timer" 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/${TIMER_NAME}.service" \
          "$HOME/.config/systemd/user/${TIMER_NAME}.timer"
    systemctl --user daemon-reload
    echo "schedule removed (systemd)"
  elif [ "$OS" = "Darwin" ]; then
    launchctl unload "$HOME/Library/LaunchAgents/${LAUNCHD_LABEL}.plist" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/${LAUNCHD_LABEL}.plist"
    echo "schedule removed (launchd)"
  else
    echo "no systemd/launchd found; remove the crontab line manually (crontab -e)" >&2
  fi
}

case "$MODE" in
  install|update)
    install_or_update "$MODE"
    ;;
  schedule)
    [ -d "$DEST" ] || { echo "error: install first ($0 install)" >&2; exit 1; }
    shift
    schedule "$@"
    ;;
  unschedule)
    unschedule
    ;;
  uninstall)
    unschedule
    rm -rf "$DEST"
    echo "codex-memory-trim removed: $DEST"
    ;;
  *)
    echo "usage: $0 [install|update|uninstall|schedule|unschedule]"
    echo "  install | update            install/refresh the skill"
    echo "  schedule daily [HH:MM] [--random 30m|2h]"
    echo "  schedule weekly [day] [HH:MM] [--random 30m|2h]   # day: mon..sun, default sat"
    echo "  unschedule                  remove the timer (systemd on Linux, launchd on macOS)"
    echo "env: CODEX_HOME (default: \$HOME/.codex)"
    exit 1
    ;;
esac
