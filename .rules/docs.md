---
paths:
  - README.md
  - README.zh-CN.md
  - ADVANCED.md
  - ADVANCED.zh-CN.md
  - examples/**
  - assets/**
---

# Docs and figures

## The documents

- `README.md` is for someone who already uses Tailscale on their own devices. It says why Tailspace exists, gives one install command with nothing to fill in, says what the install prints, lists what Tailspace does, and shows the everyday commands. Auth keys, options, proxies, exact rules and reference material go in `ADVANCED.md`.
- `README.zh-CN.md` mirrors `README.md`, and `ADVANCED.zh-CN.md` mirrors `ADVANCED.md`: same sections in the same order, same tables, same figures. Change each pair in the same commit.
- Read every sentence as someone who has read only what comes before it. A sentence that would make that reader stop and ask "what does this mean" or "is that right" gets rewritten. Root, for example, is missing on the server, not on the reader's laptop.
- Write the way a colleague explains a tool: short sentences, active voice, contractions, sentence-case headings. Use Tailscale's own words, because readers know them from Tailscale: tailnet, device, admin console, coordination server, DERP relay, auth key, key expiry, tag, check mode. Keep one word per thing within these files, such as the supervisor, the direct path and the proxy path, the shell check and the cron job.
- No em or en dashes, and colons only before a list, a table or an example. Parentheses in prose only for a short gloss, as in "root (admin)" at the top of the README. No puffery, hedging or filler. Bold lead-ins end with a period and are followed by new information, as in the Troubleshooting list.
- The slogans are exact: "Run Tailscale in Rootless Mode" and "非 Root 身份运行 Tailscale".
- In Chinese, put a space between Chinese and Latin letters or digits, as the slogan does, and use full-width punctuation. Call the supervisor 监管进程, so readers don't take it for tailscaled. 重启 always names its object, 重启服务器 or 重启 Tailscale, because the word means both reboot and restart.
- Exact rules go in `<details>` blocks in `ADVANCED.md`.
- The status texts quoted in "When Tailspace gives up" are copied from `stopped_hint` in `tailspace`, and Tailscale facts such as the 180-day key expiry and the 12-hour check period come from Tailscale's documentation. Check both after every edit.

## Numbers

Every number says where it was measured. The current ones come from a Kubernetes pod with 124 usable cores and 1,435 visible processes, running Tailscale 1.104.7. Re-measure on one server, and update every place a number appears, `assets/metrics-*.svg` included.

| Number | How to measure |
| --- | --- |
| Time added to each new shell | 100 runs of `bash -c` with the autostart line that `hook_block` writes, minus 100 runs of `bash -c :` |
| Share of one core at idle | Over 300 s, the change in fields 14 to 17 of `/proc/PID/stat`, which are utime, stime, cutime and cstime, for tailscaled, the supervisor and the supervisor's children, divided by `getconf CLK_TCK` and by the window |
| Memory at idle | Sum of the `Pss:` lines in `/proc/PID/smaps` for the same processes, with no session open |
| Threads and CPU per probe | `Threads:` in `/proc/PID/status`, and bash `time` over 10 runs of `tailscale status --json --peers=false`, with and without `GOMAXPROCS=8` |
| Userspace networking throughput | Median of 3 runs sending 1 GiB through `tailscale nc` to the node's own tailnet IPv4 address, into a listener on 127.0.0.1 that discards it. It leaves out WireGuard and UDP, which the documents' wording reflects |

## Figures

- `assets/` holds pairs: `logo`, `hero`, `metrics` and `paths`, each as `-light.svg` and `-dark.svg`. The two files of a pair differ only in their `<style>` block, so `diff assets/hero-light.svg assets/hero-dark.svg` lists style lines and nothing else. Edit the light file, then copy it and swap the palette.
- The documents embed each pair with `<picture>` and a `(prefers-color-scheme: dark)` source, the pattern GitHub documents for theme-aware images. An `@media` rule inside one SVG would not follow GitHub's theme setting.
- Palette, light: ink `#2c2b31`, rules `#e4e4e7` or `#d4d4d8`, idle parts `#d4d4d8` filled and `#a1a1aa` stroked, labels `#71717a`, values `#18181b`, blue text `#3d64d8`. Dark: ink `#a1a1aa`, rules `#27272a` or `#3f3f46`, idle parts `#3f3f46` and `#52525b`, labels `#8b8b94`, values `#ededed`, blue text `#6b8ff7`. Blue `#4c78f5`, stroked `#3d64d8` on light and `#6b8ff7` on dark, marks only what belongs to the user: unit 05, the link, the cursor, the path in use.
- ViewBoxes are 880 wide, with content running from x=0 to x=880, so stacked figures share both edges. GitHub's repository page shows README images at up to about 830 px, so they render at 94%. Labels are 11px monospace with `letter-spacing: .02em`. Repeated shapes are `<defs>` plus `<use>`, which keeps each file editable by hand.
- Text uses system font stacks, `ui-monospace, SFMono-Regular, Menlo, Consolas, ...` and `-apple-system, BlinkMacSystemFont, "Segoe UI", ...`, because GitHub serves SVGs as images, and images can't load web fonts.
- Each figure's `<picture>` carries alt text that describes it in full, in both languages; keep it in step with the drawing. The logo is decorative and keeps `alt=""`.
- `assets/social-preview.png` is 1280 by 640, rendered from `assets/social-preview.svg` with `Geist-Regular.ttf` from the Geist font release: `resvg --skip-system-fonts --use-fonts-dir DIR social-preview.svg social-preview.png`. It carries the wordmark and the slogan, and no labels or captions. GitHub doesn't read it from the repo; upload it under Settings, General, Social preview.
- Check every changed figure with resvg 0.23 or newer, light on `#ffffff` and dark on `#0d1117`, for example `resvg --background '#0d1117' --use-fonts-dir DIR --sans-serif-family Geist --monospace-family 'DejaVu Sans Mono' in.svg out.png`, and look at the result.

## examples/policy.hujson

- It is a complete policy that the admin console must accept as is. `ADVANCED.md` describes three parts of it, so keep them: `tagOwners` for `tag:server`; the `ssh` rule for `tag:server` with `autogroup:nonroot`, because Tailscale SSH can only log in as the account running tailscaled; and `nodeAttrs` with `cache-network-maps`, which needs Tailscale 1.104 or newer. `cmd_status` in `tailspace` looks for `cache-network-maps` to decide whether to print its tip.
- After an edit, strip the `//` comments and trailing commas and parse the rest as JSON to catch syntax errors.
