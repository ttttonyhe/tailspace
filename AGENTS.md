# AGENTS.md

Guidance for coding agents in this repository. Setup and reference for people live in `README.md` and `ADVANCED.md`.

## Project

Tailspace runs Tailscale without root. The product is one bash file, `tailspace`. It installs itself to `~/.tailspace`, supervises and updates tailscaled, and is the CLI.

| Path | Contents |
| --- | --- |
| `tailspace` | The whole program |
| `README.md`, `README.zh-CN.md` | The short version: why Tailspace exists, the one-line install, everyday commands |
| `ADVANCED.md`, `ADVANCED.zh-CN.md` | Everything else: auth keys, settings, proxies, how the server stays connected, reference |
| `assets/` | Logo, figures, social preview |
| `examples/policy.hujson` | Tailnet policy that `ADVANCED.md` refers to |
| `tests/` | Tests of the program, from single functions to a full install against Tailscale's servers |
| `.github/workflows/ci.yml` | CI: ShellCheck, the tests on bash 5 and bash 4.2, and the end-to-end test, also daily |

## Rules

Path-scoped rules live in `.rules/`. When you read a file that matches a rule's `paths:`, load that rule. Read every matching rule before you edit files or run commands in those paths.

### Rule map

| Rule | Paths | Covers |
| --- | --- | --- |
| `.rules/program.md` | `tailspace`, `tests/**`, `.github/**` | Bash portability, process identity, supervisor protocol, network paths, settings, secrets, verification, tests |
| `.rules/docs.md` | `README.md`, `README.zh-CN.md`, `ADVANCED.md`, `ADVANCED.zh-CN.md`, `examples/**`, `assets/**` | What goes in which document, voice, numbers and how to measure them, figures, the example policy |

### Maintaining rules

1. Write each new learning into the one rule whose `paths:` cover the files it concerns. Put only facts that hold for the whole repo in this file. Keep this file and every rule cohesive and under 200 lines.
2. Make every instruction specific and verifiable: why, where, what and how, citing the file, symbol or command. Remove generic best practices, vision statements and explanations of common terms.
3. `paths:` is a YAML list of repo-root-relative globs; `**` recurses and brace patterns such as `{svg,png}` work. A rule with `paths:` loads only when a matching file is read; a rule without it loads every session.
4. After adding or removing a rule file, update the rule map above. If two rules could conflict, fix one of them, because load order is unspecified.

## Facts for the whole repo

- The documents and `assets/*.svg` quote numbers from `tailspace`: `PROBE_INTERVAL`, `PROBE_FAILURES`, `DIRECT_LOSS_GRACE`, `PROXY_LOSS_GRACE`, `FAILBACK_HOLDDOWN`, `FAILBACK_CHECK`, `FAILBACK_HOLDDOWN_MAX`, `FLAP_WINDOW`, `FAILURE_LIMIT`, `RESTART_DELAY`, `UPDATE_HEALTH_TIMEOUT`, `UPDATE_SOAK`, `SESSION_WAIT_MINUTES`, `LOG_MAX_BYTES` and `SSH_FALLBACK_PORT`. `assets/paths-*.svg` draws the two grace periods as "wait 4 min" and "wait 1 min". They also quote the measurements listed in `.rules/docs.md`. Change all of them together.
- Never put an auth key or any other secret in a command line. Containers can share the host's PID namespace, so every user can read `/proc/*/cmdline`. Pass keys as `TS_AUTHKEY=file:PATH` with a 0600 file outside the repo.
- Tests against a real tailnet create real machines. Run them under a throwaway `HOME`, as `.rules/program.md` describes, and delete the machines in the admin console afterwards.
- Commit sources only. Rendered previews, downloaded tools and fonts stay outside the repo; the one rendered file in it is `assets/social-preview.png`.
