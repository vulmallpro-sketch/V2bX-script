#!/bin/bash
# V2bX 自动安装 + 自动配置脚本
# 用法示例：
#   wget -N https://raw.githubusercontent.com/YOUR_REPO/script/auto_install.sh && \
#   bash auto_install.sh \
#     --api-host 'https://example.com' \
#     --api-key 'your_api_key' \
#     --core sing \
#     --node-type anytls \
#     --node-id 6 \
#     --cert-mode http \
#     --cert-domain 'node.example.com'
#
# 参数说明：
#   --api-host      面板地址（必填，含 https://）
#   --api-key       面板 API Key（必填）
#   --core          核心类型：xray | sing | hysteria2（必填）
#   --node-type     节点协议：shadowsocks | vless | vmess | hysteria | hysteria2 | trojan | tuic | anytls（必填）
#   --node-id       节点 Node ID（必填，正整数）
#   --cert-mode     证书模式：none | http | dns | self（默认 none，anytls/hysteria/hysteria2/tuic 默认 http）
#   --cert-domain   证书域名（cert-mode 非 none 时必填）
#   --version       指定 V2bX 版本，如 v0.6.0（默认最新版）

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# ─────────────────────────────────────────────
# 解析参数
# ─────────────────────────────────────────────
ApiHost=""
ApiKey=""
core_arg=""
NodeType=""
NodeID=""
certmode=""
certdomain=""
v2bx_version=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --api-host)    ApiHost="$2";      shift 2 ;;
        --api-key)     ApiKey="$2";       shift 2 ;;
        --core)        core_arg="$2";     shift 2 ;;
        --node-type)   NodeType="$2";     shift 2 ;;
        --node-id)     NodeID="$2";       shift 2 ;;
        --cert-mode)   certmode="$2";     shift 2 ;;
        --cert-domain) certdomain="$2";   shift 2 ;;
        --version)     v2bx_version="$2"; shift 2 ;;
        *)
            echo -e "${red}未知参数: $1${plain}"
            exit 1
            ;;
    esac
done

# ─────────────────────────────────────────────
# 校验必填参数
# ─────────────────────────────────────────────
check_args() {
    local err=0
    [[ -z "$ApiHost" ]]  && echo -e "${red}错误：缺少 --api-host${plain}"  && err=1
    [[ -z "$ApiKey" ]]   && echo -e "${red}错误：缺少 --api-key${plain}"   && err=1
    [[ -z "$core_arg" ]] && echo -e "${red}错误：缺少 --core${plain}"      && err=1
    [[ -z "$NodeType" ]] && echo -e "${red}错误：缺少 --node-type${plain}" && err=1
    [[ -z "$NodeID" ]]   && echo -e "${red}错误：缺少 --node-id${plain}"   && err=1

    if [[ ! "$NodeID" =~ ^[0-9]+$ ]]; then
        echo -e "${red}错误：--node-id 必须为正整数${plain}"
        err=1
    fi

    case "$core_arg" in
        xray|sing|hysteria2) ;;
        *) echo -e "${red}错误：--core 必须为 xray | sing | hysteria2${plain}"; err=1 ;;
    esac

    case "$NodeType" in
        shadowsocks|vless|vmess|hysteria|hysteria2|trojan|tuic|anytls) ;;
        *) echo -e "${red}错误：--node-type 无效，可选：shadowsocks vless vmess hysteria hysteria2 trojan tuic anytls${plain}"; err=1 ;;
    esac

    [[ $err -eq 1 ]] && exit 1
}

check_args

# ─────────────────────────────────────────────
# 检查 root
# ─────────────────────────────────────────────
[[ $EUID -ne 0 ]] && echo -e "${red}错误：必须使用 root 用户运行此脚本！${plain}" && exit 1

# ─────────────────────────────────────────────
# 确定核心类型编号（兼容 add_node_config 逻辑）
# ─────────────────────────────────────────────
core_xray=false
core_sing=false
core_hysteria2=false
core=""
core_type=""

case "$core_arg" in
    xray)
        core="xray"; core_type="1"; core_xray=true ;;
    sing)
        core="sing"; core_type="2"; core_sing=true ;;
    hysteria2)
        core="hysteria2"; core_type="3"; core_hysteria2=true ;;
