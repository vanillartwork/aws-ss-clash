# Getting Started

[English](#Guide) · [中文](#指南)

This guide takes you from a bare Linux server to a working node and imported
client. Every step here is shared by both node types — for node-specific options
see [exit](exit.md) and [relay](relay.md).

Examples use the documentation IP `203.0.113.10`; substitute your own server's
address throughout.

---

## Guide

### 1. Prerequisites

#### 1.1 Choose a VPS

You need a Linux server with a public IP address (IPv4 or IPv6) and SSH access.
Any major cloud hosting provider is compatible, including AWS, Google Cloud,
Oracle Cloud, Microsoft Azure or low-cost VPS hosts. Ubuntu Server (24.04
LTS or newer) is recommended. A minimum resource specification (e.g., 1 vCPU,
512MB RAM) is more than sufficient for personal proxy requirements.

**Example: AWS EC2**

Recommended operating system:

```text
Ubuntu Server 26.04 LTS
```

Recommended instance type for personal use:

```text
t3.micro
```

When creating the instance:

- Create a new SSH key pair, or select an existing one (see [1.2](#12-create-an-ssh-key-pair)).
- Allow inbound TCP ports `22`, `443`, and `8080` in the security group (see [1.3](#13-configure-the-firewall)).
- Assign a public IPv4 (or IPv6) address.

Cloud providers usually provide the private key as a file to download once — keep it safe, as
it cannot be downloaded again.

#### 1.2 Create an SSH Key Pair

SSH authentication relies on public-key cryptography: a **private key** that
remains secure on your local machine, and a corresponding **public key** deployed
to the server.

Some providers generate a key pair for you during instance creation (for example AWS gives
you a private key to download). Others ask you to upload an existing
public key. If you do not have a key pair yet, generate one locally — the full
walkthrough is in [Appendix A](#a-ssh-key-generation).

By default, keys live in the `~/.ssh` directory with standard filenames that most
SSH clients pick up automatically:

| Algorithm | Private key | Public key |
|---|---|---|
| ED25519 | `id_ed25519` | `id_ed25519.pub` |
| RSA | `id_rsa` | `id_rsa.pub` |
| ECDSA | `id_ecdsa` | `id_ecdsa.pub` |

Only the `.pub` public key is uploaded to your provider. **Never share the
private key.**

#### 1.3 Configure the Firewall

Configure your cloud provider's network security group or firewall to permit inbound
TCP connections on the following ports:

| Port | Source | Purpose |
|---|---|---|
| `22` | your IP | SSH login |
| `443` | `0.0.0.0/0` (and `::/0` on IPv6) | the node itself |
| `8080` | your IP if possible | HTTP subscription (optional) |

Notes:

- **No UDP needed**: Xray VLESS Reality is built on the TCP transport protocol;
  opening UDP ports is unnecessary.
- **Sensitive data protection**: Because HTTP subscription links contain your full
  client config, restrict access to port `8080` to your trusted IP ranges, or
  disable subscription hosting entirely after initial client setup.
- **Relay configuration**: In a relay architecture, the exit node only needs to
  open its proxy port (default `443`) to the relay node's IP address — see
  [relay](relay.md).

> [!WARNING]
> **Common firewall pitfall.** Opening ports in the cloud console is not always
> enough. Many Linux images run a local software firewall (`ufw` or `firewalld`)
> that can silently block traffic even when the cloud rule is correct. If a port
> looks open in the console but the client still cannot connect, see
> [Appendix B](#b-firewall-ufw--firewalld).

#### 1.4 Connect via SSH

Open a terminal on your computer and use the following command:

```bash
ssh -i [KEY_FILE] [USERNAME]@[SERVER_PUBLIC_IP]
```

- `[KEY_FILE]` — path to your private key (for example `key.pem`, or `~/.ssh/id_ed25519`).
- `[USERNAME]` — the default login user. Ubuntu images use `ubuntu`; others may use `root`, `debian`, or `admin`.
- `[SERVER_PUBLIC_IP]` — your server's public IP address.

Example:

```bash
ssh -i key.pem ubuntu@203.0.113.10
```

On the first connection you will be asked to confirm the server's fingerprint;
type `yes` to continue.

### 2. Install RayLink

#### Exit Node

An **exit node** serves as the direct link to the destination internet. Clients
connect directly to the exit node's public interface, which forwards traffic out to
the web. Execute the following command in your server's shell:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh | sudo bash -s -- exit
```

When it finishes, the installer prints your subscription URLs (also saved to
`/opt/cloud-xray-exit/server-info.txt`). Continue to [3](#3-import-into-clients).

To customize the install (ports, DNS profile, IPv6, etc.), pass environment
variables — see [configuration](configuration.md). Example, using port `8443`:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh | sudo env PORT=8443 bash -s -- exit
```

#### Relay Node

A **relay node** forwards client traffic through an intermediary transit server
before sending it to the exit node, securing and stabilizing the connection path
(`Client → Relay → Exit → Internet`). Deploy your exit node first, retrieve its
**Universal Subscription URL**, and then run the following bootstrap command on your
secondary (relay) server:

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh | sudo env UPSTREAM_SUBSCRIPTION_URL='http://203.0.113.10:8080/sub/TOKEN' bash -s -- relay
```

Replace `203.0.113.10:8080/sub/TOKEN` with your exit's actual Universal
Subscription URL. See [relay](relay.md) for other ways to supply the upstream.

### 3. Import into Clients

The installer serves three link types. Use the one your client supports (see [Appendix C](#c-recommended-clients-by-os) for platform-specific client recommendations):

| Link | Endpoint |
|---|---|
| **Universal Subscription URL** | `http://SERVER:8080/sub/TOKEN` |
| **Clash Subscription URL** | `http://SERVER:8080/sub/TOKEN/clash.yaml` |
| **Direct VLESS Link** | `vless://…` |

When HTTP subscription is enabled, the installer prints the two subscription
URLs; when it is disabled, it prints the Direct VLESS Link instead.

For Clash/Mihomo clients: import the Clash Subscription URL, select your node
under the `GLOBAL` proxy group, then enable system proxy or TUN mode.

To view the Direct VLESS Link on the server (an exit node shown; a relay uses
`/opt/cloud-xray-relay`):

```bash
sudo cat /opt/cloud-xray-exit/vless-uri.txt
```

> [!NOTE]
> The Clash YAML and the VLESS URI intentionally keep their own field names
> This is expected — do not rename them.

### 4. Download Configuration

To copy a generated file to your computer, use `scp` from your **local**
terminal:

```bash
scp -i [KEY_FILE] [USERNAME]@[SERVER_PUBLIC_IP]:[REMOTE_PATH] [LOCAL_PATH]
```

Example — download the Clash config:

```bash
scp -i key.pem ubuntu@203.0.113.10:/opt/cloud-xray-exit/clash.yaml ./raylink-clash.yaml
```

Example — download the Direct VLESS Link file:

```bash
scp -i key.pem ubuntu@203.0.113.10:/opt/cloud-xray-exit/vless-uri.txt ./vless-uri.txt
```

### 5. Next Steps

Manage the node any time from the server:

```bash
sudo raylink exit                 # re-run / update (safe, idempotent)
sudo raylink exit --health-check  # run a health check now
sudo raylink version
```

A systemd timer already re-checks the node periodically and self-heals. To learn
more:

- [exit](exit.md) — exit-node install, options, and health check.
- [relay](relay.md) — relay model, upstream parameters, and firewall.
- [configuration](configuration.md) — every environment variable.
- [troubleshooting](troubleshooting.md) — common issues, IPv6, uninstall.

---

## Appendix

### A. SSH Key Generation

If you do not already have an SSH key pair, you must generate one locally.
ED25519 is recommended for modern security and performance; RSA 4096-bit is a widely
compatible legacy fallback.

To generate an ED25519 key pair at the default location (`~/.ssh/id_ed25519`):

```bash
ssh-keygen -t ed25519 -C "you@example.com"
```

Or a legacy RSA 4096-bit key pair:

```bash
ssh-keygen -t rsa -b 4096 -C "you@example.com" -f ~/.ssh/id_rsa
```

You will be prompted for a private key passphrase:

- **Leave it empty** (press Enter twice) for convenience.
- **Set a passphrase** for better security — you will enter it whenever the key
  is used.

Press Enter to accept the default save location. Afterwards you have two files:

- `id_ed25519` (or `id_rsa`) — the **private key**. Never share it.
- `id_ed25519.pub` (or `id_rsa.pub`) — the **public key**. Safe to upload to your
  VPS provider.

Copy the public key to your clipboard, then paste it into your provider's
**SSH Keys** page (the "Key Name" is just a label and does not affect
authentication):

```bash
# macOS
pbcopy < ~/.ssh/id_ed25519.pub

# Linux (X11 / Wayland)
xclip -sel clip < ~/.ssh/id_ed25519.pub   # or: wl-copy < ~/.ssh/id_ed25519.pub
```

```powershell
# Windows (PowerShell)
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub" | Set-Clipboard
```

### B. Firewall (ufw / firewalld)

Opening ports in your cloud provider's web console may not be sufficient if your
server's operating system runs a local software firewall. You should only configure
the firewall that is **already active** on your system; do not enable a firewall
daemon solely for RayLink.

**ufw (Debian/Ubuntu).** Check whether it is active:

```bash
sudo ufw status
```

If the output starts with `Status: active`, allow the ports:

```bash
sudo ufw allow 443/tcp
sudo ufw allow 8080/tcp
sudo ufw reload
```

**firewalld (RHEL/Fedora/CentOS).** Check whether it is running:

```bash
sudo systemctl is-active firewalld
```

If the output is `active`, allow the ports and reload:

```bash
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

Verify:

```bash
sudo firewall-cmd --list-ports
# expected: 443/tcp 8080/tcp
```

### C. Recommended Clients by OS

Below is a list of recommended mainstream clients categorized by operating system, along with the link types they support (Universal, Clash, or VLESS).

- **Windows**
  - [v2rayN](https://github.com/2dust/v2rayN) — Supports **Universal**, **VLESS**
  - [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev) — Supports **Clash**
  - [FlClash](https://github.com/flclash/FlClash) — Supports **Clash**, **Universal**
  - [Hiddify](https://github.com/hiddify/hiddify-next) — Supports **Universal**, **VLESS**

- **Android**
  - [v2rayNG](https://github.com/2dust/v2rayNG) — Supports **Universal**, **VLESS**
  - [Hiddify](https://github.com/hiddify/hiddify-next) — Supports **Universal**, **VLESS**
  - [FlClash](https://github.com/flclash/FlClash) — Supports **Clash**, **Universal**
  - [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid) — Supports **Universal**, **VLESS**

- **iOS / macOS & tvOS**
  - [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118) — Supports **Universal**, **VLESS**
  - [Anywhere](https://github.com/NodePassProject/Anywhere) — Supports **Universal**, **VLESS**
  - [Egern](https://apps.apple.com/us/app/egern/id1616105820) — Supports **Universal**, **VLESS**

---

## 指南

本指南将协助您在一台全新的 Linux 服务器上完成节点部署与客户端配置导入。本教程中的步骤适用于所有类型的节点，针对特定节点类型的详细选项请参阅 [exit](exit.md) 与 [relay](relay.md)。

本文所有示例均使用文档保留 IP `203.0.113.10`，请在实际操作中替换为您服务器的公网 IP 地址。

### 1. 准备工作

#### 1.1 选择 VPS

您需要准备一台配置有公网 IP（支持 IPv4 或 IPv6）且启用了 SSH 登录的 Linux 云服务器。常见的服务商（如 AWS、Google Cloud、Oracle Cloud、Azure 以及各类高性价比 VPS 服务商）均可满足要求。推荐使用 Ubuntu Server（24.04 LTS 或更高版本），个人用户选择最低规格的实例即可（例如 1 vCPU，512MB RAM）。

**配置示例：AWS EC2**

- 推荐操作系统：
  ```text
  Ubuntu Server 26.04 LTS
  ```
- 推荐实例类型（个人使用）：
  ```text
  t3.micro
  ```

在控制台创建实例时的关键设置：

- 新建或选择一个 SSH 密钥对（详见 [1.2](#12-创建-ssh-密钥对)）。
- 在关联的安全组中放行入站 TCP 端口 `22`、`443` 和 `8080`（详见 [1.3](#13-配置防火墙)）。
- 关联或分配一个公网 IPv4（或 IPv6）地址。

> [!IMPORTANT]
> 云服务商生成的私钥文件通常仅在创建时提供一次下载机会，请妥善保管。

#### 1.2 创建 SSH 密钥对

SSH 服务采用非对称加密方式进行身份验证。它由一对密钥组成：**私钥**安全存放在您的本地计算机上，**公钥**则配置在目标云服务器中。

某些云服务商在实例初始化时会自动为您生成密钥对（例如 AWS 会引导您下载私钥文件），而有些服务商则要求您手动上传已有的公钥。若您尚未创建密钥对，请参考 [附录 A](#a-ssh-密钥生成) 进行本地生成。

默认情况下，密钥对会保存在本地的 `~/.ssh` 目录下。以下是常用的标准密钥文件名，大多数 SSH 客户端均可自动识别并调用：

| 算法 | 私钥文件名 | 公钥文件名 |
|---|---|---|
| ED25519 | `id_ed25519` | `id_ed25519.pub` |
| RSA | `id_rsa` | `id_rsa.pub` |
| ECDSA | `id_ecdsa` | `id_ecdsa.pub` |

您只需将 `.pub` 后缀的公钥内容上传或粘贴至云服务商控制台。**在任何情况下都切勿向外界泄露您的私钥文件。**

#### 1.3 配置网络与防火墙安全策略

请在您的云服务商防火墙或网络安全组（Security Group）中配置入站规则，放行以下 TCP 端口：

| 端口 | 允许源 IP | 端口用途 |
|---|---|---|
| `22` | 仅限您的本地 IP | 安全 SSH 远程登录 |
| `443` | `0.0.0.0/0` (IPv6 为 `::/0`) | Xray Reality 服务端口 |
| `8080` | 建议仅限您的本地 IP | HTTP 订阅文件分发服务 (可选) |

配置要点：

- **无需启用 UDP**：Xray VLESS Reality 基于 TCP 传输协议，因此防火墙仅需放行 TCP 流量。
- **敏感信息防护**：由于 HTTP 订阅链接中包含节点的完整连接配置，建议将 `8080` 端口的源 IP 限制为您自己的 IP，或在客户端成功导入订阅后，在控制台中关闭该端口。
- **中转（Relay）模式配置**：在中转架构下，出口节点只需向中转节点的公网 IP 开放代理端口（默认 `443`），具体配置请参考 [relay](relay.md)。

> [!WARNING]
> **常见排查难点**
> 仅在云服务商的控制面板放行端口有时并不够。许多 Linux 镜像内置并默认启用了本地防火墙服务（如 `ufw` 或 `firewalld`），这可能导致外部请求在系统底层被拦截。如果您确认云控制台配置正确但客户端依旧无法连接，请参阅 [附录 B](#b-防火墙-ufw--firewalld)。

#### 1.4 通过 SSH 建立连接

在本地终端（Windows 环境下可使用 PowerShell 或 CMD，macOS/Linux 环境下使用终端）中执行以下连接指令：

```bash
ssh -i [KEY_FILE] [USERNAME]@[SERVER_PUBLIC_IP]
```

- `[KEY_FILE]`：您本地私钥文件的存储路径。
- `[USERNAME]`：服务器的系统默认登录用户名。Ubuntu 系统镜像通常为 `ubuntu`，Debian 镜像为 `debian`，CentOS 等其他系统可能是 `root` 或 `admin`。
- `[SERVER_PUBLIC_IP]`：目标云服务器的公网 IP 地址。

使用示例：

```bash
ssh -i key.pem ubuntu@203.0.113.10
```

首次建立连接时，SSH 客户端会要求您确认服务器的安全指纹。输入 `yes` 并按下回车以完成信任关系绑定。

### 2. 安装与运行 RayLink

#### 部署出口节点 (Exit Node)

**出口节点**承载完整的代理访问流量：客户端直接连接至该节点，再由该节点直接访问目标互联网资源。请在服务器的 SSH 终端中运行以下一键部署脚本：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh | sudo bash -s -- exit
```

部署完成后，安装程序会直接输出您的订阅及节点连接信息（该内容也会同步保存至 `/opt/cloud-xray-exit/server-info.txt` 供日后查阅）。随后可进入 [3](#3-导入客户端配置)。

若您希望自定义配置（如修改监听端口、切换 DNS Profile 或启用 IPv6 支持），可通过在脚本前置传入环境变量实现，详见 [configuration](configuration.md). 例如，将代理监听端口指定为 `8443`：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh | sudo env PORT=8443 bash -s -- exit
```

#### 部署中转节点 (Relay Node)

**中转节点**用于将客户端的连接中继转发至后端的出口节点（数据流向：`客户端 → 中转节点 → 出口节点 → 目标互联网`）。请先完成出口节点的部署，并获取其 **Universal Subscription URL**，然后在第二台服务器（中转服务器）上运行以下命令：

```bash
curl -fsSL https://raw.githubusercontent.com/vanillartwork/raylink/main/install.sh | sudo env UPSTREAM_SUBSCRIPTION_URL='http://203.0.113.10:8080/sub/TOKEN' bash -s -- relay
```

> [!NOTE]
> 请将示例中的 `203.0.113.10:8080/sub/TOKEN` 替换为您出口服务器上实际生成的 Universal 订阅链接。关于定义上游出口参数的其他高级方案，请参阅 [relay](relay.md)。

### 3. 导入客户端配置

部署完成后，RayLink 会生成以下三种链接，请根据您所使用的代理软件客户端进行选择（推荐客户端详见 [附录 C](#c-各系统主流客户端推荐)）：

| 订阅链接类型 | 链接形式 |
|---|---|
| **Universal Subscription URL** | `http://SERVER:8080/sub/TOKEN` |
| **Clash Subscription URL** | `http://SERVER:8080/sub/TOKEN/clash.yaml` |
| **Direct VLESS Link** | `vless://…` |

- **启用 HTTP 订阅时**：部署程序将同时提供 **Universal** 和 **Clash** 订阅链接；
- **禁用 HTTP 订阅时**：程序将仅输出 **VLESS** 链接。

对于 Clash/Mihomo 系列客户端，导入 Clash 订阅链接后，请在代理组中将 `GLOBAL` 设置为您所部署的节点，并开启系统代理（System Proxy）或 TUN 模式。

在服务器终端上查看 Direct VLESS 链接的方法（以出口节点为例，中转节点请查看 `/opt/cloud-xray-relay` 对应目录）：

```bash
sudo cat /opt/cloud-xray-exit/vless-uri.txt
```

> [!NOTE]
> Clash 配置文件及 VLESS URI 连接串将保留其专用的字段命名规范请勿修改配置的命名格式。

### 4. 下载配置文件

如果您不希望开启公网 HTTP 订阅，可在本地计算机的终端中使用 `scp` 命令，通过 SSH 安全协议将生成的配置文件下载至本地：

```bash
scp -i [KEY_FILE] [USERNAME]@[SERVER_PUBLIC_IP]:[REMOTE_PATH] [LOCAL_PATH]
```

示例：下载 Clash 配置文件至当前目录并重命名：

```bash
scp -i key.pem ubuntu@203.0.113.10:/opt/cloud-xray-exit/clash.yaml ./raylink-clash.yaml
```

示例：下载包含 VLESS 链接的文件至当前目录：

```bash
scp -i key.pem ubuntu@203.0.113.10:/opt/cloud-xray-exit/vless-uri.txt ./vless-uri.txt
```

### 5. 后续运维管理

您可以在服务器上随时通过以下 CLI 命令对节点进行更新或自检：

```bash
sudo raylink exit                 # 重新运行或更新（操作具备幂等性，可安全重复执行）
sudo raylink exit --health-check  # 手动触发一次节点状态自愈与检测
sudo raylink version             # 查看当前 RayLink 的版本号
```

服务器已默认启用 systemd 定时任务，在后台对服务状态 and Reality 目标域名进行定期健康监控与自愈重建。如需获取更深入的技术细节，请阅读以下参考文档：

- [exit](exit.md) —— 出口节点详细部署参数、架构说明及自恢复逻辑。
- [relay](relay.md) —— 中转模式工作流、上游参数管理及专属防火墙设置。
- [configuration](configuration.md) —— 每一个环境变量配置字段的参考指南。
- [troubleshooting](troubleshooting.md) —— 常见连接排查、IPv6 部署指南及无痕卸载方法。

---

## 附录

### A. SSH 密钥生成

若您尚未在本地生成过密钥对，请参照此步骤进行创建。目前推荐使用安全性与速度兼备的 ED25519 算法；RSA 4096 位算法则作为高兼容性的备选方案。

在本地终端中生成 ED25519 密钥对（将默认保存至本地的 `~/.ssh/id_ed25519`）：

```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
```

或者在指定路径下生成高强度的 RSA 4096 密钥对：

```bash
ssh-keygen -t rsa -b 4096 -C "your_email@example.com" -f ~/.ssh/id_rsa
```

生成过程中会提示您为私钥设置密码短语（Passphrase）：

- **直接按两次回车（不设密码）**：密钥读取更便捷，适合自动化免密连接。
- **设置独立密码**：增强密钥安全性。每次调用该密钥进行 SSH 登录时，系统均会要求您输入此密码。

密钥对生成后，您将获得以下两个核心文件：

- `id_ed25519`（或 `id_rsa`）：**私钥文件**。请严格保存在您的本地个人电脑中，在任何情况下均不要分享或上传。
- `id_ed25519.pub`（或 `id_rsa.pub`）：**公钥文件**。用于提供给云服务商，配置到服务器的受信密钥列表中。

您可以通过以下指令将公钥文件的内容一键复制到剪贴板，随后粘贴至云控制面板的 **SSH Keys** 新建窗口中（控制台里的 "Key Name" 仅做备注标识，不影响身份鉴权）：

```bash
# macOS
pbcopy < ~/.ssh/id_ed25519.pub

# Linux (X11 环境 / Wayland 环境)
xclip -sel clip < ~/.ssh/id_ed25519.pub   # 或：wl-copy < ~/.ssh/id_ed25519.pub
```

```powershell
# Windows (PowerShell)
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub" | Set-Clipboard
```

### B. 防火墙配置 (ufw / firewalld)

仅仅在云服务商的管理控制台开放端口有时并不充分，服务器的 Linux 系统中如果启用了系统级本地防火墙，同样需要手动写入端口策略。本部分建议仅在服务器**已启用**本地防火墙时进行配置，请勿为了运行 RayLink 而专门且盲目地开启防火墙。

**ufw 防火墙（主要用于 Debian / Ubuntu 系统）：**

首先运行以下命令检查防火墙的启用状态：

```bash
sudo ufw status
```

如果输出内容为 `Status: active`，说明防火墙已在运行，请执行以下指令放行代理及订阅服务的 TCP 端口：

```bash
sudo ufw allow 443/tcp
sudo ufw allow 8080/tcp
sudo ufw reload
```

**firewalld 防火墙（主要用于 RHEL / CentOS / Rocky Linux 等系统）：**

执行以下命令检查防火墙服务是否处于活动状态：

```bash
sudo systemctl is-active firewalld
```

如果输出结果为 `active`，请通过以下指令允许相关 TCP 端口通过并热重载防火墙：

```bash
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

运行以下命令验证策略是否已成功应用：

```bash
sudo firewall-cmd --list-ports
# 预期输出应包含: 443/tcp 8080/tcp
```

### C. 各系统主流客户端推荐

以下是按操作系统划分的主流客户端推荐列表，供您选择使用。每个客户端均标注了支持的连接类型（Universal、Clash 或 VLESS 链接）。

- **Windows 系统**
  - [v2rayN](https://github.com/2dust/v2rayN) — 支持 **Universal**、**VLESS**
  - [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev) — 支持 **Clash**
  - [FlClash](https://github.com/flclash/FlClash) — 支持 **Clash**、**Universal**
  - [Hiddify](https://github.com/hiddify/hiddify-next) — 支持 **Universal**、**VLESS**

- **安卓系统**
  - [v2rayNG](https://github.com/2dust/v2rayNG) — 支持 **Universal**、**VLESS**
  - [Hiddify](https://github.com/hiddify/hiddify-next) — 支持 **Universal**、**VLESS**
  - [FlClash](https://github.com/flclash/FlClash) — 支持 **Clash**、**Universal**
  - [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid) — 支持 **Universal**、**VLESS**

- **iOS / macOS & tvOS**
  - [Shadowrocket](https://apps.apple.com/app/shadowrocket/id932747118) — 支持 **Universal**、**VLESS**
  - [Anywhere](https://github.com/NodePassProject/Anywhere) — 支持 **Universal**、**VLESS**
  - [Egern](https://apps.apple.com/us/app/egern/id1616105820) — 支持 **Universal**、**VLESS**
