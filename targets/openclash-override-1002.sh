#!/bin/sh
# ============================================================================
#  openclash-override-1002.sh —— net-routing 路由器侧覆写脚本
#
#  内容版本：v1.1.0
#  文件大版本：1002（2026-10-02 立项）
#  规模：51 条分流规则 / 43 个规则集 / 22 个策略组
#
# ── 文件定位 ────────────────────────────────────────────────────────
#  类型     OpenClash 自定义覆写脚本（Custom Overwrite Module）
#  入口     /etc/init.d/openclash 在处理完自身所有脚本后调用，$1 = 配置路径
#  位置     LuCI → 服务 → OpenClash → 覆写模块 → 覆写设置（整段粘贴）
#  依赖     mihomo 内核（用于 -t 离线校验）；ruby + ruby-yaml（OpenClash 自带）
#  产物     自包含单文件，数据段内嵌，不依赖任何外部文件
#
# ── 与 flclash-override-1001.js 的关系 ─────────────────────────────────
#  两端共用 rules/*.yaml 这一层规则定义，但产物在三点上有意分叉：
#    1. 策略组用 mihomo 原生 include-all-proxies + filter 声明式实现，
#       不需要 flclash 那套 classifyNodes 节点分类代码
#    2. 地区组一律不设 exclude-filter（实测会让美/英/台三个地区组清空）
#    3. 没有 TUN 段、没有 IPv6 三层封堵（路由器无 TUN 接管，见 docs/openclash.md）
#
# ── 绝不做的事 ───────────────────────────────────────────────────────
#  ✗ 改 proxies                订阅生成的节点，含服务器与密码
#  ✗ 改任何端口                 OpenClash 生成防火墙规则时按端口配对
#  ✗ 改 dns.listen             必须是 0.0.0.0:7874，dnsmasq 已配好转发到它
#  ✗ 改 authentication         面板密钥，由 OpenClash 管理
#  ✗ 改 tun 段                  混合模式自带
#
# ── 安全机制（三重）────────────────────────────────────────────────
#  1. 改前备份          备份到 ${CONFIG_FILE}.nr-bak
#  2. 交叉引用自检      RULE-SET 指向不存在的 provider / 规则指向不存在的组
#                      → mihomo 是硬失败（整份配置加载不了），提前拦
#  3. 离线校验门        写盘后用 clash_meta -t 校验，不通过自动回滚
#
#  ⚠️ 失败是静默的：OpenClash 的 ruby.sh 带 2>/dev/null，
#     屏幕上不会有任何报错，只写 /tmp/openclash.log。
#     改完分流没变化时，第一件事：
#         grep '\[net-routing\]' /tmp/openclash.log | tail -30
#
# ── 出问题怎么退 ────────────────────────────────────────────────────
#  最省事：LuCI 覆写设置页面顶部的恢复默认入口
#     http://<路由器IP>/cgi-bin/luci/admin/services/openclash/restore
#  或者把本文件内容替换回原厂模板（原厂文件见
#  https://raw.githubusercontent.com/vernesong/OpenClash/master/luci-app-openclash/root/etc/openclash/custom/openclash_custom_overwrite.sh
# ），然后重启 OpenClash。
# ============================================================================

. /usr/share/openclash/ruby.sh
. /usr/share/openclash/log.sh
. /lib/functions.sh

LOG_TIP "Start Running Custom Overwrite Scripts..."
LOGTIME=$(echo $(date "+%Y-%m-%d %H:%M:%S"))
LOG_FILE="/tmp/openclash.log"
CONFIG_FILE="$1"

NR_CORE="/etc/openclash/core/clash_meta"
NR_DATA="/tmp/nr-routes-$$.yaml"
NR_BACKUP="${CONFIG_FILE}.nr-bak"
NR_VLOG="/tmp/nr-validate-$$.log"

nr_log()
{
    echo "${LOGTIME} [net-routing] $1" >> "$LOG_FILE"
    echo "[net-routing] $1"
}