esac

# hysteria2 核心强制 NodeType=hysteria2
if [ "$core_hysteria2" = true ]; then
    NodeType="hysteria2"
fi

# ─────────────────────────────────────────────
# TLS / fastopen 逻辑
# ─────────────────────────────────────────────
fastopen=true
istls=""
isreality=""

case "$NodeType" in
    hysteria|hysteria2|tuic|anytls)
        fastopen=false
        istls="y"
        # 这些协议必须有 TLS，若未指定 certmode 则默认 http
        [[ -z "$certmode" ]] && certmode="http"
        ;;
    vless)
        isreality="n"  # 非交互模式默认不启用 reality（如需 reality 请手动改配置）
        ;;
esac

# 若 certmode 仍为空则设置默认值
[[ -z "$certmode" ]] && certmode="none"
[[ -z "$certdomain" ]] && certdomain="example.com"

# cert-mode 非 none 时校验域名
if [[ "$certmode" != "none" && "$certdomain" == "example.com" ]]; then
    echo -e "${red}错误：cert-mode 为 $certmode 时，请通过 --cert-domain 指定真实域名${plain}"
    exit 1
fi

# ─────────────────────────────────────────────
# 检查 IPv6 支持
# ─────────────────────────────────────────────
check_ipv6_support() {
    if ip -6 addr 2>/dev/null | grep -q "inet6"; then
        echo "1"
    else
        echo "0"
    fi
}

