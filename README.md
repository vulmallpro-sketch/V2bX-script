# V2bX
A V2board node server based on Xray-Core.

一个基于Xray的V2board节点服务端，支持V2ay,Trojan,Shadowsocks协议

Find the source code here: [InazumaV/V2bX](https://github.com/InazumaV/V2bX)

如对脚本不放心，可使用此沙箱先测一遍再使用：https://killercoda.com/playgrounds/scenario/ubuntu

# 详细使用教程

[教程](https://v2bx.v-50.me/)

# 一键安装（交互式）

```
wget -N https://raw.githubusercontent.com/wyx2685/V2bX-script/master/install.sh && bash install.sh
```

# 一键自动安装（无交互，参数化）

安装完成后自动写入配置文件并启动，无需手动操作，适合批量部署。

```bash
wget -N https://raw.githubusercontent.com/vulmallpro-sketch/V2bX-script/master/auto_install.sh && \
bash auto_install.sh \
  --api-host 'https://面板地址.com' \
  --api-key  '你的ApiKey'           \
  --core      sing                  \
  --node-type anytls                \
  --node-id   6                     \
  --cert-mode http                  \
  --cert-domain 'node.example.com'
```

### 参数说明

| 参数 | 必填 | 说明 |
|------|:----:|------|
| `--api-host` | ✅ | 面板地址，含 `https://` |
| `--api-key` | ✅ | 面板对接 API Key |
| `--core` | ✅ | 核心类型：`xray` / `sing` / `hysteria2` |
| `--node-type` | ✅ | 节点协议：`shadowsocks` `vless` `vmess` `trojan` `hysteria` `hysteria2` `tuic` `anytls` |
| `--node-id` | ✅ | 节点 Node ID（正整数） |
| `--cert-mode` | 否 | 证书模式：`none`（默认）/ `http` / `dns` / `self`；`anytls` `tuic` `hysteria` `hysteria2` 自动设为 `http` |
| `--cert-domain` | 有TLS时 | 证书域名，如 `node.example.com` |
| `--version` | 否 | 指定 V2bX 版本，如 `v0.6.0`，默认安装最新版 |

### 执行流程

1. 检测系统环境并安装基础依赖
2. 从 GitHub 下载并安装 V2bX 二进制（自动跳过交互式配置向导）
3. 根据传入参数自动生成 `/etc/V2bX/config.json` 及相关配置文件
4. 启动 V2bX 服务
