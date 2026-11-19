#!/bin/bash
# Installs Tailspace the way the README does, with the latest Tailscale release and the real
# coordination server, but joins no tailnet: the made-up auth key below is refused. Then starts,
# restarts, stops and uninstalls it. Needs network access, and runs in a throwaway HOME.
# Usage: bash tests/e2e.sh

# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

# Made up, so the coordination server refuses it.
export TS_AUTHKEY=tskey-auth-kTailspaceTest-NotARealKey
set_paths "$HOME/.tailspace"

# Removes the cron job too, which lives in the user's crontab, outside the scratch directory.
cleanup() {
  if [ -x "$PROGRAM" ]; then "$PROGRAM" uninstall >/dev/null 2>&1; fi
  if cron_present; then cron_set remove; fi
  clean_scratch
}
trap cleanup EXIT

replaced() { supervisor_running && [ "$(supervisor_pids)" != "$1" ]; }
own_session() { [ -n "$1" ] && [ "$(proc_field "$1" 3)" = "$1" ]; }
both_run() { supervisor_running && [ -n "$(daemon_pids)" ]; }

# The latest Tailscale release, read from the same index as the program reads, without its code.
upstream_version() {
  local url="https://pkgs.tailscale.com/stable/?mode=json"

  { curl -fsSL -m 20 --noproxy '*' "$url" || curl -fsSL -m 20 "$url"; } 2>/dev/null |
    grep -o '"TarballsVersion": *"[^"]*"' | cut -d'"' -f4 | head -n 1
}

# A release may come out during the test, so either version counts.
latest_installed() {
  local installed

  installed=$(installed_version)
  [ -n "$installed" ] && { [ "$installed" = "$before" ] || [ "$installed" = "$(upstream_version)" ]; }
}

# The tailscaled that answers is the only one, and not OLD.
new_daemon() {
  ! alive "$1" && [ "$(daemon_pids | grep -c .)" = 1 ] && api_answers
}

# Whether this account may use cron: it has a crontab, or none yet.
cron_allowed() { crontab -l >/dev/null 2>&1 || crontab -l 2>&1 | grep -q 'no crontab'; }

# Whether any PID in a space-separated list still runs.
any_alive() {
  local pid

  for pid in $1; do
    if alive "$pid"; then return 0; fi
  done
  return 1
}

# ---------------------------------------------------------------- install

# The one-line install from the README, fed from this checkout instead of GitHub.
before=$(upstream_version)
TAILSPACE_SOURCE_URL="file://$TEST_ROOT/tailspace" bash <"$TEST_ROOT/tailspace" >"$SCRATCH/install.out" 2>&1
rc=$?
sed 's/^/    | /' "$SCRATCH/install.out"
check "the install ends in an error for a refused key" "$rc" 1
check "...refused by the coordination server, not by the CLI" "$(yes_if grep -qi 'invalid key' "$SCRATCH/install.out")" yes
check "...which the stopped file records" "$(stop_reason)" enroll-failed
check "...and status explains" "$(yes_if grep -qF "stopped: $(stopped_hint)" <("$PROGRAM" status 2>&1))" yes
check "...with the latest Tailscale installed" "$(yes_if latest_installed)" yes
check "...and nothing left running" "$(yes_if nothing_runs)" yes

# ---------------------------------------------------------------- self-update

# Served from files, the way GitHub serves the real one.
sed 's/^TAILSPACE_VERSION=.*/TAILSPACE_VERSION="99.0.0"/' "$TEST_ROOT/tailspace" >"$SCRATCH/newer"
# A version and an entry point around a syntax error, so only bash -n can catch it.
# shellcheck disable=SC2016  # the fixture's own text
printf '%s\n' 'TAILSPACE_VERSION="99.0.1"' 'if then' 'main "$@"; exit' >"$SCRATCH/broken"
: >"$SCRATCH/empty"
for bad in broken empty; do
  out=$(TAILSPACE_SOURCE_URL="file://$SCRATCH/$bad" "$PROGRAM" self-update 2>&1)
  check "self-update refuses the $bad download" "$?:$(cksum <"$PROGRAM")" "1:$(cksum <"$TEST_ROOT/tailspace")"
  check "...as damaged" "$(yes_if grep -qF 'The downloaded Tailspace is damaged.' <(printf '%s\n' "$out"))" yes
