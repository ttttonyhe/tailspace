#!/bin/bash
# Checks the helper functions of tailspace on their own: reading status, settings, options, auth
# keys, proxies, the shell hook and the stopped file. Needs no network and starts no processes.
# Usage: bash tests/functions.sh

# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

# Shaped like `tailscale status --json --peers=false`: the node's addresses and Self come before
# ExitNodeStatus, which has an Online of its own.
STATUS='{
  "Version": "1.104.7-t1a2b3c4d5-g6e7f8a9b0",
  "TUN": false,
  "BackendState": "Running",
  "TailscaleIPs": [
    "100.101.102.103",
    "fd7a:115c:a1e0::1"
  ],
  "Self": {
    "DNSName": "lab-07.tail1234.ts.net.",
    "TailscaleIPs": [
      "100.101.102.103",
      "fd7a:115c:a1e0::1"
    ],
    "Online": true
  },
  "ExitNodeStatus": {
    "Online": false
  }
}'

set_paths "$SCRATCH/prefix"
mkdir -p "$STATE_DIR"

# ---------------------------------------------------------------- status --json

check "BackendState" "$(json_string BackendState "$STATUS")" Running
check "Online belongs to Self, not to the exit node" "$(json_bool Online "$STATUS")" true
check "a missing key reads as empty" "$(json_string Missing "$STATUS")" ""
check "daemon_version drops the build suffix" "$(daemon_version "$STATUS")" 1.104.7
check "node_label names the host and its IPv4 address" "$(node_label "$STATUS")" "lab-07 (100.101.102.103)"

# ---------------------------------------------------------------- settings and options

AUTOSTART=0 AUTO_UPDATE=1 SSH=0 LOG_UPLOAD=1 UDP_PORT=41641
save_settings
AUTOSTART=x AUTO_UPDATE=x SSH=x LOG_UPLOAD=x UDP_PORT=x
load_settings
check "settings survive a save and a load" "$AUTOSTART $AUTO_UPDATE $SSH $LOG_UPLOAD $UDP_PORT" "0 1 0 1 41641"

parse_options set --autostart --ssh --udp-port=4000 --hostname=lab-07 --proxy none
check "options for set" "$AUTOSTART $SSH $UDP_PORT $NODE_NAME $PROXY_OPTION" "1 1 4000 lab-07 none"
check "given lists the options on the command line" "$(given ssh && given hostname && ! given tags && echo yes)" yes
check "a UDP port below 1024 is refused" "$( (parse_options set --udp-port 80) >/dev/null 2>&1 || echo refused)" refused
check "set refuses an option that only install takes" "$( (parse_options set --tags tag:server) >/dev/null 2>&1 || echo refused)" refused
check "a switch takes no value" "$( (parse_options set --ssh=true) >/dev/null 2>&1 || echo refused)" refused
AUTO_UPDATE=1
parse_options install --version 1.104.6 --auto-update --authkey file:/x
check "a pinned version turns daily updates off" "$PIN_VERSION $AUTO_UPDATE $AUTHKEY" "1.104.6 0 file:/x"

# ---------------------------------------------------------------- auth keys

printf 'tskey-auth-abc\n' >"$SCRATCH/key"
AUTHKEY="file:$SCRATCH/key" TAGS=""
check "file:PATH reads the key from the file" "$(read_authkey)" tskey-auth-abc
AUTHKEY=tskey-client-xyz TAGS=tag:server
check "an OAuth client secret makes a persistent node" "$(read_authkey)" "tskey-client-xyz?ephemeral=false&preauthorized=true"
# shellcheck disable=SC2034  # read by read_authkey
AUTHKEY=tskey-client-xyz TAGS=""
check "an OAuth client secret needs tags" "$( (read_authkey) >/dev/null 2>&1 || echo refused)" refused

# ---------------------------------------------------------------- proxies

rm -f "$PROXY_FILE"
PROXY_OPTION=""
https_proxy=127.0.0.1:1089 save_proxy
check "the caller's proxy is saved, read as http://" "$(proxy_url)" http://127.0.0.1:1089
PROXY_OPTION=none
save_proxy
check "--proxy none saves no proxy" "$(proxy_url)" ""
PROXY_OPTION=""
https_proxy=http://127.0.0.1:1089 save_proxy
check "the caller's proxy doesn't replace a saved choice" "$(proxy_url)" ""
PROXY_OPTION=http://127.0.0.1:3128
save_proxy
PROXY_OPTION=socks5://127.0.0.1:1080
save_proxy 2>/dev/null
check "a socks5 proxy is refused and the saved one kept" "$(proxy_url)" http://127.0.0.1:3128
PROXY_OPTION=http://u:secret@127.0.0.1:9
save_proxy
check "the proxy is shown without credentials" "$(shown_proxy)" "http://***@127.0.0.1:9"
check "the proxy path exports the proxy" "$( (with_path proxy env) | grep -c '^https_proxy=http://u:secret@127.0.0.1:9$')" 1
check "the direct path clears every proxy variable" "$( (export HTTPS_PROXY=x ALL_PROXY=y no_proxy=z && with_path direct env) | grep -ciE '^(http|https|all|no)_proxy=')" 0
: >"$PROXY_FILE"
check "without a proxy only the direct path exists" "$(pick_path proxy)" direct

