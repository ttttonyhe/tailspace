<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
  <img src="assets/logo-light.svg" alt="" width="56" height="56">
</picture>

# Tailspace

**Run Tailscale in Rootless Mode**

Installing [Tailscale](https://tailscale.com) on a remote Linux server normally requires root (admin) access via `sudo`, `/dev/net/tun`, and `systemd`. On a shared server such as an HPC login node, a Slurm cluster, a Kubernetes pod, or an unprivileged Docker container, you usually have none of those. Tailspace runs `tailscaled` in [userspace networking mode](https://tailscale.com/docs/concepts/userspace-networking) with `--tun=userspace-networking` inside your home directory without root, so you can reach the server with SSH, VS Code Remote-SSH, or Jupyter from any device on your tailnet.

English · [简体中文](README.zh-CN.md) · [Guides and docs](https://ttttonyhe.github.io/tailspace/)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/hero-dark.svg">
  <img src="assets/hero-light.svg" alt="A shared cluster with no root access, drawn as nine servers in a rack. Server 05 is yours: Tailspace runs Tailscale there, inside your home directory, and connects it to your laptop, where an SSH session is open.">
</picture>

## Install

If the server belongs to a shared cluster, check its rules first. Tailspace keeps Tailscale running in the background, and Tailscale SSH skips the cluster's own two-factor check. Some clusters forbid one or both.

On the server, run:

```bash
curl -fsSL https://raw.githubusercontent.com/ttttonyhe/tailspace/main/tailspace | bash
```

Open the link it prints and log in, the same way you'd add any other device to your tailnet. Once the install finishes, it prints an SSH command you can run from any of your devices.

Tailscale expires device keys after 180 days by default. To keep the server connected for good, [disable key expiry](https://tailscale.com/kb/1028/key-expiry) for it in the admin console.

## What it does

Without root or `systemd`, Tailscale can't run as a system service, so Tailspace sets it up in userspace mode and looks after it for you:

- Turns on Tailscale SSH on port 22, forwards OpenSSH on port 2222 when the server runs OpenSSH, and lets you reach local ports such as Jupyter or TensorBoard over your tailnet.
- Restarts `tailscaled` if it crashes, hangs, or gets stuck offline while the network works.
- Starts Tailscale again after the server reboots, right away if the server has cron, or else the next time you log in.
- Switches between a direct connection and your HTTP proxy, if the server has one, whenever either goes down.
- Updates Tailscale daily, waiting up to 3 days for your sessions to end, and rolls back if a new version doesn't work.
- Keeps other users on a shared server off your tailnet, without opening unauthenticated SOCKS5 or HTTP proxies.
- Stops and tells you why when it needs your help, instead of retrying forever.

It's light, too:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/metrics-dark.svg">
  <img src="assets/metrics-light.svg" alt="Measured on a Kubernetes pod running Tailscale 1.104.7: 0.9 milliseconds added to each new shell, and while idle, 0.14 percent of one CPU core and 30 megabytes of memory.">
</picture>

## Usage

```bash
tailspace status      # what it's doing, and why
tailspace stop        # stop it, and keep it stopped across reboots
tailspace start       # start it again
tailspace self-update # update Tailspace itself
tailspace uninstall   # log the server out and remove everything
```

See [ADVANCED.md](ADVANCED.md) for auth keys, proxies, settings, and reference details. The [project site](https://ttttonyhe.github.io/tailspace/) adds the [CLI reference](https://ttttonyhe.github.io/tailspace/reference/) and guides for [HPC and Slurm](https://ttttonyhe.github.io/tailspace/guides/hpc-slurm/), [Kubernetes and Docker](https://ttttonyhe.github.io/tailspace/guides/kubernetes-docker/), [VS Code and Jupyter](https://ttttonyhe.github.io/tailspace/guides/vscode-jupyter-ssh/), [HTTP proxy failover](https://ttttonyhe.github.io/tailspace/guides/proxy-failover/), [comparing with manual setups](https://ttttonyhe.github.io/tailspace/guides/vs-manual-userspace/), and [troubleshooting](https://ttttonyhe.github.io/tailspace/guides/troubleshooting/).

Tailspace is a single bash script under the [MIT license](LICENSE), and isn't affiliated with Tailscale Inc.