done
# The reinstall can't log in here either, but by then the newer program is in place.
out=$(TAILSPACE_SOURCE_URL="file://$SCRATCH/newer" "$PROGRAM" self-update 2>&1)
check "self-update names both versions" "$(yes_if grep -qF "Updating Tailspace $TAILSPACE_VERSION to 99.0.0" <(printf '%s\n' "$out"))" yes
check "...and installs the newer Tailspace" "$("$PROGRAM" version | head -n 1)" "Tailspace 99.0.0"
TAILSPACE_SOURCE_URL="file://$SCRATCH/newer" "$PROGRAM" self-update >/dev/null 2>&1
check "...and then has nothing to do" "$?" 0
# Run from another copy, self-update names the installed version, not its own.
sed 's/^TAILSPACE_VERSION=.*/TAILSPACE_VERSION="99.0.2"/' "$TEST_ROOT/tailspace" >"$SCRATCH/newest"
out=$(TAILSPACE_SOURCE_URL="file://$SCRATCH/newest" "$TEST_ROOT/tailspace" self-update 2>&1)
check "self-update run from another copy names the installed version" "$(yes_if grep -qF "Updating Tailspace 99.0.0 to 99.0.2" <(printf '%s\n' "$out"))" yes

# ---------------------------------------------------------------- start, restart and stop

"$PROGRAM" start >/dev/null 2>&1
check "start succeeds" "$?" 0
check "...and runs the supervisor" "$(yes_if supervisor_running)" yes
check "...and one tailscaled" "$(daemon_pids | wc -l)" 1
check "...in a session of its own" "$(yes_if own_session "$(daemon_pids)")" yes
status=$(status_json)
check "Tailscale waits for a login" "$(json_string BackendState "$status")" NeedsLogin
check "Tailscale runs the installed version" "$(daemon_version "$status")" "$(installed_version)"

old=$(supervisor_pids)
old_daemon=$(daemon_pids)
"$PROGRAM" restart >/dev/null 2>&1
check "restart succeeds" "$?" 0
check "...with a new supervisor" "$(yes_if replaced "$old")" yes
check "...and a new tailscaled, the only one, which answers" "$(yes_if new_daemon "$old_daemon")" yes

"$PROGRAM" stop >/dev/null
check "stop succeeds" "$?" 0
check "...and leaves nothing running" "$(yes_if nothing_runs)" yes
"$PROGRAM" autostart
sleep 3
check "autostart leaves a stopped server alone" "$(yes_if nothing_runs)" yes

# ---------------------------------------------------------------- uninstall

"$PROGRAM" start >/dev/null 2>&1
check "start succeeds again" "$?" 0
check "...and runs the supervisor and tailscaled" "$(yes_if both_run)" yes
check "the install added the shell hook" "$(grep -cxF "$HOOK_BEGIN" "$HOME/.bashrc")" 1
check "...the links" "$(cd "$HOME/.local/bin" && echo *)" "tailscale tailspace"
if command -v crontab >/dev/null; then
  if cron_runs && cron_allowed; then jobs=1; else jobs=0; fi
  check "...a cron job at boot exactly where cron can run it" "$(crontab -l 2>/dev/null | grep -cF "@reboot \"$PROGRAM\" autostart ")" "$jobs"
  check "...and one every five minutes" "$(crontab -l 2>/dev/null | grep -cF "*/5 * * * * \"$PROGRAM\" autostart ")" "$jobs"
fi
# Once uninstall deletes the state directory, nothing finds these by their lock or state path.
running="$(supervisor_pids) $(daemon_pids)"
"$PROGRAM" uninstall >/dev/null 2>&1
check "uninstall succeeds" "$?" 0
check "...stops the supervisor and tailscaled" "$(yes_if any_alive "$running")" no
check "...removes the prefix" "$(yes_if [ ! -e "$PREFIX" ])" yes
check "...the shell hooks" "$(cat "$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc" 2>/dev/null | grep -c "$NAME (")" 0
check "...the links" "$(ls -A "$HOME/.local/bin" 2>/dev/null)" ""
check "...and the cron job" "$(crontab -l 2>/dev/null | grep -cF "$CRON_MARK")" 0

finish
