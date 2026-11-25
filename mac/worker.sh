#!/bin/bash
# Anicca living-agent worker loop (sanitized public version).
# Usage: worker.sh <agent_home> <engine: opencode|commandcode>
#
# Layout under <agent_home>: inbox/ outbox/ done/ logs/
# A task is a .md file in inbox/. Optional first line: "WORKDIR: <path>".
# The engine's full output lands in outbox/<task>.result.md; the task
# file moves to done/. A heartbeat line is appended every cycle.
#
# Secrets: engines read their keys from env files in <agent_home>
# (chmod 600, never committed, never printed). Provision them from your
# team vault out-of-band.
set -u
AGENT_HOME="$1"
ENGINE="$2"
INBOX="$AGENT_HOME/inbox"
OUTBOX="$AGENT_HOME/outbox"
DONE_DIR="$AGENT_HOME/done"
LOGS="$AGENT_HOME/logs"
mkdir -p "$INBOX" "$OUTBOX" "$DONE_DIR" "$LOGS"

ts() { date "+%Y-%m-%d %H:%M:%S %Z"; }
log() { echo "[$(ts)] $*" >> "$LOGS/worker.log"; }

run_engine() {
  local task_file="$1" workdir="$2"
  local prompt
  prompt="$(cat "$task_file")"
  cd "$workdir" || return 1
  if [ "$ENGINE" = "opencode" ]; then
    # OPENCODE_CONFIG points at a config whose provider key comes from
    # the OPENROUTER_API_KEY env var (sourced from your secret store).
    if [ -f "$AGENT_HOME/opencode.env" ]; then set -a; . "$AGENT_HOME/opencode.env"; set +a; fi
    if [ -z "${OPENROUTER_API_KEY:-}" ]; then
      echo "CONFIG_ERROR: OPENROUTER_API_KEY could not be loaded."
      return 43
    fi
    timeout 1800 opencode run --auto --title "worker" "$prompt" 2>&1
  elif [ "$ENGINE" = "commandcode" ]; then
    # Provision the account API key as an env file so the lane is
    # authenticated without an interactive login on a headless host.
    if [ -f "$AGENT_HOME/commandcode.env" ]; then set -a; . "$AGENT_HOME/commandcode.env"; set +a; fi
    if command-code status 2>&1 | grep -qi "not authenticated"; then
      echo "AUTH_REQUIRED: command-code is not authenticated on this host."
      return 42
    fi
    # --yolo is required: in headless mode the engine answers but
    # refuses file writes without it (measured 2026-11-25).
    timeout 1800 command-code -p "$prompt" -m deepseek/deepseek-v4.1-flash --trust --yolo 2>&1
  fi
}

log "worker started engine=$ENGINE home=$AGENT_HOME"
while true; do
  echo "$(ts) alive engine=$ENGINE" >> "$LOGS/heartbeat.log"
  tail -n 500 "$LOGS/heartbeat.log" > "$LOGS/heartbeat.tmp" 2>/dev/null && mv "$LOGS/heartbeat.tmp" "$LOGS/heartbeat.log"
  for task in "$INBOX"/*.md; do
    [ -e "$task" ] || continue
    base="$(basename "$task")"
    workdir="$(head -1 "$task" | sed -n 's/^WORKDIR: //p')"
    [ -z "$workdir" ] && workdir="$PWD"
    log "task start: $base workdir=$workdir"
    out="$OUTBOX/${base%.md}.result.md"
    {
      echo "# Result: $base"
      echo "- agent_home: $AGENT_HOME"
      echo "- engine: $ENGINE"
      echo "- started: $(ts)"
      echo ""
      echo "## Engine output"
      echo '```'
      run_engine "$task" "$workdir"
      echo "ENGINE_EXIT=$?"
      echo '```'
      echo "- finished: $(ts)"
    } > "$out" 2>&1
    mv "$task" "$DONE_DIR/$base"
    log "task done: $base -> $out"
  done
  sleep 120
done
