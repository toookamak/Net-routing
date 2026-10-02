#!/bin/sh
# ============================================================================
#  openclash-groups-1002.sh —— 策略组专用覆写脚本
#
#  部署位置：/etc/openclash/custom/openclash_custom_overwrite.sh
#  配套：targets/openclash-override-1002.conf（覆写模块，负责规则/规则集/DNS）
#
#  ── 为什么单独拆一个文件 ──────────────────────────────────────────
#  OpenClash 覆写模块的 [YAML] 块在处理 proxy-groups! （数组套对象整体替换）
#  时，会把元素内**值里含竖线 `|` 的键整行丢掉**。2026-10-02 实测：
#
#      活下来： type / include-all-proxies / empty-fallback / url / interval
#              / tolerance / lazy                        ← 值里都没有 `|`
#      死掉：  filter / exclude-filter                    ← 值里全是 `|`
#
#  `|` 是 YAML 的块标量指示符，OpenClash 那个块的解析器是逐行处理的，
#  不是完整 YAML 解析器。rules! 里的规则不含 `|`，所以 51 条规则全部正常；
#  只有 filter 系的值中招。
#
#  绕法 A（把 `|` 换成 `\n` 多行正则）走不通 —— 同一个解析器不处理引号内的
#  转义序列，`\n` 只会原样传下去，mihomo 收到的是字面反斜杠 n。
#  所以策略组这一块退回走本脚本：Psych 直接读写 YAML，中间没有那个解析器。
#
#  ── 分工 ────────────────────────────────────────────────────────
#  覆写模块 .conf  →  rules! / rule-providers / dns / basic   （已验证正常）
#  本脚本 .sh      →  proxy-groups                            （绕开解析器）
#
#  执行顺序：覆写模块在第 ③ 步，本脚本在第 ④ 步（最后），所以本脚本的
#  策略组最终生效，不会被覆写模块覆盖。
#
#  内容版本：v1.1.0    文件大版本：1002（2026-10-02）
#  规模：22 个策略组
#
#  ── 安全机制 ────────────────────────────────────────────────────
#    备份 → 交叉引用自检 → 写盘 → clash_meta -t 离线校验 → 失败自动回滚
#
#  ── 出问题怎么退 ────────────────────────────────────────────────
#    把本文件内容替换回原厂模板后重启 OpenClash。原厂模板：
#    https://github.com/vernesong/OpenClash/blob/master/luci-app-openclash/root/etc/openclash/custom/openclash_custom_overwrite.sh
#    或点 LuCI 覆写设置页顶部的 /cgi-bin/luci/admin/services/openclash/restore
#
#  ── 排错 ────────────────────────────────────────────────────────
#    Ruby 失败在屏幕上完全静默（OpenClash 的 ruby.sh 带 2>/dev/null），
#    只写日志：
#        grep '\[net-routing\]' /tmp/openclash.log | tail -20
# ============================================================================

. /usr/share/openclash/ruby.sh
. /usr/share/openclash/log.sh
. /lib/functions.sh

LOG_TIP "net-routing groups overwrite starting..."
LOGTIME=$(echo $(date "+%Y-%m-%d %H:%M:%S"))
LOG_FILE="/tmp/openclash.log"
CONFIG_FILE="$1"

NR_CORE="/etc/openclash/core/clash_meta"
NR_DATA="/tmp/nr-groups-$$.yaml"
NR_BACKUP="${CONFIG_FILE}.nr-bak"
NR_VLOG="/tmp/nr-validate-$$.log"

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
if [ ! -s "$NR_DATA" ] && [ ! -f "$NR_DATA" ]; then
    nr_log "SKIP: groups data not extracted"
    exit 0
fi

