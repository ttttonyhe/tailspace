# Sourced by the tests: loads the functions of tailspace without running it, makes a scratch
# directory that is cleaned up on exit, and provides checks and helpers.
# shellcheck shell=bash

TEST_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FAILURES=0

# The program runs from its last line; anything else there would run it while this file sources it.
# shellcheck disable=SC2016  # the literal line
if [ "$(tail -n 1 "$TEST_ROOT/tailspace")" != 'main "$@"; exit' ]; then
  echo "tailspace doesn't end with its entry point." >&2
  exit 1
fi

# Without symlinks, so its paths read as the program's do, which some checks compare as text. If
# mktemp fails, stop: an empty name would make the cleanup delete the current directory.
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/tailspace-test.XXXXXX") && SCRATCH=$(cd "$SCRATCH" && pwd -P) || exit 1

# Set before sourcing, because the program's paths follow HOME, TAILSPACE_PREFIX would point it at a
# real installation, and crontab -r backs the crontab up under XDG_CACHE_HOME.
export HOME="$SCRATCH/home" XDG_CACHE_HOME="$SCRATCH/home/.cache"
mkdir -p "$HOME"
unset TAILSPACE_PREFIX

# shellcheck source=/dev/null
source <(sed '$d' "$TEST_ROOT/tailspace")
# shellcheck disable=SC2034  # read by the functions of tailspace
SELF="$TEST_ROOT/tailspace"

# Stops the supervisors and tailscaled that a test started, found by their lock and state directory
# as the program finds them, then deletes the scratch directory.
clean_scratch() {
  local dir pid stopped=0

  for dir in "$SCRATCH"/prefix* "$HOME/.tailspace"; do
    [ -d "$dir/state" ] || continue
    set_paths "$dir"
    for pid in $(supervisor_pids) $(daemon_pids); do
      if kill -TERM "$pid" 2>/dev/null; then stopped=1; fi
    done
  done
  # Their children can hold files there for a moment, and on NFS an open file keeps the directory.
  if [ "$stopped" = 1 ]; then sleep 2; fi
  rm -rf "$SCRATCH"
}

trap clean_scratch EXIT
# bash skips the EXIT trap when a signal ends it, so turn the signals into exits.
trap 'exit 130' INT
trap 'exit 143' TERM

# check NAME GOT WANT
check() {
  if [ "$2" = "$3" ]; then
    printf 'ok    %s\n' "$1"
    return 0
  fi
  printf 'FAIL  %s\n      got:  %s\n      want: %s\n' "$1" "$2" "$3"
  FAILURES=$((FAILURES + 1))
}

yes_if() { if "$@"; then echo yes; else echo no; fi; }

# The first word of the stopped file: why Tailspace stopped.
stop_reason() {
  local reason=""

  { read -r reason _ <"$STOPPED_FILE"; } 2>/dev/null
  echo "$reason"
}

stopped_for() { [ "$(stop_reason)" = "$1" ]; }
nothing_runs() { [ -z "$(supervisor_pids)$(daemon_pids)" ]; }

# Whether nothing but zombies is left in session SID.
session_empty() {
  local pid

  [ -n "$1" ] || return 1
  for pid in $(session_pids "$1"); do
    if alive "$pid"; then return 1; fi
  done
}

finish() {
  if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES failed."
    exit 1
  fi
  echo "All passed."
}
