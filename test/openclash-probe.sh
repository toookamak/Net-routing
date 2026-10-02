#!/bin/sh
# ============================================================================
# OpenClash 现状探针 v2 —— 纯只读，不修改任何配置
#
# 用法：
#   1) scp 本文件到路由器：
#        scp .\test\openclash-probe.sh root@192.168.31.1:/tmp/probe.sh
#   2) ssh 登录后执行：
#        sh /tmp/probe.sh 2>&1 | tee /tmp/probe-out.txt
#   3) 把 /tmp/probe-out.txt 的内容贴回来
#
# v2 相对 v1 的改动：
#   - 改用「运行中内核进程的 -f 参数」反查配置路径，修掉 v1 第 3 节定位失败
#   - 输出加 NODE|GRP|RPROV|RULE|KEY| 前缀标记，便于精确提取
#   - 新增 IPv6 泄漏面详查（RA / DHCPv6 / odhcpd / sysctl）
#   - 新增「区域绕过」注入规则的排查
#   - 新增 Tailscale 真实路由检查（policy routing，不在主路由表）
#   - 新增 dump 路由器上现有的覆写脚本内容
# ============================================================================

echo "############################################################"
echo "# 0. 配置文件定位（v1 失败点，优先用进程反查）"
echo "############################################################"
echo "--- 各种 UCI 键名探测（找出为什么 config_path 为空）---"
for k in config_path config_name config file_name; do
    v=$(uci -q get openclash.$k 2>/dev/null)
    echo "  openclash.$k = ${v:-(不存在/为空)}"
done
echo

echo "--- 运行中的内核进程（最可靠的配置来源）---"
CORE_PID=$(pgrep -f 'clash_meta|clash' 2>/dev/null | head -1)
if [ -n "$CORE_PID" ]; then
    echo "  内核 PID = $CORE_PID"
    echo "  完整命令行:"
    tr '\0' ' ' < /proc/$CORE_PID/cmdline 2>/dev/null
    echo
    echo
else
    echo "  !! 未找到运行中的内核进程，OpenClash 可能未启动"
fi
echo

# --- 配置路径三级回退 ---
CFG=""
if [ -n "$CORE_PID" ]; then
    CFG=$(tr '\0' '\n' < /proc/$CORE_PID/cmdline 2>/dev/null | grep '\.yaml$' | head -1)
