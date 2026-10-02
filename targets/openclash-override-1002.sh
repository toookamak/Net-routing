#!/bin/sh
# ============================================================================
#  openclash-override-1002.sh —— net-routing 路由器侧覆写脚本
#  ★★ 版本 1002 v1.3.0 ★★    规模 51 规则 / 43 规则集 / 22 策略组
# ============================================================================
#  部署  LuCI → 服务 → OpenClash → 覆写模块 → 编辑本文件 → 粘贴替换 → 保存 → 重启
#  传输  scp .\targets\openclash-override-1002.sh \
#            root@192.168.31.1:/etc/openclash/custom/openclash_custom_overwrite.sh
#  确认  grep 'net-routing artifact' /tmp/openclash.log | tail -5
#  ──────────────────────────────────────────────────────────────────────────
#  为什么不用覆写模块的 [YAML] 块（试过，有 bug）：
#    它的解析器处理 proxy-groups!（数组套对象整体替换）时，会把元素内
#    「值里含竖线 |」的键整行丢掉。实测活下来的是 type / include-all-proxies /
#    empty-fallback / url / interval / tolerance / lazy（值里都没 |），
#    死掉的是 filter / exclude-filter（值里全是 |）。| 是 YAML 块标量指示符，
#    那个解析器是逐行处理的。症状：每个组候选池都是全部节点，
#    「选香港」选出来的是新加坡节点。绕法（| 换 \n）走不通，同一解析器
#    不处理引号内转义。本脚本走 Psych 直接读写 YAML，不经过它。
#  ──────────────────────────────────────────────────────────────────────────
#  绝不做：碰 proxies / 任何端口 / authentication / dns.listen（写错=全局域网
#  DNS 瘫痪）/ tun 段 / IPv6（那是系统层问题，见配套文档第九节）
#
#  安全：备份 → 交叉引用自检 → 写盘 → clash_meta -t 离线校验 → 失败自动回滚。
#  OpenClash 启动 mihomo 时拿到的永远是能通过校验的配置；写坏的后果是
#  「本次覆写被跳过，网络照旧」，不是断网。
#
#  退路：LuCI 覆写设置页顶部 /cgi-bin/luci/admin/services/openclash/restore
#  或换回原厂模板后重启（OpenClash 仓库 luci-app-openclash/root/etc/openclash/
#  custom/openclash_custom_overwrite.sh）
#
#  ⚠️ Ruby 出错在屏幕上完全静默（OpenClash 的 ruby.sh 带 2>/dev/null），只写日志。
#     改完分流没变化时第一件事：grep '\[net-routing\]' /tmp/openclash.log | tail -20
# ============================================================================

. /usr/share/openclash/ruby.sh
. /usr/share/openclash/log.sh
. /lib/functions.sh

LOG_TIP "Start Running Custom Overwrite Scripts..."
LOGTIME=$(echo $(date "+%Y-%m-%d %H:%M:%S"))
LOG_FILE="/tmp/openclash.log"
CONFIG_FILE="$1"

NR_CORE="/etc/openclash/core/clash_meta"
NR_DATA="/tmp/nr-data-$$.yaml"
NR_BACKUP="${CONFIG_FILE}.nr-bak"
NR_VLOG="/tmp/nr-validate-$$.log"
# 规则集下载走 CDN。43 个规则集大半来自 raw.githubusercontent.com，大陆直连经常
# 超时，而 mihomo 对 provider 下载失败是静默空载（面板正常但分流不生效）
NR_CDN="https://cdn.jsdelivr.net/"

nr_log()
{
    echo "${LOGTIME} [net-routing] $1" >> "$LOG_FILE"
    echo "[net-routing] $1"
}