# ---------- 1. 写出内嵌策略组 ----------
cat > "$NR_DATA" <<'NET_ROUTING_GROUPS_EOF'
# @generated:begin GROUPS   ← 由 rules/groups.yaml + rules/regions.yaml + rules/filters.yaml 渲染
# ---------------------------------------------------------------------------
# 全部用 mihomo 原生 include-all-proxies + filter 正则声明，组内不含任何节点名，
# 换订阅依然成立。
#
# 地区组一律不设 exclude-filter —— 实测排低倍率会让美国 12→0、英国 4→0，
# 排流媒体会让台湾 1→0。详见 targets/openclash-override-1002.md 第三节。
#
# 通知节点关键词（下方多处引用）：
#   自动|故障|流量|官网|套餐|机场|订阅|年付|月付|失联|频道|Traffic|Expire|剩余|激励|分享|到期|续费|充值
# ---------------------------------------------------------------------------

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
    # 通知节点绝不能参与测速 —— 它们是流量/到期提示，不是线路
    exclude-filter: "自动|故障|流量|官网|套餐|机场|订阅|年付|月付|失联|频道|Traffic|Expire|剩余|激励|分享|到期|续费|充值"
    empty-fallback: DIRECT
    url: "http://www.gstatic.com/generate_204"
    interval: 1800
    # 路由器比客户端更需要容差：服务器上的长连接（docker pull / rsync /
    # 数据库同步）经不起一次中途切换导致的 TCP 重连
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
    # 本组不设 filter，因此也包含「未命中任何地区」的节点。
    # flclash 版有个「🌐 其他地区」组用来兜这些节点，路由器上做不出来 ——
    # 正则无法表达「不匹配上述任何地区」（Go RE2 不支持否定前瞻）。

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
    # 不用单字「台」（会误伤）；部分机场用 🇨🇳 而非 🇹🇼 标台湾，
    # 靠「台湾」这个双字命中，国旗只是附加项
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
    # 多数订阅无此类节点，本组会走 empty-fallback 落到 DIRECT。
    # 组本身无害（实测内核容忍空组）。不想看它就在 groups.yaml 里注释掉。

  - name: "💰 低倍率节点"
    type: select
    include-all-proxies: true
    # lowrate + lowrate_numeric 合并。数字写法（0.5x / 0.1x）是主流机场的
    # 实际记法，rules/filters.yaml 原先只覆盖中文写法，实测命中 0 个。
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
  # 每一项都含 DIRECT —— 让用户能不改规则就把某一类流量改成直连。
  # 路由器场景下 homelab 机器没人去面板上点，这个设计更关键。

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
    # 默认 DIRECT。接入 GEOIP,CN
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
# @generated:end GROUPS
NET_ROUTING_GROUPS_EOF

if [ ! -s "$NR_DATA" ]; then
    nr_log "ABORT: groups data extraction failed"
    exit 0
fi

# ---------- 2. 备份 ----------
cp -f "$CONFIG_FILE" "$NR_BACKUP" 2>/dev/null
if [ ! -f "$NR_BACKUP" ]; then
    nr_log "ABORT: cannot create backup, refusing to modify"
    exit 0
fi

# ---------- 3. 合并 ----------
ruby -ryaml -rYAML -I "/usr/share/openclash" -E UTF-8 -e '
cfg_path = ARGV[0]
grp_path = ARGV[1]
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
  grp = (YAML.load_file(grp_path) || {})["proxy-groups"] || []
rescue => e
  nlog(log_path, stamp, "ABORT: YAML parse failed: #{e.message}")
  exit 0
end

old_names = (cfg["proxy-groups"] || []).map { |g| g["name"] }
new_names = grp.map { |g| g["name"] }
nlog(log_path, stamp, "proxy-groups: #{old_names.size} -> #{new_names.size}")

# ---- 自检 1：组内引用的组必须存在 ----
bad = []
grp.each do |g|
  (g["proxies"] || []).each do |o|
    next if %w[DIRECT REJECT].include?(o) || o == g["name"]
    bad << "group #{g["name"]} references missing #{o}" unless new_names.include?(o)
  end
end

# ---- 自检 2：规则引用到的组必须存在 ----
(cfg["rules"] || []).each do |r|
  t = r.sub(/,no-resolve$/, "").split(",").last
  next if t == "no-resolve"
  next if %w[DIRECT REJECT GLOBAL MATCH].include?(t)
  bad << "rule references missing group #{t} <- #{r}" unless new_names.include?(t)
end

# ---- 自检 3：用真实节点名验证 filter 是否能匹配 ----
names = (cfg["proxies"] || []).map { |p| p["name"] }
empty = []
grp.each do |g|
  next unless g["include-all-proxies"]
  sel = names
  begin
    sel = sel.select { |n| n =~ /#{g["filter"]}/i } if g["filter"]
    sel = sel.reject { |n| n =~ /#{g["exclude-filter"]}/i } if g["exclude-filter"]
  rescue => e
    bad << "group #{g["name"]} regex broken: #{e.message}"
    next
  end
  nlog(log_path, stamp, format("  %-14s %s -> %d nodes", g["name"], g["type"], sel.size))
  empty << g["name"] if sel.empty?
end
nlog(log_path, stamp, "empty groups (will use empty-fallback): #{empty.empty? ? "(none)" : empty.join(", ")}")

if bad.empty?
  nlog(log_path, stamp, "self-check OK")
else
  bad.first(20).each { |b| nlog(log_path, stamp, "SELF-CHECK FAIL: #{b}") }
  nlog(log_path, stamp, "ABORT: #{bad.size} problems, config NOT modified")
  exit 0
end

cfg["proxy-groups"] = grp

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
' "$CONFIG_FILE" "$NR_DATA" "$LOG_FILE" "$LOGTIME"

rm -f "$NR_DATA"

# ---------- 4. 校验门 ----------
if [ -x "$NR_CORE" ]; then
    if "$NR_CORE" -t -d /etc/openclash -f "$CONFIG_FILE" > "$NR_VLOG" 2>&1; then
        rm -f "$NR_BACKUP" "$NR_VLOG"
        nr_log "validation PASSED, groups merge complete"
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