fi
if [ -z "$CFG" ]; then
    for c in /etc/openclash/*.yaml; do
        case "$c" in
            *custom*|*ovw*|*backup*|*_old*) ;;
            *) [ -f "$c" ] && CFG="$c" && break ;;
        esac
    done
fi
if [ -z "$CFG" ]; then
    CFG=$(ls -1 /etc/openclash/config/*.yaml 2>/dev/null | head -1)
fi

echo ">>> 定位到的配置文件: ${CFG:-【失败】}"
if [ -z "$CFG" ] || [ ! -f "$CFG" ]; then
    echo "!!! 定位失败，目录实况如下，请把这段贴回来："
    ls -la /etc/openclash/ 2>/dev/null
    echo "---"
    ls -la /etc/openclash/config/ 2>/dev/null
    echo "--- uci 全量 openclash 主配置段 ---"
    uci -q show openclash 2>/dev/null | head -80
    echo "###PROBE_DONE###"
    exit 1
fi
echo

echo "############################################################"
echo "# 1. 配置内容"
echo "############################################################"
ruby -ryaml -e '
begin
  d = YAML.load_file(ARGV[0])
rescue => e
  puts "!!! YAML 解析失败: #{e.message}"
  exit
end
d ||= {}

puts "###CFG|#{ARGV[0]}"
puts "###TOPKEYS|#{(d.keys.sort).join(",")}"
puts

# ---------- 节点 ----------
n = d["proxies"] || []
puts "###NODECOUNT|#{n.size}"
n.each { |x| puts "NODE|#{x["name"]}|#{x["type"]}" }
puts
puts "###NODETYPES|#{n.group_by{|x| x["type"]}.map{|k,v| "#{k}:#{v.size}"}.join(",")}"
puts

# ---------- 订阅自带策略组 ----------
puts "###GROUPCOUNT|#{(d["proxy-groups"]||[]).size}"
(d["proxy-groups"]||[]).each { |g| puts "GRP|#{g["type"]}|#{g["name"]}|#{((g["proxies"]||[]).size + (g["use"]||[]).size)}" }
puts

# ---------- 订阅自带 provider ----------
pp_ = d["proxy-providers"] || {}
puts "###PROVIDERCOUNT|#{pp_.size}"
pp_.each { |k,v| puts "PPROV|#{k}|#{v["path"]}" }
puts

rp = d["rule-providers"] || {}
puts "###RULEPROVCOUNT|#{rp.size}"
rp.each { |k,v| puts "RPROV|#{k}|#{v["behavior"]}|#{v["format"]}|#{v["path"]}" }
puts

# ---------- 规则链 ----------
r = d["rules"] || []
puts "###RULECOUNT|#{r.size}"
r.each_with_index { |x,i| puts "RULE|#{i+1}|#{x}" }
puts

# ---------- DNS ----------
puts "###DNSSECTION"
puts((d["dns"] || {}).to_yaml)
puts

# ---------- 其它 ----------
puts "###SNIFFERSECTION"
puts((d["sniffer"] || {}).to_yaml)
puts
puts "###TUNSECTION"
puts((d["tun"] || {}).to_yaml)
puts
puts "###TOPVALUES"
%w[mixed-port port socks-port redir-port tproxy-port external-controller
   external-ui allow-lan bind-address lan-allowed-ips mode ipv6
   find-process-mode global-client-fingerprint unified-delay
   tcp-concurrent geodata-mode skip-auth-prefixes authentication].each do |k|
  puts "KEY|#{k}|#{(d[k] || "(未设置)").inspect}"
end
' "$CFG" 2>&1
echo

echo "############################################################"
echo "# 2. IPv6 泄漏面详查（决定要不要动、怎么动）"
echo "############################################################"
echo "--- network.lan 的 IPv6 分配 ---"
uci -q show network.lan 2>/dev/null | grep -iE 'ip6|delegate'
echo "  (无输出 = 未显式配置，可能依赖 odhcpd 默认行为)"
echo
echo "--- dhcp.lan 的 RA / DHCPv6 ---"
uci -q show dhcp.lan 2>/dev/null | grep -iE 'ra|dhcpv6|ndp|ra_management|ra_default'
echo
echo "--- 局域网接口是否在发 RA ---"
for f in /proc/sys/net/ipv6/conf/br-lan/accept_ra \
         /proc/sys/net/ipv6/conf/br-lan/autoconf \
         /proc/sys/net/ipv6/conf/br-lan/disable_ipv6; do
    [ -f "$f" ] && echo "  $(basename $(dirname $f))/$(basename $f) = $(cat $f)"
done
echo
echo "--- odhcpd / radvd 是否在跑（RA 实际发送者）---"
pgrep -a odhcpd 2>/dev/null | head -3
pgrep -a radvd 2>/dev/null | head -3
echo "  (无输出 = 无人发 RA)"
echo
echo "--- 全局 IPv6 地址清单 ---"
ip -6 addr show scope global 2>/dev/null | grep 'inet6' | sed 's/^/  /'
echo
echo "--- IPv6 默认路由（有无 IPv6 出口）---"
ip -6 route show default 2>/dev/null | sed 's/^/  /'
echo
echo "--- iptables/nft 是否拦 IPv6 转发 ---"
ip6tables -L FORWARD -n 2>/dev/null | head -8
echo
echo

echo "############################################################"
echo "# 3. 「区域绕过=大陆」注入了什么"
echo "############################################################"
echo "--- 相关 UCI ---"
uci -q show openclash 2>/dev/null | grep -iE 'chnr|china_route|bypass|lanonly'
echo
echo "--- chnr 规则文件是否已下载 ---"
ls -la /etc/openclash/rule_provider/ 2>/dev/null | head -20
find /etc/openclash -iname '*chnr*' -o -iname '*china*' 2>/dev/null | head -10
echo
echo "--- 实际生效配置里与「大陆绕过」相关的规则 ---"
grep -nE 'chnr|china|CHINA|clash.cn|ispip' "$CFG" 2>/dev/null | head -20
echo "  (无输出 = 大陆绕过不通过 rules 注入，可能是防火墙层实现)"
echo
echo

echo "############################################################"
echo "# 4. Tailscale 真实路由面（v1 的主路由表检查是假阴性）"
echo "############################################################"
echo "--- 策略路由规则（ip rule）---"
ip rule show 2>/dev/null | head -15
echo
echo "--- 100.64.0.0/10 在各路由表中的条目 ---"
for t in $(ip rule show 2>/dev/null | grep -oE 'lookup [0-9]+' | awk '{print $2}' | sort -u); do
    hit=$(ip route show table $t 2>/dev/null | grep '100\.6[4-9]\|100\.[7-9][0-9]\|100\.1[01][0-9]\|100\.12[0-7]')
    [ -n "$hit" ] && { echo "  table $t:"; echo "$hit" | sed 's/^/    /'; }
done
echo
echo "--- tailscale 网卡 ---"
ip addr show tailscale0 2>/dev/null | grep -E 'inet6? ' | sed 's/^/  /'
echo
echo "--- tailscaled 服务状态 ---"
/etc/init.d/tailscale status 2>/dev/null | head -5
echo
echo

echo "############################################################"
echo "# 5. 路由器上现有的覆写文件（确认是否原厂未改）"
echo "############################################################"
echo "--- /etc/openclash/custom/ 目录 ---"
ls -la /etc/openclash/custom/ 2>/dev/null
echo
echo "--- openclash_custom_overwrite.sh 全文 ---"
cat /etc/openclash/custom/openclash_custom_overwrite.sh 2>/dev/null
echo
echo "--- openclash_custom_rules.list 全文（休眠中）---"
cat /etc/openclash/custom/openclash_custom_rules.list 2>/dev/null
echo
echo "--- openclash_custom_rules_2.list 全文（休眠中）---"
cat /etc/openclash/custom/openclash_custom_rules_2.list 2>/dev/null
echo
echo

echo "############################################################"
echo "# 6. DNS 链路现状"
echo "############################################################"
echo "--- dnsmasq 正在监听的端口 ---"
netstat -lnup 2>/dev/null | grep -E 'dnsmasq|:53|:7874' | head -10
echo
echo "--- resolv.conf（引导 DNS）---"
cat /tmp/resolv.conf.d/resolv.conf.auto 2>/dev/null
echo
echo "--- 路由器自身能否直连国内 DoH（验证 DoH 可达性，不改任何东西）---"
echo "  doh.pub:"
curl -s -o /dev/null -w "    HTTP %{http_code}  耗时 %{time_total}s\n" \
     --max-time 8 -H 'accept: application/dns-message' \
     'https://doh.pub/dns-query?dns=AAABAAABAAAAAAAAB2V4YW1wbGUDY29tAAABAAE' 2>&1
echo "  alidns:"
curl -s -o /dev/null -w "    HTTP %{http_code}  耗时 %{time_total}s\n" \
     --max-time 8 -H 'accept: application/dns-message' \
     'https://dns.alidns.com/resolve?name=example.com&type=A' 2>&1
echo
echo "--- 路由器能否直连国际 DoH（决定国际 DoH 能不能用）---"
echo "  cloudflare DoH:"
curl -s -o /dev/null -w "    HTTP %{http_code}  耗时 %{time_total}s\n" \
     --max-time 8 'https://cloudflare-dns.com/dns-query?name=example.com&type=A' 2>&1
echo "  google DoH:"
curl -s -o /dev/null -w "    HTTP %{http_code}  耗时 %{time_total}s\n" \
     --max-time 8 'https://dns.google/resolve?name=example.com&type=A' 2>&1
echo
echo "############################################################"
echo "###PROBE_DONE###"
