#!/bin/sh
# ============================================================================
# OpenClash 代理组地基验证 —— 零风险版
#
# 只做两件事：
#   1) 读现有配置与运行中内核的状态
#   2) 在 /tmp 构造测试配置，验证 filter 语法是否被本内核接受
#
# 绝不触碰：
#   ✗ /etc/openclash/*.yaml（实际配置）
#   ✗ /etc/openclash/custom/ 任何文件
#   ✗ 任何端口、防火墙、UCI 设置
#   ✗ 不会重启 OpenClash / mihomo
#
# 用法：
#   scp .\test\openclash-verify-groups.sh root@192.168.31.1:/tmp/
#   ssh root@192.168.31.1
#   sh /tmp/openclash-verify-groups.sh 2>&1 | tee /tmp/verify-out.txt
# ============================================================================

TS=$(date +%s)
WORK="/tmp/nr-verify-$TS"
mkdir -p "$WORK"
echo "工作目录: $WORK（重启即消失）"
echo

# 定位实际配置：从所有候选 PID 里挑第一个 cmdline 带 .yaml 的
# （直接 pgrep -f clash 会误匹配 /usr/share/openclash/ 下的辅助进程）
CFG=""
for p in $(pgrep -f 'clash' 2>/dev/null); do
    c=$(tr '\0' '\n' < /proc/$p/cmdline 2>/dev/null | grep '\.yaml$' | head -1)
    if [ -n "$c" ] && [ -f "$c" ]; then CFG="$c"; CORE_PID="$p"; break; fi