# ─────────────────────────────────────────────
# 安装 V2bX（调用官方 install.sh）
# ─────────────────────────────────────────────
install_v2bx() {
    echo -e "${green}>>> 开始安装 V2bX ...${plain}"
    if [[ -n "$v2bx_version" ]]; then
        bash <(curl -Ls https://raw.githubusercontent.com/wyx2685/V2bX-script/master/install.sh) "$v2bx_version"
    else
        bash <(curl -Ls https://raw.githubusercontent.com/wyx2685/V2bX-script/master/install.sh)
    fi
    if [[ $? -ne 0 ]]; then
        echo -e "${red}V2bX 安装失败，请检查网络后重试${plain}"
        exit 1
    fi
    echo -e "${green}>>> V2bX 安装完成${plain}"
}

# ─────────────────────────────────────────────
# 生成节点配置 JSON 片段
# ─────────────────────────────────────────────
build_node_config() {
    local ipv6_support listen_ip
    ipv6_support=$(check_ipv6_support)
    listen_ip="0.0.0.0"
    [ "$ipv6_support" -eq 1 ] && listen_ip="::"

    if [ "$core_type" == "1" ]; then
        node_config=$(cat <<EOF
{
            "Core": "$core",
            "ApiHost": "$ApiHost",
            "ApiKey": "$ApiKey",
            "NodeID": $NodeID,
            "NodeType": "$NodeType",
            "Timeout": 30,
            "ListenIP": "0.0.0.0",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "EnableProxyProtocol": false,
            "EnableUot": true,
            "EnableTFO": true,
            "DNSType": "UseIPv4",
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/V2bX/fullchain.cer",
                "KeyFile": "/etc/V2bX/cert.key",
                "Email": "v2bx@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        }
EOF
)
    elif [ "$core_type" == "2" ]; then
        node_config=$(cat <<EOF
{
            "Core": "$core",
            "ApiHost": "$ApiHost",
            "ApiKey": "$ApiKey",
            "NodeID": $NodeID,
            "NodeType": "$NodeType",
            "Timeout": 30,
            "ListenIP": "$listen_ip",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "TCPFastOpen": $fastopen,
            "SniffEnabled": true,
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/V2bX/fullchain.cer",
                "KeyFile": "/etc/V2bX/cert.key",
                "Email": "v2bx@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        }
EOF
)
    elif [ "$core_type" == "3" ]; then
        node_config=$(cat <<EOF
{
            "Core": "$core",
            "ApiHost": "$ApiHost",
            "ApiKey": "$ApiKey",
            "NodeID": $NodeID,
            "NodeType": "$NodeType",
            "Hysteria2ConfigPath": "/etc/V2bX/hy2config.yaml",
            "Timeout": 30,
            "ListenIP": "",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/V2bX/fullchain.cer",
                "KeyFile": "/etc/V2bX/cert.key",
                "Email": "v2bx@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        }
EOF
)
    fi
}

# ─────────────────────────────────────────────
# 生成所有配置文件
# ─────────────────────────────────────────────
generate_config() {
    echo -e "${green}>>> 生成 V2bX 配置文件 ...${plain}"

    mkdir -p /etc/V2bX
    [ -f /etc/V2bX/config.json ] && mv /etc/V2bX/config.json /etc/V2bX/config.json.bak

    # 构建节点 JSON
    build_node_config

    # 构建 Cores 配置
    local cores_config="["
    if [ "$core_xray" = true ]; then
        cores_config+='
    {
        "Type": "xray",
        "Log": {
            "Level": "error",
            "ErrorPath": "/etc/V2bX/error.log"
        },
        "OutboundConfigPath": "/etc/V2bX/custom_outbound.json",
        "RouteConfigPath": "/etc/V2bX/route.json"
    },'
    fi
    if [ "$core_sing" = true ]; then
        cores_config+='
    {
        "Type": "sing",
        "Log": {
            "Level": "error",
            "Timestamp": true
        },
        "NTP": {
            "Enable": false,
            "Server": "time.apple.com",
            "ServerPort": 0
        },
        "OriginalPath": "/etc/V2bX/sing_origin.json"
    },'
    fi
    if [ "$core_hysteria2" = true ]; then
        cores_config+='
    {
        "Type": "hysteria2",
        "Log": {
            "Level": "error"
        }
    },'
    fi
    cores_config+="]"
    cores_config=$(echo "$cores_config" | sed 's/},]$/}]/')

    # 写入 config.json
    cat > /etc/V2bX/config.json <<EOF
{
    "Log": {
        "Level": "error",
        "Output": ""
    },
    "Cores": $cores_config,
    "Nodes": [$node_config]
}
EOF

    # 写入 custom_outbound.json
    cat > /etc/V2bX/custom_outbound.json <<'EOF'
[
    {
        "tag": "IPv4_out",
        "protocol": "freedom",
        "settings": {
            "domainStrategy": "UseIPv4v6"
        }
    },
    {
        "tag": "IPv6_out",
        "protocol": "freedom",
        "settings": {
            "domainStrategy": "UseIPv6"
        }
    },
    {
        "protocol": "blackhole",
        "tag": "block"
    }
]
EOF

    # 写入 route.json
    cat > /etc/V2bX/route.json <<'EOF'
{
    "domainStrategy": "AsIs",
    "rules": [
        {
            "outboundTag": "block",
            "ip": ["geoip:private"]
        },
        {
            "outboundTag": "block",
            "domain": [
                "regexp:(api|ps|sv|offnavi|newvector|ulog.imap|newloc)(.map|).(baidu|n.shifen).com",
                "regexp:(.+.|^)(360|so).(cn|com)",
                "regexp:(Subject|HELO|SMTP)",
                "regexp:(torrent|.torrent|peer_id=|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=)",
                "regexp:(ed2k|.torrent|peer_id=|announce|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=|magnet:|xunlei|sandai|Thunder|XLLiveUD|bt_key)",
                "regexp:(.?)(xunlei|sandai|Thunder|XLLiveUD)(.)",
                "regexp:(..||)(dafahao|mingjinglive|botanwang|minghui|dongtaiwang|falunaz|epochtimes|ntdtv|falundafa|falungong|wujieliulan|zhengjian).(org|com|net)",
                "regexp:(.*.||)(rising|kingsoft|duba|xindubawukong|jinshanduba).(com|net|org)",
                "regexp:(.*.||)(netvigator|torproject).(com|cn|net|org)",
                "regexp:(.*.||)(miaozhen|cnzz|talkingdata|umeng).(cn|com)",
                "regexp:(.*.||)(pincong).(rocks)",
                "regexp:(.*.||)(taobao).(com)",
                "regexp:(flows|miaoko).(pages).(dev)"
            ]
        },
        {
            "outboundTag": "block",
            "ip": [
                "127.0.0.1/32",
                "10.0.0.0/8",
                "fc00::/7",
                "fe80::/10",
                "172.16.0.0/12"
            ]
        },
        {
            "outboundTag": "block",
            "protocol": ["bittorrent"]
        },
        {
            "outboundTag": "IPv4_out",
            "network": "udp,tcp"
        }
    ]
}
EOF

    # IPv6 DNS 策略
    local ipv6_support dnsstrategy
    ipv6_support=$(check_ipv6_support)
    dnsstrategy="ipv4_only"
    [ "$ipv6_support" -eq 1 ] && dnsstrategy="prefer_ipv4"

    # 写入 sing_origin.json（sing 核心使用）
    cat > /etc/V2bX/sing_origin.json <<EOF
{
  "dns": {
    "servers": [{"tag": "cf", "address": "1.1.1.1"}],
    "strategy": "$dnsstrategy"
  },
  "outbounds": [
    {
      "tag": "direct",
      "type": "direct",
      "domain_resolver": {"server": "cf", "strategy": "$dnsstrategy"}
    },
    {"type": "block", "tag": "block"}
  ],
  "route": {
    "rules": [
      {"ip_is_private": true, "outbound": "block"},
      {
        "domain_regex": [
            "(api|ps|sv|offnavi|newvector|ulog.imap|newloc)(.map|).(baidu|n.shifen).com",
            "(.+.|^)(360|so).(cn|com)",
            "(torrent|.torrent|peer_id=|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=)",
            "(ed2k|.torrent|peer_id=|announce|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=|magnet:|xunlei|sandai|Thunder|XLLiveUD|bt_key)",
            "(.?)(xunlei|sandai|Thunder|XLLiveUD)(.)",
            "(..||)(dafahao|mingjinglive|botanwang|minghui|dongtaiwang|falunaz|epochtimes|ntdtv|falundafa|falungong|wujieliulan|zhengjian).(org|com|net)",
            "(.*.||)(rising|kingsoft|duba|xindubawukong|jinshanduba).(com|net|org)",
            "(.*.||)(miaozhen|cnzz|talkingdata|umeng).(cn|com)",
            "(.*.||)(pincong).(rocks)",
            "(.*.||)(taobao).(com)",
            "(flows|miaoko).(pages).(dev)"
        ],
        "outbound": "block"
      },
      {"outbound": "direct", "network": ["udp", "tcp"]}
    ]
  },
  "experimental": {
    "cache_file": {"enabled": true}
  }
}
EOF

    # 写入 hy2config.yaml（hysteria2 核心使用）
    cat > /etc/V2bX/hy2config.yaml <<'EOF'
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 30s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false
ignoreClientBandwidth: false
disableUDP: false
udpIdleTimeout: 60s
resolver:
  type: system
acl:
  inline:
    - direct(geosite:google)
    - reject(geosite:cn)
    - reject(geoip:cn)
masquerade:
  type: 404
EOF

    echo -e "${green}>>> 配置文件生成完成${plain}"
}

# ─────────────────────────────────────────────
# 打印配置摘要
# ─────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${green}========== 安装配置摘要 ==========${plain}"
    echo -e "  面板地址  : ${yellow}$ApiHost${plain}"
    echo -e "  API Key   : ${yellow}${ApiKey:0:6}******${plain}"
    echo -e "  核心      : ${yellow}$core_arg${plain}"
    echo -e "  协议      : ${yellow}$NodeType${plain}"
    echo -e "  Node ID   : ${yellow}$NodeID${plain}"
    echo -e "  证书模式  : ${yellow}$certmode${plain}"
    echo -e "  证书域名  : ${yellow}$certdomain${plain}"
    echo -e "${green}===================================${plain}"
    echo ""
}

# ─────────────────────────────────────────────
# 主流程
# ─────────────────────────────────────────────
print_summary
install_v2bx
generate_config

echo -e "${green}>>> 重启 V2bX 服务 ...${plain}"
if command -v v2bx &>/dev/null; then
    v2bx restart
elif systemctl list-units --type=service 2>/dev/null | grep -q V2bX; then
    systemctl restart V2bX
else
    echo -e "${yellow}无法自动重启，请手动执行：v2bx restart${plain}"
fi

echo ""
echo -e "${green}全部完成！使用 v2bx log 查看运行日志。${plain}"
