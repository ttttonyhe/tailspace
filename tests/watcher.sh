#!/bin/bash
# Drives the supervisor's watcher through simulated situations and checks what it does and when.
# Time is simulated: sleep moves the clock, and status, path tests and the proxy are stubs.
# Usage: bash tests/watcher.sh

# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

# Unset, SECONDS becomes a plain variable, so only the stubbed sleep moves the clock.
unset SECONDS
SECONDS=0

sleep() { SECONDS=$((SECONDS + ${1%.*})); }
log() { :; }
rotate_log() { :; }

# An hour instead of three days keeps the hold scenarios short.
# shellcheck disable=SC2034  # read by watch_daemon
SESSION_WAIT_MINUTES=60

# Whether the clock is in WINDOW, FROM-TO in seconds, which ends before TO. An empty window never is.
within() {
  [ -n "$1" ] || return 1
  [ "$SECONDS" -ge "${1%-*}" ] && [ "$SECONDS" -lt "${1#*-}" ]
}

# One session, open until SESSIONS_UNTIL.
open_sessions() { if [ "$SECONDS" -lt "$SESSIONS_UNTIL" ]; then echo 1; else echo 0; fi; }

# The watcher runs until its parent changes; here it runs for MAX_ITERATIONS probes.
is_child_of() {
  ITERATION=$((ITERATION + 1))
  [ "$ITERATION" -le "$MAX_ITERATIONS" ]
}

status_json() {
  local online="$ONLINE"

  [ "$API_OK" = 1 ] || return 1
  if within "$OFFLINE"; then online=false; fi
  printf '{\n  "BackendState": "%s",\n  "Self": {\n    "Online": %s\n  }\n}\n' "$STATE" "$online"
}

path_works() {
  if [ "$1" = direct ]; then
    [ "$DIRECT_OK" = 1 ] && ! within "$DIRECT_DOWN"
  else
    [ "$PROXY_OK" = 1 ] && [ "$SECONDS" -ge "$PROXY_FROM" ]
  fi
}

proxy_url() { if [ "$HAS_PROXY" = 1 ]; then printf '%s' http://127.0.0.1:3128; fi; }
prefix_busy() { [ "$BUSY" = 1 ]; }

# Ends the run like the real one does, recording the reason and the simulated time.
restart_for() {
  printf '%s %s\n' "$1" "$SECONDS" >"$RESULT"
  exit 0
}

# Prints "REASON SECONDS" for the restart the watcher asks for, or "none".
run_watcher() {
  local path="$1" assignment dir
  shift

  API_OK=1 STATE=Running ONLINE=true DIRECT_OK=1 PROXY_OK=1 PROXY_FROM=0 HAS_PROXY=1 BUSY=0
  ENROLLED=0 MAX_ITERATIONS=200 ITERATION=0 SECONDS=0 SESSIONS_UNTIL=0 DIRECT_DOWN="" OFFLINE=""
  for assignment in "$@"; do eval "$assignment"; done

  dir=$(mktemp -d "$SCRATCH/case.XXXXXX") || {
    echo "mktemp failed"
    return
  }
  set_paths "$dir"
  mkdir -p "$STATE_DIR"
  if [ "$ENROLLED" = 1 ]; then : >"$ENROLLED_FILE"; fi
  RESULT="$STATE_DIR/result"
  # shellcheck disable=SC2034  # read by watch_daemon
  HOLDDOWN="$FAILBACK_HOLDDOWN"
  if ! (watch_daemon "$path"); then
    echo "watcher failed"
    return
  fi
  cat "$RESULT" 2>/dev/null || echo none
}

# scenario NAME PATH EXPECTED [VARIABLE=VALUE ...]
scenario() {
  local name="$1" path="$2" expected="$3"
  shift 3
  check "$name" "$(run_watcher "$path" "$@")" "$expected"
}

scenario "direct, online: nothing to do" direct none MAX_ITERATIONS=100
scenario "direct path down, proxy path works: fail over after 4 minutes" direct "failover 260" ONLINE=false DIRECT_OK=0
scenario "direct path down from NoState: fail over" direct "failover 260" STATE=NoState ONLINE=false DIRECT_OK=0
scenario "direct path down while Starting: fail over" direct "failover 260" STATE=Starting ONLINE=false DIRECT_OK=0
scenario "both paths down: wait" direct none ONLINE=false DIRECT_OK=0 PROXY_OK=0 MAX_ITERATIONS=100
scenario "direct path down, no proxy: wait" direct none ONLINE=false DIRECT_OK=0 HAS_PROXY=0 MAX_ITERATIONS=100
scenario "outage, proxy path back at 300 s: fail over within a minute" direct "failover 320" ONLINE=false DIRECT_OK=0 PROXY_FROM=300
scenario "proxy path down, direct path works: fail over after a minute" proxy "failover 80" ONLINE=false PROXY_OK=0
scenario "on the proxy path, direct path healthy: fail back after the holddown" proxy "failback 1200"
scenario "on the proxy path, direct path down: stay" proxy none DIRECT_OK=0 MAX_ITERATIONS=150
scenario "offline while its own path works: stuck" direct "stuck 500" ONLINE=false
scenario "LocalAPI doesn't answer: hung" direct "hung 60" API_OK=0
scenario "an enrolled node must log in: give up" direct "needs-login 140" STATE=NeedsLogin ENROLLED=1
scenario "must log in during an install: wait" direct none STATE=NeedsLogin ENROLLED=1 BUSY=1 MAX_ITERATIONS=100
scenario "never enrolled, must log in: wait" direct none STATE=NeedsLogin MAX_ITERATIONS=100
scenario "turned off with tailscale down: nothing to do" direct none STATE=Stopped ONLINE=false MAX_ITERATIONS=100
scenario "Starting but online: nothing to do" direct none STATE=Starting MAX_ITERATIONS=100

# Holds for sessions. The direct path is good from 900 s, so the hold starts at the check at 1200 s
# and fails back once an hour of holding has passed; tests that fail, or time offline, don't count.
scenario "a session open until 1500 s: fail back when it closes" proxy "failback 1500" SESSIONS_UNTIL=1500
scenario "a session that stays open: fail back after an hour of holding" proxy "failback 4800" SESSIONS_UNTIL=999999 MAX_ITERATIONS=300
scenario "failed direct tests pause the hold" proxy "failback 6000" SESSIONS_UNTIL=999999 DIRECT_DOWN=2000-2600 MAX_ITERATIONS=350
scenario "...however long the direct path stays down" proxy "failback 33300" SESSIONS_UNTIL=999999 DIRECT_DOWN=2000-30000 MAX_ITERATIONS=1700
scenario "a short time offline restarts the streak and pauses the hold" proxy "failback 5400" SESSIONS_UNTIL=999999 OFFLINE=2000-2060 MAX_ITERATIONS=300
scenario "sessions don't hold a failover from the proxy path" proxy "failover 80" ONLINE=false PROXY_OK=0 SESSIONS_UNTIL=999999
scenario "...nor one from the direct path" direct "failover 260" ONLINE=false DIRECT_OK=0 SESSIONS_UNTIL=999999
scenario "...nor a restart when stuck" direct "stuck 500" ONLINE=false SESSIONS_UNTIL=999999

finish