# ---------------------------------------------------------------------------
# 数据段：以下 YAML 是本文件唯一需要维护的内容（规则、策略组、规则集、DNS）
# 由 rules/*.yaml 渲染而来。标记之外是逻辑，改逻辑才需要动。
# ---------------------------------------------------------------------------
cat > "$NR_DATA" <<'NET_ROUTING_ROUTES_EOF'
# @generated:begin ROUTES   ← 由 rules/*.yaml 渲染，勿手改本段
# ============================================================================
# openclash-routes.yaml —— net-routing 路由器侧静态路由文档
#
# 用途：被 openclash_custom_overwrite.sh 读入，合并进 OpenClash 生成的配置。
#       合并器只读本文件，**不含任何节点名**，换任何订阅都通用。
#
# 生成方式：由 rules/*.yaml 渲染（人工/AI），改规则请改 rules/ 再重新生成。
# 内容版本：v1.0.0
#
# ── 本文件负责什么 ─────────────────────────────────────────────────
#   basic          顶层键，直接覆盖
#   proxy-groups   整体替换
#   rule-providers 合并（保留 OpenClash 注入的 oc-cn-domain）
#   rules          整体替换
#
# ── 本文件不负责什么（绝对不要往这里加）──────────────────────────
#   proxies            订阅生成，含服务器与密码
#   mixed-port 等端口   OpenClash 生成防火墙规则时按端口配对，改了会失配
#   dns.listen         必须是 0.0.0.0:7874，dnsmasq 已配好转发到它
#   authentication     面板密钥
#   dns 段             走 LuCI 的 @dns_servers 表 + openclash_custom_*.list，
#                      不在覆写里改（见 docs/openclash.md 第三节）
#   tun 段            OpenClash 混合模式自带，不动
# ============================================================================

meta:
  # 合并器不读这一段，仅供人 review
  version: "1.1.0"
  generated_for: "OpenClash 0.47.156 / mihomo alpha-ge183c58"
  scope: "homelab 设备（NAS / PVE / 服务器）；个人电脑与手机各自用 FlClash"
  rule_count: 51
  provider_count: 43
  group_count: 22


# ============================================================================
# dns —— 与 OpenClash 已有 dns 段做「浅合并」
#
# 只写需要改的键，以下 OpenClash 原有的键保持不动：
#   listen           0.0.0.0:7874   ← dnsmasq 已配好转发到它，绝不能动
#   enhanced-mode    fake-ip
#   fake-ip-range    198.18.0.1/16   ← 与 LAN 192.168.31.0/24 不冲突
#   use-hosts        true
#
# ⚠️ respect-rules 说明：
#   改 false → true，让 DNS 连接本身也走规则，这样国际 DoH 才能穿隧道。
#   实测 dns.google 317ms 返回 200（走代理），而原来的
#   fallback: [1.1.1.1, 8.8.8.8] + respect-rules:false 是直连，必然超时。
#
# ⚠️ 回退方案（出问题就用这个，把整段 dns 删掉即可恢复 OpenClash 原状）：
#   respect-rules: false
#   nameserver: 全部用国内明文 UDP，不配 nameserver-policy
#   理由与 FlClash 版一致，见 targets/flclash-override-1001.md 第六节
# ============================================================================

dns:
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


# ============================================================================
# basic —— 顶层键，直接覆盖
# ============================================================================
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
# ============================================================================

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
# @generated:end ROUTES
NET_ROUTING_ROUTES_EOF

# ===========================================================================
#  逻辑段：@generated 标记之外，改逻辑才动这里
# ===========================================================================