# ---------- 0. 前置检查 ----------
if [ -z "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ]; then
    nr_log "SKIP: config not found: ${CONFIG_FILE}"
    exit 0
fi

# ===========================================================================
#  数据段 —— 以下 YAML 是本文件唯一需要维护的内容，由 rules/*.yaml 渲染
#  标记之外是逻辑，可直接改
# ===========================================================================
cat > "$NR_DATA" <<'NET_ROUTING_DATA_EOF'
# ================================================================
#  数据段 —— 由 rules/*.yaml 渲染，勿手改
# ================================================================
net-routing:
  basic:
    mode: rule
    unified-delay: true      # 统一延迟计算，去掉握手等额外耗时
    tcp-concurrent: true     # 并发请求多个 IP 取最低延迟那条
    geodata-mode: true       # 启用 GeoIP/GeoSite 数据库
    # 路由器场景与客户端相反：进程规则只对路由器自身生效（官方源码原话
    # "Only Works on Routerself"），LAN 客户端的进程路由器上看不到。
    # 保持 off 省掉每连接的进程扫描开销。
    find-process-mode: "off"
  # ============================================================================
  # proxy-groups —— 整体替换
  #
  # ⚠️ 与 flclash 版的三个结构性差异：
  #   1. 全部用 include-all-proxies + filter 声明，**不写死节点名**
  #      → 本段与订阅无关，也是「PC 侧渲染、路由器侧极简合并」架构的前提
  #   2. 地区组**一律不设 exclude-filter**（实测：排低倍率会让美英清空、
  #      排流媒体会让台湾清空，见 docs/openclash.md 第五节 11）
  #   3. 不设 🔗 Tailscale 组 —— tailscaled 是系统服务，规则直接指向 DIRECT
  # sniffer —— 域名嗅探
  # 官方说明 Sniffer Will Prevent Domain Name Proxy and DNS Hijack Failure。
  # fake-ip 下大部分连接本来就有域名信息，但 homelab 机器之间不少是直连 IP
  # 的（NAS 挂载、数据库直连、CI 拉镜像），走不到 fake-ip 映射，嗅探能捞回域名。
  # override-destination 保持 false —— 改写会破坏连接复用。
  sniffer:
    enable: true
    force-dns-mapping: true
    parse-pure-ip: true
    override-destination: false
    sniff:
      HTTP:
        ports: [80, "8080-8880"]
        override-destination: false
      TLS:
        ports: [443]
    # APNs 推送需保持原目的 IP，否则收不到推送
    skip-domain: ["+.push.apple.com"]
    # Telegram 机房段，嗅探反而会拿到错误的目的地
    skip-dst-address:
      - "91.105.192.0/23"
      - "91.108.4.0/22"
      - "91.108.8.0/21"
      - "91.108.16.0/21"
      - "91.108.56.0/22"
      - "95.161.64.0/20"
      - "149.154.160.0/20"
      - "185.76.151.0/24"

  # ============================================================================

  # dns 段 —— 浅合并，保留 OpenClash 原有的 listen / enhanced-mode / fake-ip-range
  # 下面几项在订阅原配置里是坏的，这里修掉：
  #   fallback: [1.1.1.1, 8.8.8.8] 大陆直连必然被污染/超时，
  #   而 fallback-filter 配了 geosite:gfw，gfw 域名查询全撞在它上面
  #   respect-rules: false 导致 DNS 连接不走代理，国际 DoH 穿不过隧道
  dns_merge:
    ipv6: false
    respect-rules: true
    # 引导层：只用来解析下面两个 DoH 的域名，必须明文 UDP 且直连可达
    default-nameserver:
      - "223.5.5.5"
      - "119.29.29.29"
    # 默认国内 DoH（实测 doh.pub 189ms / alidns 175ms）
    nameserver:
      - "https://dns.alidns.com/dns-query"
      - "https://doh.pub/dns-query"
    # 节点自身域名的解析源，单独隔离。机场节点域名被污染就永远连不上，
    # 路由器是全家入口，这里比客户端更要命
    proxy-server-nameserver:
      - "https://dns.alidns.com/dns-query"
      - "https://doh.pub/dns-query"
    # 境外域名走国际 DoH。respect-rules=true 时这条 DoH 连接会穿隧道
    nameserver-policy:
      "geosite:gfw,geolocation-!cn":
        - "https://dns.google/dns-query"
        - "https://cloudflare-dns.com/dns-query"
    # 以下会与 OpenClash 原有的 fake-ip-filter 合并（不是替换），
    # 原有那条 rule-set:oc-cn-domain 会保留
    fake-ip-filter:
      - "+.lan"
      - "+.local"
      - "+.localdomain"
      - "+.home"
      - "+.home.arpa"
      - "+.internal"
      - "+.intranet"
      - "+.private"
      - "+.arpa"
      - "+.ts.net"
      - "connectivitycheck.gstatic.com"
      - "*.msftconnecttest.com"
      - "*.msftncsi.com"
      - "*.gvt1.com"
      - "*.gvt2.com"
      - "time.*.com"
      - "ntp.*.com"
      - "*.mi.com"
      - "*.xiaomi.com"
      - "*.hp.com"
      - "*.brother.com"
      - "*.epson.net"
      - "*.esphome.io"
      - "*.homeassistant.io"
      - "+.oray.com"
      - "+.sunlogin.net"
      - "+.icbc.com.cn"
      - "+.ccb.com"
      - "+.abchina.com"
      - "+.alipay.com"
      - "+.unionpay.com"
  # basic —— 顶层键，直接覆盖

  proxy-groups:
  
    # ---- 核心路由 ----
  
    - name: "🧭 代理模式"
      type: select
      # 顶层唯一入口。日常只需要碰这一个组。
      proxies:
        - "⚡ 延迟优选"
        - "🇭🇰 香港"
        - "🇸🇬 新加坡"
        - "🇯🇵 日本"
        - "🇺🇸 美国"
        - "🇬🇧 英国"
        - "🇹🇼 台湾"
        - "🚧 故障转移"
        - "🌍 全部节点"
        - "DIRECT"
        - "REJECT"
  
    - name: "⚡ 延迟优选"
      type: url-test
      include-all-proxies: true
      # 通知节点绝不能参与测速——它们是流量/到期提示，不是线路
      exclude-filter: "自动|故障|流量|官网|套餐|机场|订阅|年付|月付|失联|频道|Traffic|Expire|剩余|激励|分享|到期|续费|充值"
      empty-fallback: DIRECT
      url: "http://www.gstatic.com/generate_204"
      interval: 1800
      # 路由器比客户端更需要容差：服务器上的长连接（docker pull / rsync /
      # 数据库同步）经不起一次中途切换导致的 TCP 重连。
      tolerance: 50
      lazy: true
  
    - name: "🚧 故障转移"
      type: fallback
      include-all-proxies: true
      exclude-filter: "自动|故障|流量|官网|套餐|机场|订阅|年付|月付|失联|频道|Traffic|Expire|剩余|激励|分享|到期|续费|充值"
      empty-fallback: DIRECT
      url: "http://www.gstatic.com/generate_204"
      interval: 1800
      lazy: true
  
    - name: "🌍 全部节点"
      type: select
      include-all-proxies: true
      exclude-filter: "自动|故障|流量|官网|套餐|机场|订阅|年付|月付|失联|频道|Traffic|Expire|剩余|激励|分享|到期|续费|充值"
      empty-fallback: DIRECT
      # 注意：本组不设 filter，因此也会包含「未命中任何地区」的节点。
      # flclash 版有个「🌐 其他地区」组用来兜这些节点，路由器上做不出来——
      # 正则无法表达「不匹配上述任何地区」（Go RE2 不支持否定前瞻）。
      # 这些节点在本组里仍然可选。
  
    # ---- 地区组：选地区 = 该地区内延迟最低的那个 ----
    # 正则来自 rules/regions.yaml，一行都不写死
  
    - name: "🇭🇰 香港"
      type: url-test
      include-all-proxies: true
      filter: "香港|HK|Hong Kong|🇭🇰"
      empty-fallback: DIRECT
      url: "http://www.gstatic.com/generate_204"
      interval: 1800
      tolerance: 50
      lazy: true
  
    - name: "🇸🇬 新加坡"
      type: url-test
      include-all-proxies: true
      filter: "新加坡|狮城|SG|Singapore|🇸🇬"
      empty-fallback: DIRECT
      url: "http://www.gstatic.com/generate_204"
      interval: 1800
      tolerance: 50
      lazy: true
  
    - name: "🇯🇵 日本"
      type: url-test
      include-all-proxies: true
      filter: "日本|JP|Japan|🇯🇵"
      empty-fallback: DIRECT
      url: "http://www.gstatic.com/generate_204"
      interval: 1800
      tolerance: 50
      lazy: true
  
    - name: "🇺🇸 美国"
      type: url-test
      include-all-proxies: true
      filter: "美国|US|USA|United States|America|🇺🇸"
      empty-fallback: DIRECT
      url: "http://www.gstatic.com/generate_204"
      interval: 1800
      tolerance: 50
      lazy: true
  
    - name: "🇬🇧 英国"
      type: url-test
      include-all-proxies: true
      filter: "英国|UK|United Kingdom|伦敦|🇬🇧"
      empty-fallback: DIRECT
      url: "http://www.gstatic.com/generate_204"
      interval: 1800
      tolerance: 50
      lazy: true
  
    - name: "🇹🇼 台湾"
      type: url-test
      include-all-proxies: true
      # 不用单字「台」（会误伤）；靠「台湾」双字命中，国旗只是附加项
      filter: "台湾|台灣|Taiwan|🇹🇼"
      empty-fallback: DIRECT
      url: "http://www.gstatic.com/generate_204"
      interval: 1800
      tolerance: 50
      lazy: true
  
    # ---- 线路特性组 ----
    # 正则来自 rules/filters.yaml
  
    - name: "🏠 家宽/原生线路"
      type: select
      include-all-proxies: true
      filter: "家宽|原生|residential|home"
      empty-fallback: DIRECT
      # 当前订阅无此类节点，本组会走 empty-fallback 落到 DIRECT。
      # 组本身无害（实测内核容忍空组）。不想看它就在 groups.yaml 里注释掉。
  
    - name: "💰 低倍率节点"
      type: select
      include-all-proxies: true
      # lowrate + lowrate_numeric 合并。数字写法（0.5x / 0.1x）是主流机场的
      # 实际记法，rules/filters.yaml 里原先只覆盖中文写法，实测命中 0 个。
      filter: "低倍率|lowrate|低-rate|倍率|0\\.\\d+x|[0-9]+倍"
      empty-fallback: DIRECT
  
    - name: "📺 流媒体节点"
      type: select
      include-all-proxies: true
      filter: "流媒体|解锁|Netflix|Disney|IPLC|IEPL"
      empty-fallback: DIRECT
  
    - name: "📢 订阅信息"
      type: select
      include-all-proxies: true
      filter: "自动|故障|流量|官网|套餐|机场|订阅|年付|月付|失联|频道|Traffic|Expire|剩余|激励|分享|到期|续费|充值"
      empty-fallback: DIRECT
      # 机场的流量/到期提示节点，正常不该选
  
    # ---- 服务组 ----
    # 选项完全一致：代理模式 + 延迟优选 + 故障转移 + 全部节点 + DIRECT + REJECT
    # 每一项都含 DIRECT —— 让用户能不改规则就把某一类流量改成直连
    # 路由器版尤其重要：homelab 机器没人去面板上点，服务分组必须自己兜住
  
    - name: "📁 办公通讯"
      type: select
      proxies: ["🧭 代理模式", "⚡ 延迟优选", "🚧 故障转移", "🌍 全部节点", "DIRECT", "REJECT"]
  
    - name: "🤖 AI服务"
      type: select
      proxies: ["🧭 代理模式", "⚡ 延迟优选", "🚧 故障转移", "🌍 全部节点", "DIRECT", "REJECT"]
  
    - name: "🔍 谷歌服务"
      type: select
      proxies: ["🧭 代理模式", "⚡ 延迟优选", "🚧 故障转移", "🌍 全部节点", "DIRECT", "REJECT"]
  
    - name: "游戏平台"
      type: select
      proxies: ["🧭 代理模式", "⚡ 延迟优选", "🚧 故障转移", "🌍 全部节点", "DIRECT", "REJECT"]
  
    - name: "📺 大流量通道"
      type: select
      # 不含 REJECT —— 大流量没有「拒绝」这个选项
      proxies: ["🧭 代理模式", "⚡ 延迟优选", "🚧 故障转移", "🌍 全部节点", "DIRECT"]
  
    - name: "⛔ 广告拦截"
      type: select
      # 固定两项，不可选其他出口
      proxies: ["REJECT", "DIRECT"]
      # 路由器版的广告拦截是 homelab 机器唯一的防线
      #（NAS / PVE / CI 上装不了 FlClash）
  
    # ---- 默认路由 ----
  
    - name: "🛡️ 国内直连"
      type: select
      # 默认 DIRECT。接入第 50 条 GEOIP,CN
      proxies:
        - "DIRECT"
        - "⚡ 延迟优选"
        - "🇭🇰 香港"
        - "🇸🇬 新加坡"
        - "🇯🇵 日本"
        - "🇺🇸 美国"
        - "🇬🇧 英国"
        - "🇹🇼 台湾"
        - "🚧 故障转移"
        - "🌍 全部节点"
  
    - name: "🌍 兜底代理"
      type: select
      # 接入最后一条 MATCH
      proxies:
        - "🧭 代理模式"
        - "⚡ 延迟优选"
        - "🇭🇰 香港"
        - "🇸🇬 新加坡"
        - "🇯🇵 日本"
        - "🇺🇸 美国"
        - "🇬🇧 英国"
        - "🇹🇼 台湾"
        - "🚧 故障转移"
        - "🌍 全部节点"
        - "DIRECT"
  
  
  # ============================================================================
  # rule-providers —— 合并进已有的（保留 OpenClash 注入的 oc-cn-domain）
  #
  # 相比 flclash 版少了 3 个：
  #   applications        —— 全是 PROCESS-NAME，路由器上对 LAN 客户端永不命中
  #                          （官方源码："Only Works on Routerself"）
  #   Telegram_no_ip      —— 与 Telegram_ip 同 url 同 path，功能完全重复。
  #                          FlClash 有「Provider Path Mapping」把 path 重映射成
  #                          哈希路径把这个 bug 掩盖了，**OpenClash 尊重声明的
  #                          path**，两个 provider 会竞争写同一个文件。
  #   GoogleFCM_no_ip     —— 同上
  # 这两条是 docs/openclash.md 第五节实测确认的，路由器上真的会触发。
  # ============================================================================
  

  rule-providers:
  
    # ---- 免拦截 / 直连 ----
    UnBan:
      type: http
      behavior: classical
      format: text
      interval: 172800
      url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/UnBan.list"
      path: "./ruleset/net-routing/UnBan.list"
    DirectNoResolve:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Direct/Direct.yaml"
      path: "./ruleset/net-routing/Direct.yaml"
    Lan_ip:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/DIRECT/ip/Lan_ip.yaml"
      path: "./ruleset/net-routing/Lan_ip.yaml"
    Domestic_no_ip:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/DIRECT/no_ip/Domestic_no_ip.yaml"
      path: "./ruleset/net-routing/Domestic_no_ip.yaml"
    MicrosoftCNCDN_no_ip:
      type: http
      behavior: classical
      format: text
      interval: 172800
      url: "https://ruleset.skk.moe/Clash/non_ip/microsoft_cdn.txt"
      path: "./ruleset/net-routing/MicrosoftCNCDN.txt"
    AppleCNCDN_no_ip:
      type: http
      behavior: domain
      format: text
      interval: 172800
      url: "https://ruleset.skk.moe/Clash/domainset/apple_cdn.txt"
      path: "./ruleset/net-routing/AppleCNCDN.txt"
  
    # ---- 广告拦截 ----
    Reject_no_ip:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/REJECT/no_ip/Reject_no_ip.yaml"
      path: "./ruleset/net-routing/Reject_no_ip.yaml"
    Reject_domainset:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/REJECT/no_ip/Reject_domainset.yaml"
      path: "./ruleset/net-routing/Reject_domainset.yaml"
    Reject_no_ip_drop:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/REJECT/no_ip/Reject_no_ip_drop.yaml"
      path: "./ruleset/net-routing/Reject_no_ip_drop.yaml"
    Reject_no_ip_no_drop:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/REJECT/no_ip/Reject_no_ip_no_drop.yaml"
      path: "./ruleset/net-routing/Reject_no_ip_no_drop.yaml"
    Reject_ip:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/REJECT/ip/Reject_ip.yaml"
      path: "./ruleset/net-routing/Reject_ip.yaml"
  
    # ---- 办公通讯 / 开发工具链 ----
    Github:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/refs/heads/master/rule/Clash/GitHub/GitHub.yaml"
      path: "./ruleset/net-routing/Github.yaml"
    Twitter:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Twitter/Twitter.yaml"
      path: "./ruleset/net-routing/Twitter.yaml"
    Notion_ip:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/refs/heads/master/rule/Clash/Notion/Notion.yaml"
      path: "./ruleset/net-routing/Notion_ip.yaml"
    Figma_ip:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/refs/heads/master/rule/Clash/Figma/Figma.yaml"
      path: "./ruleset/net-routing/Figma_ip.yaml"
    OneDrive:
      type: http
      behavior: classical
      format: text
      interval: 172800
      url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/OneDrive.list"
      path: "./ruleset/net-routing/OneDrive.list"
    Dropbox:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/refs/heads/master/rule/Clash/Dropbox/Dropbox.yaml"
      path: "./ruleset/net-routing/Dropbox.yaml"
    Telegram_ip:
      type: http
      behavior: classical
      format: text
      interval: 172800
      url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/Telegram.list"
      path: "./ruleset/net-routing/Telegram.list"
    Microsoft_no_ip:
      type: http
      behavior: classical
      format: text
      interval: 172800
      url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/Microsoft.list"
      path: "./ruleset/net-routing/Microsoft.list"
    Docker:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Docker/Docker.yaml"
      path: "./ruleset/net-routing/Docker.yaml"
    MicrosoftCDN_no_ip:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/DIRECT/no_ip/MicrosoftCDN_no_ip.yaml"
      path: "./ruleset/net-routing/MicrosoftCDN_no_ip.yaml"
  
    # ---- AI 服务 ----
    OpenAI:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/OpenAI/OpenAI.yaml"
      path: "./ruleset/net-routing/OpenAI.yaml"
    Gemini:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/refs/heads/master/rule/Clash/Gemini/Gemini.yaml"
      path: "./ruleset/net-routing/Gemini.yaml"
    AI_no_ip:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/PROXY/no_ip/AI_no_ip.yaml"
      path: "./ruleset/net-routing/AI_no_ip.yaml"
  
    # ---- 谷歌服务 ----
    Google:
      type: http
      behavior: classical
      format: text
      interval: 172800
      url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/Google.list"
      path: "./ruleset/net-routing/Google.list"
    YouTube:
      type: http
      behavior: classical
      format: text
      interval: 172800
      url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/YouTube.list"
      path: "./ruleset/net-routing/YouTube.list"
    GoogleFCM_ip:
      type: http
      behavior: classical
      format: text
      interval: 172800
      url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/GoogleFCM.list"
      path: "./ruleset/net-routing/GoogleFCM.list"
  
    # ---- 大流量 / CDN / 下载 / 流媒体 ----
    Stream_ip:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/PROXY/ip/Stream_ip.yaml"
      path: "./ruleset/net-routing/Stream_ip.yaml"
    CDN_domainset:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/PROXY/no_ip/CDN_domainset.yaml"
      path: "./ruleset/net-routing/CDN_domainset.yaml"
    CDN_no_ip:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/PROXY/no_ip/CDN_no_ip.yaml"
      path: "./ruleset/net-routing/CDN_no_ip.yaml"
    Download_domainset:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/PROXY/no_ip/Download_domainset.yaml"
      path: "./ruleset/net-routing/Download_domainset.yaml"
    Download_no_ip:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/PROXY/no_ip/Download_no_ip.yaml"
      path: "./ruleset/net-routing/Download_no_ip.yaml"
    GameDownload:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/refs/heads/master/rule/Clash/Game/GameDownload/GameDownload.yaml"
      path: "./ruleset/net-routing/GameDownload.yaml"
  
    # ---- 游戏平台 ----
    SteamCN_ip:
      type: http
      behavior: classical
      format: text
      interval: 172800
      url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/SteamCN.list"
      path: "./ruleset/net-routing/SteamCN.list"
    Steam:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Steam/Steam.yaml"
      path: "./ruleset/net-routing/Steam.yaml"
    UnrealRules:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/refs/heads/master/rule/Clash/Epic/Epic.yaml"
      path: "./ruleset/net-routing/UnrealRules.yaml"
    Origin:
      type: http
      behavior: classical
      format: yaml
      interval: 172800
      url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/EA/EA.yaml"
      path: "./ruleset/net-routing/EA.yaml"
    Sony:
      type: http
      behavior: classical
      format: text
      interval: 172800
      url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/Sony.list"
      path: "./ruleset/net-routing/Sony.list"
    Nintendo:
      type: http
      behavior: classical
      format: text
      interval: 172800
      url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/Nintendo.list"
      path: "./ruleset/net-routing/Nintendo.list"
  
    # ---- 自托管规则集（rulesets/ 目录，需先推到 GitHub 否则 404 静默空载）----
    CustomRejectRules:
      type: http
      behavior: classical
      format: yaml
      interval: 86400
      url: "https://raw.githubusercontent.com/toookamak/Net-routing/refs/heads/main/rulesets/OwnREJECTRules.yaml"
      path: "./ruleset/net-routing/CustomRejectRules.yaml"
    CustomDirectRules:
      type: http
      behavior: classical
      format: yaml
      interval: 86400
      url: "https://raw.githubusercontent.com/toookamak/Net-routing/refs/heads/main/rulesets/OwnDIRECTRules.yaml"
      path: "./ruleset/net-routing/CustomDirectRules.yaml"
    CustomProxyRules:
      type: http
      behavior: classical
      format: yaml
      interval: 86400
      url: "https://raw.githubusercontent.com/toookamak/Net-routing/refs/heads/main/rulesets/OwnPROXYRules.yaml"
      path: "./ruleset/net-routing/CustomProxyRules.yaml"
  
    # ---- 内嵌规则：npm 源域名稳定，但自建仓库随时可能转私有 ----
    Npm:
      type: inline
      behavior: classical
      payload:
        - "DOMAIN,registry.npmjs.org"
        - "DOMAIN,auth.docker.io"
        - "DOMAIN,registry.npmmirror.com"
        - "DOMAIN,registry.npm.taobao.org"
        - "DOMAIN-SUFFIX,npmmirror.com"
        - "DOMAIN-SUFFIX,cnpmjs.org"
        - "DOMAIN-SUFFIX,npm.taobao.org"
        - "DOMAIN,registry.yarnpkg.com"
        - "DOMAIN-SUFFIX,yarnpkg.com"
        - "DOMAIN,registry.bower.io"
        - "DOMAIN-SUFFIX,nodejs.org"
        - "DOMAIN-SUFFIX,nodejs.com"
        - "DOMAIN-SUFFIX,nodejs.dev"
        - "DOMAIN-SUFFIX,nodejs.cn"
        - "DOMAIN-KEYWORD,nodejs"
  
  
  # ============================================================================
  # rules —— 整体替换（51 条）
  #
  # mihomo 从上到下匹配，命中即停。三个不可动的顺序约束：
  #   ① 第 1-2 条 UnBan 必须在所有 REJECT 之前，否则白名单形同虚设
  #   ② 第 7-9 条 tailnet 必须在 GEOSITE,cn / GEOIP,CN 之前，
  #      否则 homelab 机器间互访会被「国内直连」抢走
  #   ③ 最后两条必须是 GEOIP,CN 和 MATCH
  #
  # ⚠️ no-resolve 的位置：必须在目标组之后。
  #      IP-CIDR,100.64.0.0/10,DIRECT,no-resolve  ✅
  #      IP-CIDR,100.64.0.0/10,no-resolve,DIRECT  ❌ 报 proxy [no-resolve] not found
  # ============================================================================
  

  rules:
  
    # ── 段 1 · 免拦截白名单（1-2）→ DIRECT ──────────────────────────
    # 必须最先。误伤广告规则的代价（装不上、登不进）远大于漏放几个广告。
    - "RULE-SET,UnBan,DIRECT"
    - "RULE-SET,DirectNoResolve,DIRECT"
  
    # ── 段 2 · 广告拦截（3-8）→ ⛔ 广告拦截 ────────────────────────
    # homelab 机器唯一的广告防线（NAS / PVE / CI 上装不了 FlClash）
    - "RULE-SET,Reject_no_ip,⛔ 广告拦截"
    - "RULE-SET,Reject_domainset,⛔ 广告拦截"
    - "RULE-SET,Reject_no_ip_drop,⛔ 广告拦截"
    - "RULE-SET,Reject_no_ip_no_drop,⛔ 广告拦截"
    - "RULE-SET,Reject_ip,⛔ 广告拦截"
    - "RULE-SET,CustomRejectRules,⛔ 广告拦截"
  
    # ── 段 3 · tailnet 内网（9-11）→ DIRECT ────────────────────────
    # ⚠️ 路由器版与 flclash 版的唯一结构差异：目标直接是 DIRECT，不建策略组。
    #    tailscaled 是系统服务，tailnet 路由由它自己处理（ip rule → table 52），
    #    mihomo 再插一层只会添乱。
    #    刚需理由：tailnet 里有 fnos(NAS) / nas6418 / pve，homelab 机器之间
    #    要互访，走代理就断了。
    - "IP-CIDR,100.64.0.0/10,DIRECT,no-resolve"
    - "IP-CIDR,100.100.100.100/32,DIRECT,no-resolve"
    - "DOMAIN-SUFFIX,ts.net,DIRECT"
  
    # ── 段 4 · 私有网络与国内直连（12-19）→ DIRECT ─────────────────
    - "GEOSITE,private,DIRECT"
    - "GEOIP,private,DIRECT,no-resolve"
    - "RULE-SET,MicrosoftCNCDN_no_ip,DIRECT"
    - "RULE-SET,AppleCNCDN_no_ip,DIRECT"
    - "GEOSITE,cn,DIRECT"
    - "RULE-SET,Lan_ip,DIRECT"
    - "RULE-SET,SteamCN_ip,DIRECT"
    - "RULE-SET,Domestic_no_ip,DIRECT"
  
    # ── 段 5 · 自定义直连（20）→ DIRECT，锁死不建组 ─────────────────
    - "RULE-SET,CustomDirectRules,DIRECT"
  
    # ⚠️ flclash 版这里的「段 5 · 应用级分流（PROCESS-NAME）」已删除。
    #    那条规则依赖 PROCESS-NAME，路由器上对 LAN 客户端永不命中
    #    （官方源码原话："Only Works on Routerself"）。
    #    路由器版不做按设备分流 —— homelab 机器的流量特征由下面的
    #    服务组（办公通讯/大流量通道）覆盖，不靠客户端那种进程规则。
  
    # ── 段 6 · 办公通讯与开发工具链（21-31）→ 📁 办公通讯 ───────────
    # homelab 权重最高的一段：git clone / docker pull / npm / CI 都在这
    - "RULE-SET,Github,📁 办公通讯"
    - "RULE-SET,Figma_ip,📁 办公通讯"
    - "RULE-SET,Notion_ip,📁 办公通讯"
    - "RULE-SET,Twitter,📁 办公通讯"
    - "RULE-SET,OneDrive,📁 办公通讯"
    - "RULE-SET,Dropbox,📁 办公通讯"
    - "RULE-SET,Telegram_ip,📁 办公通讯"
    - "RULE-SET,Microsoft_no_ip,📁 办公通讯"
    - "RULE-SET,Docker,📁 办公通讯"
    - "RULE-SET,Npm,📁 办公通讯"
    - "RULE-SET,CustomProxyRules,📁 办公通讯"
  
    # ── 段 7 · AI 服务（32-34）→ 🤖 AI服务 ─────────────────────────
    - "RULE-SET,OpenAI,🤖 AI服务"
    - "RULE-SET,AI_no_ip,🤖 AI服务"
    - "RULE-SET,Gemini,🤖 AI服务"
  
    # ── 段 8 · 谷歌服务（35-37）→ 🔍 谷歌服务 ───────────────────────
    - "RULE-SET,Google,🔍 谷歌服务"
    - "RULE-SET,YouTube,🔍 谷歌服务"
    - "RULE-SET,GoogleFCM_ip,🔍 谷歌服务"
  
    # ── 段 9 · 大流量通道（38-44）→ 📺 大流量通道 ──────────────────
    - "RULE-SET,MicrosoftCDN_no_ip,📺 大流量通道"
    - "RULE-SET,CDN_domainset,📺 大流量通道"
    - "RULE-SET,CDN_no_ip,📺 大流量通道"
    - "RULE-SET,Download_domainset,📺 大流量通道"
    - "RULE-SET,Download_no_ip,📺 大流量通道"
    - "RULE-SET,GameDownload,📺 大流量通道"
    - "RULE-SET,Stream_ip,📺 大流量通道"
  
    # ── 段 10 · 游戏平台（45-49）→ 游戏平台 ─────────────────────────
    # homelab 场景下几乎用不到，但规则集已在链上，留着不影响分流
    # （流媒体解锁走 📺 流媒体节点 特性组，不走这里）
    - "RULE-SET,Steam,游戏平台"
    - "RULE-SET,UnrealRules,游戏平台"
    - "RULE-SET,Origin,游戏平台"
    - "RULE-SET,Sony,游戏平台"
    - "RULE-SET,Nintendo,游戏平台"
  
    # ── 段 11 · 兜底（50-51）──────────────────────────────────────
    # 这两条必须是最后两条。提前会让后面所有规则永不生效。
    - "GEOIP,CN,🛡️ 国内直连"
    - "MATCH,🌍 兜底代理"
NET_ROUTING_DATA_EOF

if [ ! -s "$NR_DATA" ]; then
    nr_log "ABORT: embedded data extraction failed"
    exit 0
fi

# ---------- 1. 备份 ----------
cp -f "$CONFIG_FILE" "$NR_BACKUP" 2>/dev/null
if [ ! -f "$NR_BACKUP" ]; then
    nr_log "ABORT: cannot create backup, refusing to modify"
    exit 0
fi

# ---------- 2. 合并 ----------
ruby -ryaml -rYAML -I "/usr/share/openclash" -E UTF-8 -e '
cfg_path = ARGV[0]
src_path = ARGV[1]
log_path = ARGV[2]
stamp    = ARGV[3]
cdn      = ARGV[4]

def nlog(lp, st, m)
  line = "#{st} [net-routing] #{m}"
  begin
    File.open(lp, "a") { |f| f.puts(line) }
  rescue
  end
  puts line
end

begin
  cfg = YAML.load_file(cfg_path) || {}
  src = (YAML.load_file(src_path) || {})["net-routing"] || {}
rescue => e
  nlog(log_path, stamp, "ABORT: YAML parse failed: #{e.message}")
  exit 0
end

nlog(log_path, stamp, "net-routing artifact: 1002 v1.3.0")

# ---- basic：顶层键直接覆盖 ----
(src["basic"] || {}).each { |k, v| cfg[k] = v }
nlog(log_path, stamp, "basic: #{(src["basic"] || {}).keys.join(", ")}")

# ---- sniffer：整体替换 ----
if src["sniffer"]
  cfg["sniffer"] = src["sniffer"]
  nlog(log_path, stamp, "sniffer: enabled")
end

# ---- dns：浅合并，保留 listen / enhanced-mode / fake-ip-range / use-hosts ----
# fake-ip-filter 是追加不是替换 —— 保住 OpenClash 注入的 rule-set:oc-cn-domain
if src["dns_merge"].is_a?(Hash) && !src["dns_merge"].empty?
  cfg["dns"] ||= {}
  merged = ((cfg["dns"]["fake-ip-filter"] || []) + (src["dns_merge"]["fake-ip-filter"] || [])).uniq
  cfg["dns"].merge!(src["dns_merge"])
  cfg["dns"]["fake-ip-filter"] = merged
  nlog(log_path, stamp, "dns merged, listen=#{cfg["dns"]["listen"]}, fif=#{merged.size}")
end

# ---- proxy-groups：整体替换 ----
old_g = (cfg["proxy-groups"] || []).map { |g| g["name"] }
cfg["proxy-groups"] = src["proxy-groups"] || []
new_g = cfg["proxy-groups"].map { |g| g["name"] }
nlog(log_path, stamp, "proxy-groups: #{old_g.size} -> #{new_g.size}")

# ---- rule-providers：合并，保留 OpenClash 注入的 oc-cn-domain ----
old_p = cfg["rule-providers"] || {}
cfg["rule-providers"] = old_p.merge(src["rule-providers"] || {})
kept = old_p.keys - (src["rule-providers"] || {}).keys
nlog(log_path, stamp, "rule-providers: +#{(src["rule-providers"] || {}).size}, preserved: #{kept.empty? ? "(none)" : kept.join(", ")}")

# ---- CDN 重写：raw.githubusercontent.com -> jsdelivr ----
#   https://raw.githubusercontent.com/OWNER/REPO/refs/heads/BRANCH/PATH
#     -> https://cdn.jsdelivr.net/gh/OWNER/REPO@refs/heads/BRANCH/PATH
rewritten = 0
(cfg["rule-providers"] || {}).each_value do |p|
  u = p["url"].to_s
  if u =~ %r{^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/(.+)$}
    p["url"] = cdn + "gh/" + $1 + "/" + $2 + "@" + $3
    rewritten += 1
  end
end
nlog(log_path, stamp, "provider CDN rewrite: #{rewritten} urls")

# ---- rules：整体替换 ----
old_r = cfg["rules"] || []
cfg["rules"] = src["rules"] || []
nlog(log_path, stamp, "rules: #{old_r.size} -> #{cfg["rules"].size}")

# ---- 自检 1：组内引用 ----
bad = []
(cfg["proxy-groups"] || []).each do |g|
  (g["proxies"] || []).each do |o|
    next if %w[DIRECT REJECT].include?(o) || o == g["name"]
    bad << "group #{g["name"]} references missing #{o}" unless new_g.include?(o)
  end
end

# ---- 自检 2：规则引用 ----
(cfg["rules"] || []).each do |r|
  if r.start_with?("RULE-SET,")
    pn = r.split(",")[1]
    bad << "undefined provider #{pn} <- #{r}" unless cfg["rule-providers"].key?(pn)
  end
  t = r.sub(/,no-resolve$/, "").split(",").last
  next if t == "no-resolve"
  next if %w[DIRECT REJECT GLOBAL].include?(t)
  bad << "undefined group #{t} <- #{r}" unless new_g.include?(t)
end

# ---- 自检 3：兜底两条必须在末尾 ----
rl = cfg["rules"] || []
if rl.last != "MATCH,🌍 兜底代理" || rl[-2] != "GEOIP,CN,🛡️ 国内直连"
  bad << "last two rules must be GEOIP,CN then MATCH, got: #{rl.last(2).join(" | ")}"
end

# ---- 自检 4：用真实节点名验证 filter 命中数 ----
names = (cfg["proxies"] || []).map { |p| p["name"] }
empty = []
(cfg["proxy-groups"] || []).each do |g|
  next unless g["include-all-proxies"]
  sel = names
  begin
    sel = sel.select { |n| n =~ /#{g["filter"]}/i } if g["filter"]
    sel = sel.reject { |n| n =~ /#{g["exclude-filter"]}/i } if g["exclude-filter"]
  rescue => e
    bad << "group #{g["name"]} regex broken: #{e.message}"
    next
  end
  nlog(log_path, stamp, format("  %-16s %-9s -> %d nodes", g["name"], g["type"], sel.size))
  empty << g["name"] if sel.empty?
end
nlog(log_path, stamp, "empty groups (use empty-fallback): #{empty.empty? ? "(none)" : empty.join(", ")}")

if bad.empty?
  nlog(log_path, stamp, "self-check OK")
else
  bad.first(20).each { |b| nlog(log_path, stamp, "SELF-CHECK FAIL: #{b}") }
  nlog(log_path, stamp, "ABORT: #{bad.size} problems, config NOT modified")
  exit 0
end

# ---- 落盘 ----
begin
  out = YAML.dump(cfg, line_width: -1)
  # Psych 默认把星形平面字符（emoji）转义成 \U0001F1ED，
  # 能解析但人没法看，还原成原始 UTF-8
  out = out.gsub(/\\U([0-9A-Fa-f]{8})/) { [$1.hex].pack("U") }
  File.open(cfg_path, "w") { |f| f.write(out) }
  nlog(log_path, stamp, "written #{File.size(cfg_path)} bytes")
rescue => e
  nlog(log_path, stamp, "ABORT: write failed: #{e.message}")
  exit 0
end
' "$CONFIG_FILE" "$NR_DATA" "$LOG_FILE" "$LOGTIME" "$NR_CDN"

rm -f "$NR_DATA"

# ---------- 3. 校验门 ----------
# 用内核自带的 -t 做离线校验。不带 -d /etc/openclash 找不到 geo 库会误报失败。
if [ -x "$NR_CORE" ]; then
    if "$NR_CORE" -t -d /etc/openclash -f "$CONFIG_FILE" > "$NR_VLOG" 2>&1; then
        rm -f "$NR_BACKUP" "$NR_VLOG"
        nr_log "validation PASSED, merge complete"
    else
        cp -f "$NR_BACKUP" "$CONFIG_FILE"
        nr_log "validation FAILED - ROLLED BACK to previous config"
        grep -iE 'error' "$NR_VLOG" 2>/dev/null | head -8 | while read -r l; do
            echo "${LOGTIME} [net-routing]   ${l}" >> "$LOG_FILE"
        done
        rm -f "$NR_VLOG"
    fi
else
    nr_log "WARN: no core binary, config written WITHOUT validation"
fi

exit 0
