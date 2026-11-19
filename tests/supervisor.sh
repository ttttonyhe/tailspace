#!/bin/bash
# Runs the real supervisor against fake Tailscale binaries that fail after a second, to check the
# failure accounting: giving up, the boot a give-up holds for, stopping during a backoff, and the
# prefix lock that an install holds. The copy under test waits 1 s instead of 5 s before its first
# restart, so the backoff runs 1, 2, 4 and 8 s. Takes about two minutes.
# Usage: bash tests/supervisor.sh

# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

# A prefix with a copy of tailspace that runs on the bash running this test, no proxy, autostart
# on, and a tailscaled that fails.
make_prefix() {
  set_paths "$SCRATCH/prefix-$1"
  mkdir -p "$BIN_DIR" "$STATE_DIR"
  sed -e "1s|.*|#!$BASH|" -e 's/^RESTART_DELAY=5$/RESTART_DELAY=1/' "$TEST_ROOT/tailspace" >"$PROGRAM"
  # shellcheck disable=SC2016  # $1 belongs to the fake tailscaled
  printf '%s\n' '#!/bin/sh' 'if [ "$1" = --version ]; then echo 1.0.0; exit 0; fi' 'date +%s%N >>"${0%/*}/starts"' 'sleep 1' 'exit 1' >"$BIN_DIR/tailscaled"
  printf '%s\n' '#!/bin/sh' 'exit 1' >"$BIN_DIR/tailscale"
  chmod 755 "$PROGRAM" "$BIN_DIR/tailscaled" "$BIN_DIR/tailscale"
  : >"$PROXY_FILE"
  # shellcheck disable=SC2034  # read by save_settings
  AUTOSTART=1
  save_settings
}

# wait_for SECONDS COMMAND...: checks once a second until COMMAND succeeds or time runs out.
wait_for() {
  local deadline=$((SECONDS + $1))
  shift

  until "$@"; do
    if [ "$SECONDS" -ge "$deadline" ]; then return 1; fi
    sleep 1
  done
}

boot_of_stop() {
  local boot=""

  { read -r _ boot <"$STOPPED_FILE"; } 2>/dev/null
  echo "$boot"
}

# Whether `sleep SECONDS` runs in session SID, as the supervisor's backoff does.
sleep_left() {
  local dir arg args

  for dir in /proc/[0-9]*; do
    args=""
    while IFS= read -r -d '' arg; do args="$args $arg"; done 2>/dev/null <"$dir/cmdline"
    if [ "$args" = " sleep $2" ] && [ "$(proc_field "${dir#/proc/}" 3)" = "$1" ]; then return 0; fi
  done
  return 1
}

failures_logged() {
  local count

  count=$(grep -c 'tailscaled exited' "$LOG" 2>/dev/null)
  [ "${count:-0}" -ge "$1" ]
}

still_restarting() { supervisor_running && [ ! -e "$STOPPED_FILE" ]; }
# The supervisor sends TERM as it exits and doesn't wait, so a sleep can take a moment to go.
sleep_gone() { ! sleep_left "$1" "$2"; }
# Milliseconds between the starts that the fake tailscaled recorded.
start_gaps() {
  local now prev=""

  while read -r now; do
    if [ -n "$prev" ]; then echo $(((now - prev) / 1000000)); fi
    prev=$now
  done <"$BIN_DIR/starts"
}

# Each wait between runs is at least a run of a second plus the backoff, 1, 2, 4 and then 8 s. No
# upper bound, which a busy runner could break.
waited_double() {
  local gap delay=1 n=0

  for gap in $(start_gaps); do
    [ "$gap" -ge $(((delay + 1) * 1000 - 200)) ] || return 1
    delay=$((delay * 2))
    n=$((n + 1))
  done
  [ "$n" = 4 ]
}

# The backoffs the supervisor logged, in order.
backoffs() { grep -o 'next try in [0-9]*s' "$LOG" | grep -o '[0-9][0-9]*' | paste -sd' ' -; }

# ---------------------------------------------------------------- five failures in a row

make_prefix give-up
"$PROGRAM" autostart
wait_for 10 supervisor_running
session=$(supervisor_pids)
check "the updater sleeps in the supervisor's session" "$(yes_if wait_for 5 sleep_left "$session" 300)" yes
wait_for 60 stopped_for failing
check "five failures in a row give up" "$(yes_if stopped_for failing)" yes
check "...recording the boot they happened in" "$(boot_of_stop)" "$(current_boot)"
check "...after exactly five runs" "$(grep -c 'tailscaled exited' "$LOG")" 5
check "...with backoffs of 1, 2, 4 and 8 s between them" "$(backoffs)" "1 2 4 8"
check "...which tailscaled's starts bear out" "$(yes_if waited_double)" yes
check "...and leave nothing running" "$(yes_if wait_for 10 nothing_runs)" yes
check "...not the updater's sleep" "$(yes_if wait_for 10 sleep_gone "$session" 300)" yes
check "...nor anything else in the supervisor's session" "$(yes_if wait_for 10 session_empty "$session")" yes

"$PROGRAM" autostart
sleep 3
check "autostart leaves a give-up alone for the rest of its boot" "$(yes_if nothing_runs)" yes
printf 'failing another-boot\n' >"$STOPPED_FILE"
"$PROGRAM" autostart
check "autostart starts again after a give-up on an earlier boot" "$(yes_if wait_for 10 supervisor_running)" yes
"$PROGRAM" stop >/dev/null

# ---------------------------------------------------------------- stop during a backoff

make_prefix stop
"$PROGRAM" autostart
check "four failures come within 40 s" "$(yes_if wait_for 40 failures_logged 4)" yes
supervisor=$(supervisor_pids)
check "...followed by an 8-second backoff" "$(yes_if wait_for 5 sleep_left "$supervisor" 8)" yes
start=$SECONDS
"$PROGRAM" stop >/dev/null
check "stop during the backoff returns at once" "$(yes_if [ $((SECONDS - start)) -le 3 ])" yes
check "...stays stopped" "$(yes_if stopped_for user)" yes
check "...ends the supervisor and tailscaled" "$(yes_if nothing_runs)" yes
check "...the backoff sleep" "$(yes_if wait_for 10 sleep_gone "$supervisor" 8)" yes
check "...and everything else in the supervisor's session" "$(yes_if wait_for 10 session_empty "$supervisor")" yes

# ---------------------------------------------------------------- the prefix lock

make_prefix busy
# Held the way an install holds it, with the fd closed for everything this test starts.
exec 7>>"$PREFIX_LOCK"
flock 7
"$PROGRAM" autostart 7>&-
wait_for 10 supervisor_running
session=$(supervisor_pids)
check "seven failures come within 90 s" "$(yes_if wait_for 90 failures_logged 7)" yes
check "...because while an install holds the prefix lock, the supervisor keeps restarting" "$(yes_if still_restarting)" yes
exec 7>&-
check "once the lock is free, the next failure gives up" "$(yes_if wait_for 20 stopped_for failing)" yes
check "...and leaves nothing running" "$(yes_if wait_for 10 nothing_runs)" yes
check "...not even in the supervisor's session" "$(yes_if wait_for 10 session_empty "$session")" yes

finish