# ---------------------------------------------------------------- the shell hook

rc="$SCRATCH/rc"
printf 'line one\nline two\n' >"$rc"
cp "$rc" "$SCRATCH/rc.before"
AUTOSTART=1
rewrite_hook "$rc" add
rewrite_hook "$rc" add
check "the hook is added once" "$(grep -cxF "$HOOK_BEGIN" "$rc")" 1
check "the hook goes first, ahead of an early return" "$(head -n 1 "$rc")" "$HOOK_BEGIN"
check "with autostart on, the hook starts Tailspace" "$(grep -c ' autostart ' "$rc")" 1
rewrite_hook "$rc" remove
check "removing the hook restores the file byte for byte" "$(yes_if cmp -s "$rc" "$SCRATCH/rc.before")" yes
printf 'line one\nline two' >"$SCRATCH/rc-cut"
rewrite_hook "$SCRATCH/rc-cut" add
check "a last line without a newline survives" "$(tail -n 1 "$SCRATCH/rc-cut")" "line two"
printf '%s\nunterminated\n' "$HOOK_BEGIN" >"$rc"
rewrite_hook "$rc" add 2>/dev/null
check "a block without an end marker is left alone" "$(cat "$rc")" "$HOOK_BEGIN
unterminated"
AUTOSTART=0
check "with autostart off, the hook only sets PATH" "$(hook_block | grep -c autostart)" 0

# ---------------------------------------------------------------- the root filesystem

# One overlay seen from two mount namespaces, the host's own disk, a container whose / is a
# directory on that disk, and a tmpfs stacked on /.
printf '%s\n' '25 1 8:3 / /boot rw - xfs /dev/sda1 rw' \
  '26 1 0:52 / / rw - overlay overlay rw,upperdir=/var/lib/docker/overlay2/a/diff' >"$SCRATCH/overlay"
printf '%s\n' '731 1 0:52 / / rw - overlay overlay rw,upperdir=/var/lib/docker/overlay2/a/diff' >"$SCRATCH/overlay-again"
printf '%s\n' '41 1 8:3 / / rw - xfs /dev/sda3 rw' >"$SCRATCH/host"
printf '%s\n' '57 1 8:3 /var/lib/docker/vfs/dir/b / rw - xfs /dev/sda3 rw' >"$SCRATCH/directory"
printf '%s\n' '90 41 0:60 / / rw - tmpfs tmpfs rw' >"$SCRATCH/tmpfs"
cat "$SCRATCH/host" "$SCRATCH/tmpfs" >"$SCRATCH/stacked"
cat "$SCRATCH/tmpfs" "$SCRATCH/host" >"$SCRATCH/stacked-reversed"
printf '%s\n' '41 41 8:3 / / rw - xfs /dev/sda3 rw' >"$SCRATCH/own-parent"

check "the same filesystem reads the same under another mount ID" "$(root_fs "$SCRATCH/overlay-again")" "$(root_fs "$SCRATCH/overlay")"
check "a directory of the host's disk mounted on / isn't the host's /" "$(yes_if [ "$(root_fs "$SCRATCH/directory")" != "$(root_fs "$SCRATCH/host")" ])" yes
check "of mounts stacked on /, the top one counts" "$(root_fs "$SCRATCH/stacked")" "$(root_fs "$SCRATCH/tmpfs")"
check "...whatever order mountinfo lists them in" "$(root_fs "$SCRATCH/stacked-reversed")" "$(root_fs "$SCRATCH/tmpfs")"
check "a mount that is its own parent still counts" "$(root_fs "$SCRATCH/own-parent")" "8:3 / xfs /dev/sda3 rw"
check "root_fs reads this process's root filesystem" "$(yes_if [ -n "$(root_fs /proc/self/mountinfo)" ])" yes

# Remounts of a disk and of an overlay, and the overlay of another container.
printf '%s\n' '41 1 8:3 / / rw - ext4 /dev/sda3 rw,commit=5' >"$SCRATCH/ext4"
printf '%s\n' '41 1 8:3 / / rw - ext4 /dev/sda3 rw,commit=10' >"$SCRATCH/ext4-remounted"
printf '%s\n' '26 1 0:52 / / rw - overlay overlay rw,lowerdir=/l,upperdir=/var/lib/docker/overlay2/a/diff,workdir=/w' >"$SCRATCH/overlay-a"
printf '%s\n' '26 1 0:52 / / ro - overlay overlay ro,lowerdir=/l,upperdir=/var/lib/docker/overlay2/a/diff,workdir=/w' >"$SCRATCH/overlay-a-ro"
printf '%s\n' '26 1 0:52 / / rw - overlay overlay rw,lowerdir=/l,upperdir=/var/lib/docker/overlay2/b/diff,workdir=/w' >"$SCRATCH/overlay-b"
read -r kernel_boot </proc/sys/kernel/random/boot_id
token=$(current_boot "$SCRATCH/ext4")

