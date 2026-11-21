<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
  <img src="assets/logo-light.svg" alt="" width="56" height="56">
</picture>

# Tailspace

**非 Root 身份运行 Tailscale**

在远程 Linux 服务器上常规安装 [Tailscale](https://tailscale.com) 需要 root（管理员）权限、`sudo`、`/dev/net/tun` 和 `systemd`。在 HPC 登录节点、Slurm 集群、Kubernetes Pod 或无特权 Docker 容器这类共享服务器上，这些条件通常都没有。Tailspace 会在你的家目录里以 [userspace 网络模式](https://tailscale.com/docs/concepts/userspace-networking)（`--tun=userspace-networking`）免 root 运行 `tailscaled`，让你通过 SSH、VS Code Remote-SSH 或 Jupyter 从 tailnet 里的任何设备连上服务器。

[English](README.md) · 简体中文 · [指南与文档](https://ttttonyhe.github.io/tailspace/zh/)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/hero-dark.svg">
  <img src="assets/hero-light.svg" alt="一个没有 root 权限的共享集群，画成机柜里的九台服务器。05 号是你的服务器：Tailspace 在你的家目录里运行 Tailscale，并把它连到你的笔记本，笔记本上开着一个 SSH 会话。">
</picture>

## 安装

如果服务器属于某个共享集群，先看看集群的规定。Tailspace 会让 Tailscale 一直在后台运行，Tailscale SSH 也会绕过集群自己的两步验证，有些集群禁止其中一项或两项。

在服务器上运行：

```bash
curl -fsSL https://raw.githubusercontent.com/ttttonyhe/tailspace/main/tailspace | bash
```

打开它打印出的链接并登录，就像往 tailnet 里添加其他设备一样。安装完成后，它会打印一条 SSH 命令，在你的任何设备上运行即可连上服务器。

Tailscale 的设备密钥默认 180 天后过期。想让服务器一直保持连接，就在管理后台为它[关闭密钥过期](https://tailscale.com/kb/1028/key-expiry)。

## 它会做什么

没有 root 或 `systemd`，Tailscale 没法作为系统服务运行，所以由 Tailspace 以 userspace 模式替你装好并照看它：

- 在 22 端口开启 Tailscale SSH，在服务器运行 OpenSSH 时把它转发到 2222 端口，并让你通过 tailnet 访问 Jupyter、TensorBoard 等本地端口。
- `tailscaled` 崩溃、无响应或在网络正常时卡在离线状态，就重启 Tailscale。
- 服务器重启后再次启动 Tailscale：有 cron 的服务器上立即启动，否则等你下次登录时启动。
- 如果服务器用 HTTP 代理上网，直连和代理哪个断了，就切到另一个。
- 每天更新 Tailscale，最多等 3 天让你的会话结束，新版本有问题就回滚。
- 让共享服务器上的其他用户用不了你的 tailnet，也不开启无密码的 SOCKS5 或 HTTP 代理。
- 遇到需要你处理的问题，停下来告诉你原因，而不是无休止地重试。

而且它很轻：

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/metrics-dark.svg">
  <img src="assets/metrics-light.svg" alt="在一个运行 Tailscale 1.104.7 的 Kubernetes Pod 上测得：每个新 shell 多 0.9 毫秒，空闲时占用一个 CPU 核心的 0.14% 和 30 MB 内存。">
</picture>

## 用法

```bash
tailspace status      # 在做什么，为什么
tailspace stop        # 停止，服务器重启后也保持停止
tailspace start       # 重新启动
tailspace self-update # 更新 Tailspace 自身
tailspace uninstall   # 让服务器登出，并删除一切
```

auth key、代理、各项设置与参考信息，见 [ADVANCED.zh-CN.md](ADVANCED.zh-CN.md)。[项目主页](https://ttttonyhe.github.io/tailspace/zh/)还提供[命令参考](https://ttttonyhe.github.io/tailspace/zh/reference/)以及[超算与 Slurm](https://ttttonyhe.github.io/tailspace/zh/guides/hpc-slurm/)、[Kubernetes 与容器](https://ttttonyhe.github.io/tailspace/zh/guides/kubernetes-docker/)、[VS Code 与 Jupyter](https://ttttonyhe.github.io/tailspace/zh/guides/vscode-jupyter-ssh/)、[HTTP 代理切换](https://ttttonyhe.github.io/tailspace/zh/guides/proxy-failover/)、[与手动方案对比](https://ttttonyhe.github.io/tailspace/zh/guides/vs-manual-userspace/)和[故障排查](https://ttttonyhe.github.io/tailspace/zh/guides/troubleshooting/)专题指南。

Tailspace 是一个 bash 脚本，以 [MIT 许可证](LICENSE)发布，与 Tailscale Inc. 没有关联。