done
if [ -z "$CFG" ]; then
    CFG=$(ls -1 /etc/openclash/*.yaml 2>/dev/null | grep -v custom | head -1)
fi
echo "实际配置: ${CFG:-【未找到】}"
if [ -z "$CFG" ]; then
    echo "找不到配置文件，终止"
    exit 1
fi
if [ ! -f "$CFG" ]; then
    echo "配置路径存在但文件不可读，终止"
    exit 1
fi
echo

echo "############################################################"
echo "# 1. 内核 CLI 能力探测"
echo "############################################################"
CORE_BIN=""
for b in /etc/openclash/core/clash_meta /etc/openclash/core/clash /etc/openclash/clash; do
    [ -x "$b" ] && { CORE_BIN="$b"; break; }
done
echo "内核路径: ${CORE_BIN:-【未找到】}"
[ -z "$CORE_BIN" ] && { echo "找不到内核，无法做语法验证"; exit 1; }
echo "版本: $("$CORE_BIN" -v 2>&1 | head -1)"
echo
echo "--- --help 输出（查是否有配置测试开关）---"
"$CORE_BIN" -h 2>&1 | head -30
echo
HAS_T=0
"$CORE_BIN" -h 2>&1 | grep -qE '(^|[[:space:]])-t([[:space:],]|$)|--test' && HAS_T=1
echo ">>> 配置测试开关(-t / --test): $([ $HAS_T -eq 1 ] && echo '存在 ✅' || echo '不存在 ❌')"
echo

echo "############################################################"
echo "# 2. 现状：当前策略组"
echo "############################################################"
echo "--- 配置文件里的 proxy-groups ---"
ruby -ryaml -e '
d = YAML.load_file(ARGV[0]) || {}
(d["proxy-groups"] || []).each_with_index do |g,i|
  puts format("  [%d] %-14s %-10s 成员:%-4d filter:%-8s exclude-filter:%-8s include-all:%s",
    i+1, g["type"].to_s, g["name"].to_s,
    (g["proxies"]||[]).size,
    g["filter"] ? "有" : "无",
    g["exclude-filter"] ? "有" : "无",
    (g["include-all-proxies"] || g["include-all"] || g["include-all-providers"]) ? "是" : "否")
end
' "$CFG"
echo
echo "--- 运行中内核的 API 视角（只读 GET）---"
SECRET=$(ruby -ryaml -e 'd=YAML.load_file(ARGV[0])||{}; a=d["authentication"]||[]; puts a[0].to_s.split(":",2)[1]||""' "$CFG")
if command -v curl >/dev/null 2>&1; then
    RESP=$(curl -s -m 6 -H "Authorization: Bearer $SECRET" http://127.0.0.1:9090/proxies 2>/dev/null)
    if [ -n "$RESP" ]; then
        echo "$RESP" | ruby -rjson -e '
          begin
            j = JSON.parse(STDIN.read)
            g = j["proxies"] || {}
            types = Hash.new(0)
            g.each { |k,v| types[v["type"]] += 1 }
            puts "  API 可达 ✅  内核报告 #{g.size} 个出站对象"
            puts "  类型分布: " + types.map{|k,v| "#{k}:#{v}"}.join(", ")
            now = j.dig("proxies") || {}
            sel = now.select { |_,v| v["type"] == "Selector" }
            sel.each do |name,v|
              puts "  [select] #{name}  当前选中=#{v["now"]}  选项数=#{(v["all"]||[]).size}"
            end
          rescue => e
            puts "  API 返回解析失败: #{e.message}"
          end'
    else
        echo "  API 无响应（可能 controller 端口不同或未监听）"
    fi
else
    echo "  路由器无 curl，跳过"
fi
echo

echo "############################################################"
echo "# 3. ⭐ 正则模拟：rules/*.yaml 的模式能否命中真实节点"
echo "############################################################"
echo "（以下「现状」为当前 rules/*.yaml 内容，「建议」为待扩充内容）"
echo
ruby -ryaml -e '
d = YAML.load_file(ARGV[0]) || {}
nodes = (d["proxies"] || []).map { |x| x["name"] }
if nodes.empty?
  puts "!! proxies 为空，无法模拟"
  exit
end
puts "节点总数: #{nodes.size}"
puts

# ---- 地区 ----
REGIONS_NOW = {
  "香港"   => "香港|HK|Hong Kong|🇭🇰",
  "新加坡" => "新加坡|狮城|SG|Singapore|🇸🇬",
  "日本"   => "日本|JP|Japan|🇯🇵",
  "美国"   => "美国|US|USA|United States|America|🇺🇸",
}
REGIONS_NEW = {
  "英国(建议新增)"   => "英国|UK|United Kingdom|伦敦|🇬🇧",
  "台湾(建议新增)"   => "台湾|台灣|Taiwan",
  "韩国(建议新增)"   => "韩国|KR|Korea|首尔|🇰🇷",
  "德国(建议新增)"   => "德国|DE|Germany|法兰克福|🇩🇪",
}

puts "===== 地区 filter 命中统计 ====="
puts format("  %-20s %-6s %s", "地区", "命中", "样例")
(REGIONS_NOW.merge(REGIONS_NEW)).each do |name, re|
  hit = nodes.select { |n| n =~ /#{re}/i }
  sample = hit.first(3).map { |x| x.length > 24 ? x[0,24]+"…" : x }
  printf("  %-20s %-6d %s\n", name, hit.size, sample.join(" / "))
end
puts

# ---- 特征 ----
FILTERS = {
  "通知(现状·strict)"      => "自动|故障|流量|官网|套餐|机场|订阅|年付|月付|失联|频道|Traffic|Expire|剩余|激励|分享|到期|续费|充值",
  "家宽(现状)"            => "家宽|原生|residential|home",
  "低倍率(现状)"          => "低倍率|lowrate|低-rate|倍率",
  "低倍率(建议扩充)"      => "低倍率|lowrate|低-rate|倍率|0\\.\\d+x|[0-9]+倍",
  "流媒体(建议新增)"      => "流媒体|解锁|Netflix|Disney|IPLC|IEPL",
}
puts "===== 特征 filter 命中统计 ====="
puts format("  %-24s %-6s %s", "特征", "命中", "样例")
FILTERS.each do |name, re|
  hit = nodes.select { |n| n =~ /#{re}/i }
  sample = hit.first(3).map { |x| x.length > 24 ? x[0,24]+"…" : x }
  printf("  %-24s %-6d %s\n", name, hit.size, sample.join(" / "))
end
puts

# ---- 关键风险：地区组若排掉特性节点会不会变空 ----
puts "===== ⚠️ 交叉风险检查：地区组排除特性后是否还有货 ====="
SPECIALS = {
  "流媒体"   => "流媒体",
  "低倍率"   => "低倍率|lowrate|低-rate|倍率|0\\.\\d+x|[0-9]+倍",
  "通知"     => FILTERS["通知(现状·strict)"],
}
combos = [
  ["不排除任何特性", nil],
  ["排除 流媒体",    "流媒体"],
  ["排除 低倍率",    "低倍率|lowrate|低-rate|倍率|0\\.\\d+x|[0-9]+倍"],
  ["排除 流媒体+低倍率", "流媒体|低倍率|lowrate|低-rate|倍率|0\\.\\d+x|[0-9]+倍"],
]
(REGIONS_NOW.merge(REGIONS_NEW)).each do |rname, rre|
  row = combos.map do |label, exre|
    sel = nodes.select { |n| n =~ /#{rre}/i }
    sel = sel.reject { |n| n =~ /#{exre}/i } if exre
    label + "=" + sel.size.to_s
  end
  empty = combos.any? { |_, exre|
    sel = nodes.select { |n| n =~ /#{rre}/i }
    sel = sel.reject { |n| n =~ /#{exre}/i } if exre
    sel.empty?
  }
  printf("  %-20s %s%s\n", rname, row.join("  "), empty ? "   ← 有组合会变空" : "")
end
' "$CFG"
echo

echo "############################################################"
echo "# 4. ⭐ 语法验证：filter / empty-fallback 是否被本内核接受"
echo "############################################################"
if [ "$HAS_T" -ne 1 ]; then
    echo "内核没有 -t 开关，跳过本节。"
    echo "（仍可人工核对：把 $WORK/test-groups.yaml 内容贴回来审阅）"
else
    ruby -ryaml -e '
require "yaml"
out = ARGV[0]

# 用假节点复刻真实命名形态，不含任何真实凭据
fake = [
  "剩余流量：917.91 GB", "套餐到期：长期有效",
  "🇭🇰香港高速01|BGP|CMCU", "🇭🇰香港高速02|BGP|CMCU",
  "🇯🇵日本高速01|CTCU|0.5x", "🇯🇵日本专线01|BGP|流媒体",
  "🇸🇬新加坡高速01|BGP|CTCUCM", "🇸🇬新加坡专线01|BGP|流媒体",
  "🇺🇸美国高速01|CTCU|0.1x", "🇺🇸美国洛杉矶01|流媒体|0.01x",
  "🇬🇧英国伦敦01|流媒体|0.1x", "🇨🇳台湾专线01|BGP|流媒体",
]
proxies = fake.map do |n|
  { "name" => n, "type" => "ss", "server" => "127.0.0.1", "port" => 8388,
    "cipher" => "aes-128-gcm", "password" => "dummy" }
end

def g(name, type, re: nil, exre: nil, empty: nil, default: nil, extra: {})
  h = { "name" => name, "type" => type, "include-all-proxies" => true,
        "url" => "http://www.gstatic.com/generate_204", "interval" => 300,
        "lazy" => true }
  h["filter"] = re if re
  h["exclude-filter"] = exre if exre
  h["empty-fallback"] = empty if empty
  h["default-selected"] = default if default
  h.merge!(extra)
end

cfg = {
  "mode" => "rule",
  "log-level" => "warning",
  "proxies" => proxies,
  "proxy-groups" => [
    g("T1 全部节点",   "select",  empty: "DIRECT", default: "🇭🇰香港高速01|BGP|CMCU",
      extra: { "proxies" => ["DIRECT"] }),
    g("T2 香港",       "url-test", re: "香港|HK|Hong Kong|🇭🇰", empty: "DIRECT"),
    g("T3 台湾",       "url-test", re: "台湾|台灣|Taiwan",       empty: "DIRECT"),
    g("T4 英国",       "url-test", re: "英国|UK|United Kingdom|伦敦|🇬🇧", empty: "DIRECT"),
    g("T5 低倍率",     "select",  re: "0\\.\\d+x|[0-9]+倍",      empty: "DIRECT"),
    g("T6 流媒体",     "select",  re: "流媒体|解锁|Netflix|Disney|IPLC|IEPL", empty: "DIRECT"),
    g("T7 剔通知",     "select",
      exre: "自动|故障|流量|官网|套餐|机场|订阅|年付|月付|失联|频道|Traffic|Expire|剩余|激励|分享|到期|续费|充值",
      empty: "DIRECT"),
    # 故意构造一个永远匹配不到的地区，验证 empty-fallback 是否真的兜住
    g("T8 空组对照组", "url-test", re: "火星|水星|木星", empty: "DIRECT"),
    # 故意不设 empty-fallback 的空组 —— 若内核不报错说明该保护是多余的
    g("T9 空组无兜底", "url-test", re: "冥王星"),
    g("T10 顶层",      "select",  extra: { "proxies" => ["T1 全部节点","T2 香港","T8 空组对照组","DIRECT"] }),
  ],
  "rules" => [
    "IP-CIDR,100.64.0.0/10,DIRECT,no-resolve",
    "RULE-SET,NoSuchProvider,DIRECT",     # 故意引用不存在的 provider，看是否报错
    "IP-CIDR,1.1.1.1/32,T2 香港,no-resolve",
    "GEOIP,CN,DIRECT",
    "MATCH,T10 顶层",
  ],
}
File.open(out, "w") { |f| f.write(YAML.dump(cfg)) }
puts "测试配置已生成: #{out}"
' "$WORK/test-groups.yaml"

    echo
    echo "--- 生成内容 ---"
    cat "$WORK/test-groups.yaml"
    echo
    echo "--- 运行内核配置校验 ---"
    # ⚠️ 不要写成 `... | head -40`，那样 $? 拿到的是 head 的退出码而非内核的
    "$CORE_BIN" -t -d /etc/openclash -f "$WORK/test-groups.yaml" > "$WORK/validate.log" 2>&1
    RC=$?
    head -40 "$WORK/validate.log"
    echo
    echo ">>> 校验退出码: $RC （0 = 通过）"
    if [ "$RC" -eq 0 ]; then
        echo ">>> ✅ 本内核接受 include-all-proxies / filter / exclude-filter / empty-fallback"
    else
        echo ">>> ❌ 校验未通过，见上方报错。**不要**据此改线上配置。"
    fi
    echo
    echo "注意：测试配置里故意放了 3 个「陷阱项」，用来观察内核的校验严格度："
    echo "  T8 空组对照组  filter 匹配不到 + 有 empty-fallback  → 期望通过"
    echo "  T9 空组无兜底  filter 匹配不到 + 无 empty-fallback  → 看内核是否报错"
    echo "  RULE-SET,NoSuchProvider  引用不存在的 provider      → 看内核是否报错"
    echo
    echo "  T9 与 NoSuchProvider 若都报错，说明内核校验严格，"
    echo "  那么「空组必须配 empty-fallback」就是硬性要求，不是可选项。"
fi
echo

echo "############################################################"
echo "# 5. 结论"
echo "############################################################"
echo "1. 实际配置从未被修改，所有产物都在 $WORK"
echo "2. 未重启 OpenClash，未改任何 UCI / 端口 / 防火墙"
echo "3. 第 3 节 = 正则能否命中真实订阅（决定 regions/filters 怎么改）"
echo "4. 第 4 节 = 本内核是否接受 filter 语法（决定架构是否成立）"
echo "###VERIFY_DONE###"