check "the boot token starts with the kernel's boot ID" "${token%-*}" "$kernel_boot"
check "a remount keeps the boot token" "$(current_boot "$SCRATCH/ext4-remounted")" "$token"
check "...and so does an overlay's" "$(current_boot "$SCRATCH/overlay-a-ro")" "$(current_boot "$SCRATCH/overlay-a")"
check "another container's overlay changes it" "$(yes_if [ "$(current_boot "$SCRATCH/overlay-b")" != "$(current_boot "$SCRATCH/overlay-a")" ])" yes

# ---------------------------------------------------------------- versions

check "version_gt compares numerically" "$(version_gt 1.104.10 1.104.9 && echo yes)" yes
check "version_gt is strict" "$(version_gt 1.104.7 1.104.7 || echo no)" no

# ---------------------------------------------------------------- the stopped file

launch_supervisor() { LAUNCHED=1; }

# Prints 1 when autostart starts the supervisor, 0 when it leaves the server alone.
autostart_starts() {
  LAUNCHED=0
  cmd_autostart
  echo "$LAUNCHED"
}

# Runs give_up without stopping anything. Call it in a subshell.
give_up_quietly() {
  # shellcheck disable=SC2329  # called by give_up
  supervisor_shutdown() { :; }
  # shellcheck disable=SC2329  # called by give_up
  log() { :; }
  give_up "$1" test
}

rm -f "$STOPPED_FILE"
(give_up_quietly failing)
check "a give-up records the current boot" "$(cat "$STOPPED_FILE")" "failing $(current_boot)"
printf 'user\n' >"$STOPPED_FILE"
(give_up_quietly failing)
check "a give-up keeps a stop that came first" "$(cat "$STOPPED_FILE")" user

AUTOSTART=1
save_settings
rm -f "$STOPPED_FILE"
check "autostart starts a server that wasn't stopped" "$(autostart_starts)" 1
printf 'user\n' >"$STOPPED_FILE"
check "a stop holds" "$(autostart_starts)" 0
printf 'enroll-failed\n' >"$STOPPED_FILE"
check "a failed install holds" "$(autostart_starts)" 0
: >"$STOPPED_FILE"
check "an empty stopped file, as a full disk leaves, holds like a stop" "$(autostart_starts)" 0
printf 'failing %s\n' "$(current_boot)" >"$STOPPED_FILE"
check "a give-up holds for the rest of its boot" "$(autostart_starts)" 0
printf 'failing another-boot' >"$STOPPED_FILE"
check "a give-up record cut short holds" "$(autostart_starts)" 0
printf 'failing another-boot\n' >"$STOPPED_FILE"
check "a give-up from an earlier boot is retried" "$(autostart_starts)" 1
check "...and cleared" "$([ -e "$STOPPED_FILE" ] && echo kept || echo cleared)" cleared
printf 'needs-login another-boot\n' >"$STOPPED_FILE"
check "a login give-up from an earlier boot is retried" "$(autostart_starts)" 1
printf 'failing another-boot\n' >"$STOPPED_FILE"
AUTOSTART=0
save_settings
check "with autostart off, nothing starts" "$(autostart_starts)" 0

printf 'user\n' >"$STOPPED_FILE"
user_hint=$(stopped_hint)
: >"$STOPPED_FILE"
empty_hint=$(stopped_hint)
printf 'failing\n' >"$STOPPED_FILE"
failing_hint=$(stopped_hint)
printf 'failing %s\n' "$(current_boot)" >"$STOPPED_FILE"
check "the hint reads the reason and ignores the boot" "$(stopped_hint)" "$failing_hint"
check "a stop, a give-up and an empty file get different hints" "$(printf '%s\n' "$user_hint" "$empty_hint" "$failing_hint" | sort -u | grep -c .)" 3

# Runs cmd_stop with the stopped file at PATH and nothing to stop. Call it in a subshell.
stop_with_file() {
  STOPPED_FILE="$1"
  # shellcheck disable=SC2329  # called by cmd_stop
  stop_everything() { :; }
  cmd_stop
}

check "stop works when a full disk keeps the reason out" "$( (stop_with_file /dev/full) >/dev/null 2>&1 && echo stopped)" stopped
check "stop fails when the stopped file can't be created" "$( (stop_with_file "$SCRATCH/missing/stopped") >/dev/null 2>&1 || echo refused)" refused
# Root writes through file modes, so this needs a normal account.
if [ "$EUID" -ne 0 ]; then
  printf 'failing another-boot\n' >"$SCRATCH/read-only"
  chmod 444 "$SCRATCH/read-only"
  check "stop fails when an older reason can't be replaced" "$( (stop_with_file "$SCRATCH/read-only") >/dev/null 2>&1 || echo refused)" refused
fi

finish
