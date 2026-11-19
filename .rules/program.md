---
paths:
  - tailspace
  - .github/**
---

# The tailspace program

## Layout

- The header comment of `tailspace` lists the sections in reading order, and the `# ----` markers delimit them. Put a new function in the section it belongs to, and keep the header list in step with the markers.
- The file must end with the single line `main "$@"; exit`. bash reads a script while it runs it, and with both commands on one line it has read the `exit` before `main` starts, so a file overwritten in place can't feed it new commands. `install_program` replaces the file by rename, which is safe anyway.
- `TAILSPACE_VERSION` is the only version string. `usage()` is the reference for commands and options, and the option tables in `ADVANCED.md` and `ADVANCED.zh-CN.md` mirror it.

## Bash on CentOS 7: bash 4.2, util-linux 2.23

- No `set -e` and no `pipefail`. Probes such as `status_json` and `path_works` fail as a matter of course, and callers test their status explicitly.
- `set -u` is on. bash 4.2 calls an empty `"${array[@]}"` unbound, so test the length first, as `cleanup_tmp` does with `TMP_PATHS`.
- `setsid -f` doesn't exist there. Detach with `setsid ... &`, as `launch_supervisor` does.
- No here-strings, and no here-documents outside `usage()`: bash writes them to a temporary file, which fails when /tmp is full. `proc_field` splits with an array assignment instead.
- Wait on deadlines against `$SECONDS` whenever a single check can block, as `wait_until`, `cycle_daemon` and `stop_pid` do, because one `status_json` can take `PROBE_TIMEOUT` seconds.
- A command substitution in the supervisor holds the lock, and a TERM waits until it finishes: bash keeps fd 9 open in the forked shell, even with `9>&-` on a function inside. Long work runs as a background job that closes the lock first and is awaited with `wait`, as the path tests in `cmd_supervise` do with `(exec 9>&- && pick_path ...) &`.
- A function that sets globals must not run inside `$(...)`, which forks. The EXIT trap doesn't fire in that fork either, which is why `latest_version` deletes its own temporary file.
- Inside `$(...)`, `$BASHPID` is the subshell's PID. Background loops copy it first: `local self="$BASHPID"` in `watch_daemon` and `update_loop`.
- Read `status --json` with `json_string`, `json_bool` and `node_ip`, which match with `[[ =~ ]]`. The first match is the right one, because ipnstate.Status orders Version and BackendState before Self, and Self before ExitNodeStatus and Peer.
- `load_settings` reads `config` with a `read` loop and no forks, because the shell hook calls it at every login.
- `install_hooks` adds the cron job only when `cron_runs` finds a `cron` or `crond` process with the same root mount ID as ours, and removes it otherwise. With `hostPID`, a pod sees the host's crond, which reads the host's crontabs; with `hidepid`, no daemon is visible, so `cron_runs` assumes one. Keep this scan out of the shell hook, because it reads every process's `comm`.

## Process identity

- Containers may share the host's PID namespace, so `ps`, `pgrep` and name matching would find other users' processes. Identify processes by what they hold, from `/proc` only.
- The supervisor opens `state/HOST/lock` for appending as fd 9 and flocks it in `cmd_supervise`. `lock_holders` lists every PID whose `/proc/PID/fd/9` is that file, and `is_supervisor` picks the one that leads its session, with PID equal to SID from `proc_field PID 3`, and has comm `tailspace`.
- tailscaled must never get fd 9: `start_daemon` passes `9>&-`. tailscaled hands open descriptors to the SSH sessions it starts, so an inherited lock would outlive tailscaled and turn session processes into lock holders.
- `daemon_pids` finds tailscaled by comm `tailscaled` plus the argument `--statedir=$STATE_DIR` in `/proc/PID/cmdline`. Its SSH helpers run as `tailscaled be-child ...` and don't match.
- Long-lived children close the lock: `watch_daemon ... 9>&- &`, `update_loop 9>&- &`, the backoff `sleep "$delay" 9>&- &` and the path tests above. A background function with `9>&-` keeps no copy of the lock; only command substitutions do. `launch_supervisor` passes `8>&-`, so the supervisor never holds the install lock that `prefix_busy` tests.
- Locks are taken on files opened for appending, tested with `lock_free`, never on directories: NFS grants exclusive locks only on files open for writing, and flock(1) opens its file read-only.
- `supervisor.pid` only lets `launch_supervisor` skip the `/proc` scan on every new shell, about 9 ms with 1,400 processes. `supervisor_running` re-checks fd 9, session leadership and comm, so a stale or reused PID fails. The lock held by `cmd_supervise` is the real guarantee.
- `stop_pid` treats zombies as gone through `alive`, because a container without an init never reaps them. Before signalling a stored child PID, `kill_child` checks `is_child_of`.

## Supervisor protocol

- The watcher ends a tailscaled run with `restart_for REASON MESSAGE`, which writes REASON to `restart-reason` and then stops tailscaled. `cmd_supervise` reads it after `wait`. Reasons: `hung`, `stuck`, `failover`, `failback`, `needs-login`, plus `update`, which `cycle_daemon` writes. A new reason needs a branch in the `case` of `cmd_supervise`.
- An empty reason is a crash. Crashes, `hung` and `stuck` count as failures, and `FAILURE_LIMIT` in a row end the supervisor with `give_up failing`, but never while `prefix_busy`: an install or update is then judging the binaries and will put the old ones back. The watcher creates `online` the first time a run reaches Tailscale, and the supervisor resets the count when it finds that file.
- `stopped` records why Tailspace stopped: `user` from `cmd_stop` and `cmd_uninstall`, `needs-login` and `failing` from `give_up`, `enroll-failed` from `enroll`. `cmd_autostart`, `cmd_supervise` and its loop all stop when the file exists. `stopped_hint` turns each value into the text `status` prints.
- A new supervisor starts from the path recorded in `state/HOST/path`. `pick_path` keeps that path while it passes `path_works`, and returns `direct` when no proxy is saved; only `failover` and `failback` switch without testing.
- `GOMAXPROCS` is exported once in `cmd_supervise`, so tailscaled, the watcher's CLI probes and the updater inherit it.
- `cycle_daemon` returns 0 for a healthy release, 1 for a broken one, and 2 when it can't tell because Tailspace stopped or no path works. Only 1 writes `bad-version`.

## Network paths and settings

- `with_path PATH CMD...` replaces the calling shell with CMD in that path's environment. Call it in the background, in a subshell, in a pipeline, or last. Proxies travel in the environment, never in arguments, because every user can read `/proc/PID/cmdline`.
- tailscaled honours only `http://` proxies and ignores `ALL_PROXY`, so `save_proxy` refuses other schemes. An empty `proxy` file records that no proxy is wanted; the caller's proxy variables count only while the file doesn't exist.
- `tailscale debug ts2021` exits 0 even when the handshake fails, so `path_works` greps its output for `did noise handshake`.
- Probes cap curl at `PATH_PROBE_TIMEOUT` through the fourth argument of `download`; only full downloads retry.
- `parse_options` rewrites `--name=value` into two arguments and records every option in `GIVEN`. `cmd_set` applies only the options `given` reports, because hosts that share a home share the saved settings.
- `enroll` repeats the node's current `Hostname` and `AdvertiseTags`, read from `tailscale debug prefs`, on `tailscale up`, which refuses to run on a node that joined before unless every setting that differs from the default is repeated. If it still refuses, with "requires mentioning all", `enroll` points at the command Tailscale printed and writes no `enroll-failed`.
- `owned_prefix`, a `config` file plus a `state/` directory, decides whether a directory is Tailspace's. `prepare_directories` refuses any other non-empty prefix and writes `config` first, and `cmd_uninstall` refuses to delete from a prefix that fails the test.

## Secrets

- `enroll` hands the auth key to `tailscale up` as `--auth-key=file:<(printf ...)`, a pipe, so it never reaches the disk or a command line. Never pass a key as an argument, and never echo it.
- `prepare_directories` makes the prefix and the state directory mode 700.

## Verify

1. `bash -n tailspace && shellcheck -s bash tailspace` with ShellCheck 0.11.0, the release `.github/workflows/shellcheck.yml` pins; bump both together. CI also runs `bash -n` and `help` in the `bash:4.2` image.
2. Supervisor decisions run without a tailnet. In a scratch script, source the functions with `source <(sed -n '1,/^main "\$@"; exit$/p' tailspace | sed '$d')`, then run `set_paths "$(mktemp -d)"; mkdir -p "$STATE_DIR"; : >"$LOG"; HOLDDOWN="$FAILBACK_HOLDDOWN"`. Stub `status_json`, `path_works`, `proxy_url`, `prefix_busy`, `restart_for`, which records its reason and `$SECONDS` and exits, and `sleep`, which adds its argument to `SECONDS`. Keep stub variables clear of the watcher's locals `status`, `state`, `path`, `grace` and `failures`. Run `( watch_daemon direct )` in a subshell, because the loop ends unless `is_child_of` finds the caller as parent. Expected: failover at 260 s on direct, also from NoState and Starting, and at 80 s on proxy; failover within a minute after the proxy returns during an outage; failback at 1200 s; stuck at 500 s; needs-login at 140 s; hung at 60 s.
3. Failure accounting runs offline as well. Build a scratch prefix with a copy of `tailspace`, a `state/HOST/` directory holding an empty `proxy` file, and `bin/tailscaled` and `bin/tailscale` replaced by scripts that exit 1 after a second. `autostart` must stop with `failing` after about 80 s, and `stop` during a backoff must return at once. With the prefix lock held by another process, the supervisor must keep restarting every 40 s and stop only after the lock is released.
4. Live, against a real tailnet, under a throwaway home so nothing touches your own install:

   ```bash
   export HOME=$(mktemp -d) TS_AUTHKEY=file:/path/to/0600-key
   ./tailspace install --hostname ts-selftest
   ./tailspace status; ./tailspace stop; ./tailspace start; ./tailspace restart
   ./tailspace uninstall
   ```

   The crontab belongs to the user, not to `HOME`. Test lines carry the throwaway prefix in their marker, and `uninstall` removes them. Delete `ts-selftest` in the admin console afterwards. To swap a binary under a running test install, rename a new file over it: writing into a running binary fails with "Text file busy".