# ---------- 0. 前置检查 ----------
if [ -z "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ]; then
    nr_log "SKIP: config not found: ${CONFIG_FILE}"
    exit 0
fi

if [ ! -s "$NR_DATA" ]; then
    nr_log "ABORT: embedded routes data is empty or extraction failed"
    exit 0
fi

if [ ! -x "$NR_CORE" ]; then
    nr_log "WARN: core binary missing at ${NR_CORE}, validation gate DISABLED"
fi

# ---------- 1. 备份（任何写操作之前）----------
cp -f "$CONFIG_FILE" "$NR_BACKUP" 2>/dev/null
if [ ! -f "$NR_BACKUP" ]; then
    nr_log "ABORT: cannot create backup, refusing to modify config"
    exit 0
fi

# ---------- 2. 合并 ----------
ruby -ryaml -rYAML -I "/usr/share/openclash" -E UTF-8 -e '
cfg_path = ARGV[0]
src_path = ARGV[1]
log_path = ARGV[2]
stamp    = ARGV[3]

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
  src = YAML.load_file(src_path) || {}
rescue => e
  nlog(log_path, stamp, "ABORT: YAML parse failed: #{e.message}")
  exit 0
end

# meta 段只供人 review，不进配置
src = src.reject { |k, _| k == "meta" }
nlog(log_path, stamp, "loaded config, routes sections: #{src.keys.size}")

# ---- basic：顶层键直接覆盖 ----
(src["basic"] || {}).each { |k, v| cfg[k] = v }
nlog(log_path, stamp, "basic: #{(src["basic"] || {}).keys.join(", ")}")

# ---- dns：浅合并，保留 listen / enhanced-mode / fake-ip-range ----
# 只在源里存在 dns 段时才动。删掉源里的 dns 段即恢复 OpenClash 原生 DNS。
if src["dns"].is_a?(Hash) && !src["dns"].empty?
  cfg["dns"] ||= {}
  # fake-ip-filter 叠加而非替换 —— 保住 OpenClash 注入的 rule-set:oc-cn-domain
  merged = ((cfg["dns"]["fake-ip-filter"] || []) + (src["dns"]["fake-ip-filter"] || [])).uniq
  cfg["dns"].merge!(src["dns"])
  cfg["dns"]["fake-ip-filter"] = merged
  nlog(log_path, stamp, "dns merged, fake-ip-filter = #{merged.size} entries, listen kept = #{cfg["dns"]["listen"]}")
end

# ---- proxy-groups：整体替换 ----
old_g = (cfg["proxy-groups"] || []).map { |g| g["name"] }
cfg["proxy-groups"] = src["proxy-groups"] || []
nlog(log_path, stamp, "proxy-groups: #{old_g.size} -> #{cfg["proxy-groups"].size}")

# ---- rule-providers：合并，保留 OpenClash 注入的 ----
old_p = cfg["rule-providers"] || {}
cfg["rule-providers"] = old_p.merge(src["rule-providers"] || {})
kept = old_p.keys - (src["rule-providers"] || {}).keys
nlog(log_path, stamp, "rule-providers: +#{(src["rule-providers"] || {}).size}, preserved from OpenClash: #{kept.empty? ? "(none)" : kept.join(", ")}")

# ---- rules：整体替换 ----
old_r = cfg["rules"] || []
cfg["rules"] = src["rules"] || []
nlog(log_path, stamp, "rules: #{old_r.size} -> #{cfg["rules"].size}")

# ---- 自检：交叉引用完整性 ----
# mihomo 对「RULE-SET 指向不存在的 provider」和「规则指向不存在的组」
# 都是硬失败（整份配置加载不了），不是静默空载。这里提前拦。
groups = (cfg["proxy-groups"] || []).map { |g| g["name"] }
provs  = (cfg["rule-providers"] || {}).keys
bad = []

(cfg["rules"] || []).each do |r|
  if r.start_with?("RULE-SET,")
    pn = r.split(",")[1]
    bad << "undefined provider #{pn} <- #{r}" unless provs.include?(pn)
  end
  t = r.sub(/,no-resolve$/, "").split(",").last
  next if t == "no-resolve"
  next if %w[DIRECT REJECT GLOBAL].include?(t)
  bad << "undefined group #{t} <- #{r}" unless groups.include?(t)
end

(cfg["proxy-groups"] || []).each do |g|
  (g["proxies"] || []).each do |o|
    next if %w[DIRECT REJECT].include?(o) || o == g["name"]
    bad << "group #{g["name"]} references missing #{o}" unless groups.include?(o)
  end
end

# 兜底两条必须在末尾
rl = cfg["rules"] || []
if rl.last != "MATCH,🌍 兜底代理" || rl[-2] != "GEOIP,CN,🛡️ 国内直连"
  bad << "last two rules must be GEOIP,CN then MATCH, got: #{rl.last(2).join(" | ")}"
end

if bad.empty?
  nlog(log_path, stamp, "self-check OK (#{cfg["rules"].size} rules, #{groups.size} groups, #{provs.size} providers)")
else
  bad.first(20).each { |b| nlog(log_path, stamp, "SELF-CHECK FAIL: #{b}") }
  nlog(log_path, stamp, "ABORT: #{bad.size} problems, config NOT modified")
  exit 0
end

# ---- 落盘 ----
begin
  out = YAML.dump(cfg, line_width: -1)
  # Psych 默认把星形平面字符（emoji）转义成 \U0001F1ED，
  # 解析没问题但人没法看，还原成原始 UTF-8
  out = out.gsub(/\\U([0-9A-Fa-f]{8})/) { [$1.hex].pack("U") }
  File.open(cfg_path, "w") { |f| f.write(out) }
  nlog(log_path, stamp, "written #{File.size(cfg_path)} bytes")
rescue => e
  nlog(log_path, stamp, "ABORT: write failed: #{e.message}")
  exit 0
end
' "$CONFIG_FILE" "$NR_DATA" "$LOG_FILE" "$LOGTIME"

rm -f "$NR_DATA"

# ---------- 3. 校验门 ----------
# 用内核自带的 -t 做离线校验。不带 -d 找不到 geo 库会误报失败。
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
