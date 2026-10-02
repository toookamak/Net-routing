# OpenClash 路由器侧速查

> 写 `targets/openclash-*.sh` 之前先查本文。
> 标记约定：✅ = 已在本机实测验证 ｜ ⚠️ = 源码/官方文档推断，尚未实测 ｜ ❌ = 明确无效

---

## 〇、环境快照

| 项 | 值 | 来源 |
|---|---|---|
| 系统 | iStoreOS 24.10.7（build 2026060510） | ✅ |
| 内核 | Linux 6.6.141 aarch64 | ✅ |
| OpenClash | luci-app-openclash 0.47.156（2026-08-10 发布） | ✅ |
| mihomo | `Mihomo Meta alpha-ge183c58 linux arm64 with go1.26.5 Mon Aug 10 14:32:53 UTC 2026` | ✅ |
| 编译标签 | `with_gvisor` | ✅ |
| 实际运行二进制 | `/etc/openclash/clash -d /etc/openclash -f /etc/openclash/良心云.yaml` | ✅ |
| 依赖 | `dnsmasq-full 2.93-r1`、`tailscale 1.80.3-r1` | ✅ |
| LAN | `192.168.31.1/24` | ✅ |
| 上游 | WAN 经 `192.168.1.1`（二级路由 / 旁路由形态） | ✅ |
| 存储 | overlay 1.9G，已用 618M，可用 1.3G | ✅ |

### 内核版本号的含义

`alpha-ge183c58` 是 git-describe 串（tag `alpha` + commit `e183c58`），**不对应任何已发布版本号**，不要拿它去比对 mihomo 官方版本。
判断特性支持请看 `go1.26.5` + 构建日期 2026-08 —— 这是**远高于 v1.19.x 的新内核**，`#代理名` DNS 后缀语法、`respect-rules` 现代行为均可预期可用。
⚠️ 但「可预期」不等于「已验证」，真要用仍需实测（见第八节）。

### 端口（全部由 OpenClash 的 LuCI 接管，覆写脚本一律不碰）

| 用途 | 端口 | UCI 键 |
|---|---|---|
| DNS 监听 | 7874 | `openclash.config.dns_port` |
| redir | 7892 | `proxy_port` |
| tproxy | 7895 | `tproxy_port` |
| HTTP | 7890 | `http_port` |
| SOCKS5 | 7891 | `socks_port` |
| mixed | 7893 | `mixed_port` |
| 控制面板 | `0.0.0.0:9090` | — |

---

## 一、覆写执行链

```
/etc/init.d/openclash start_service()
      │
      ├─ overwrite_file()            读 INI 模块 → 生成 /tmp/yaml_overwrite.sh
      ├─ get_config() / config_choose() / do_run_mode()
      │
      ├─ 第3步 按顺序修改 YAML
      │    ├─ ① yml_change.sh          端口 / 模式 / TUN / DNS / Sniffer / 认证
      │    ├─ ② yml_rules_change.sh    规则注入、自定义规则、provider CDN 重写
      │    └─ ③ /tmp/yaml_overwrite.sh ← 由 INI 覆写模块编译而来
      │
      ├─ ④ /etc/openclash/custom/openclash_custom_overwrite.sh   ← 我们改这里，最后执行
      │
      └─ 启动 mihomo
```

✅ 「最后跑」这一点由原厂模板自述确认：
`# Add your custom overwrite scripts here, they will be take effict after the OpenClash own srcipts`

---

## 一之二、⚠️ 两套覆写系统，别搞混

OpenClash 同时存在两套完全不同的覆写机制，界面上挨得很近但行为差异很大。

| | **覆写模块（上传）** | **自定义覆写脚本（可编辑区）** |
|---|---|---|
| 位置 | `/etc/openclash/overwrite/*.txt`、`.conf` | `/etc/openclash/custom/openclash_custom_overwrite.sh` |
| 格式 | **INI 定义文件** | **shell + Ruby** |
| 怎么生效 | OpenClash 遍历 UCI `config_overwrite` 条目，**编译生成** `/tmp/yaml_overwrite.sh` | 直接由 `/etc/init.d/openclash` 执行 |
| 文件名要求 | 界面上传控件**只接受 `.txt` / `.conf`** | 固定名 `openclash_custom_overwrite.sh` |
| 适合 | 改端口、改 DNS 开关这类标准项的声明式覆盖 | 任意 Ruby 改写（替换策略组、整段替换 rules、改 DNS 段） |

**源码依据**（`luasrc/controller/openclash.lua` 的 `action_upload_overwrite`）：

```lua
local overwrite_dir = "/etc/openclash/overwrite/"
local target_path = overwrite_dir .. filename
...
uci:add("openclash", "config_overwrite")
uci:set("openclash", sid, "name", section_name)
uci:set("openclash", sid, "type", "file")
```

> ⚠️ **覆写模块 ≠ 只能改端口开关。**
> `[YAML]` 块提供了一套完整的合并算子（官方 `overwrite/default` 参考文件里有速查表）：
>
> | 写法 | 作用 |
> |---|---|
> | `key` | 默认合并，Hash 递归合并，其他类型直接覆盖 |
> | `key!` | **强制覆盖整个值** |
> | `key+` / `+key` | 数组后置 / 前置 |
> | `key-` | 数组差集删除 / 删键（值为空或 `~`） |
> | `key*` | 按 `where` / `set` 批量条件更新 |
>
> 官方示例里就有 `rules!:` 替换整条规则链。所以**本项目改用覆写模块实现**，
> 不用自定义覆写脚本 —— 理由见 `targets/openclash-override-1002.md` 第一节。
>
> `action_overwrite_file_list` 会把 `/etc/openclash/custom/openclash_custom_overwrite.sh`
> 和 `/etc/openclash/overwrite/` 里的文件混在一个列表里展示，界面上看着像同一个功能。
> 两个目录的**落点和格式完全不同**。

**两种覆写方式怎么选**

| 需求 | 用哪个 |
|---|---|
| 替换整条 rules / 全部策略组、合并 rule-providers、改 dns 段 | **覆写模块 `[YAML]` 块** ← 本项目 |
| 在既有 `rules` 数组里插几条规则、临时改端口 | 覆写模块（够用）或自定义覆写脚本 |
| 任意 Ruby 逻辑（跨段条件判断、动态计算） | 自定义覆写脚本 |

### 怎么把文件送进路由器

**覆写模块**（本项目采用）：LuCI → 覆写模块 → 上传 `.conf` → 打开「启用」→ 重启。

编译结果肉眼可读，这是它相对自定义脚本最大的优势：

```sh
cat /tmp/yaml_overwrite.sh
```

**自定义覆写脚本**：覆写模块页面里编辑 `openclash_custom_overwrite.sh`，或走管道：

```powershell
ssh root@192.168.31.1 "cp /etc/openclash/custom/openclash_custom_overwrite.sh /etc/openclash/custom/openclash_custom_overwrite.sh.stock"
Get-Content "F:\Git\Net-routing\targets\openclash-override-1002.sh" -Raw |
  ssh root@192.168.31.1 "cat > /etc/openclash/custom/openclash_custom_overwrite.sh"
```

⚠️ PowerShell 不支持 `ssh ... < 文件` 的写法（`<` 是本地重定向，不作用于远程命令），
必须 `Get-Content -Raw |`。

---

## 二、`ruby.sh` 机制（读源码得出）

源码：`luci-app-openclash/root/usr/share/openclash/ruby.sh`

### 两种执行模式

`openclash_custom_overwrite()` 遍历 `/proc/PID/cmdline` 向上找父进程名：

| 父进程 | `OVERWRITE_PARENT` | 行为 |
|---|---|---|
| `openclash_custom_overwrite.sh` | `custom` | Ruby 片段追加到 `/tmp/yaml_openclash_ruby_parse` |
| `yaml_overwrite.sh` | `yaml_overwrite` | Ruby 片段追加到 `/tmp/yaml_openclash_ruby_parts/$sid` |
| 都不是 | — | 直接 `ruby -e` 立即执行 |

**入队模式下 `write_ruby_part` 只做赋值，不写 `YAML.dump`** —— 落盘由 `YAML.rb` 统一负责。

### ⚠️ 陷阱一：失败完全静默

```sh
run_ruby_part() {
  ruby -ryaml -rYAML -I "/usr/share/openclash" -E UTF-8 -e "begin $part; rescue Exception => e;
    YAML.LOG_ERROR('Set Custom Overwrite Script Failed,【%s】' % [e.message]); end" 2>/dev/null
}
```

`2>/dev/null` 吞掉 stderr，异常只经 `YAML.LOG_ERROR` 写进 **`/tmp/openclash.log`**。
**脚本写坏了屏幕上不会有任何输出。改完必须查日志。**

### ⚠️ 陷阱二：辅助函数表达力不足

`ruby.sh` 提供的全部函数：
`ruby_read` / `ruby_read_hash` / `ruby_read_hash_arr` / `ruby_edit` / `ruby_cover` /
`ruby_merge` / `ruby_uniq` / `ruby_merge_hash` / `ruby_arr_add_file` /
`ruby_arr_head_add_file` / `ruby_arr_insert` / `ruby_arr_insert_hash` /
`ruby_arr_insert_arr` / `ruby_delete` / `ruby_map_edit` / `ruby_arr_edit`

**没有任何一个是「替换整个数组」或「合并大块 hash」。**
`ruby_merge_hash` 传 46 个 rule-provider 会变成一条几千字符的命令行，不可读、不可 diff、出错无法定位。

### 结论：不要用 `ruby_*` 辅助函数

用**一个自包含 Ruby 块**：`load → 改 → 校验 → dump`。
这正是原厂模板 "Ruby Script Demo" 的写法：

```sh
ruby -ryaml -rYAML -I "/usr/share/openclash" -E UTF-8 -e "
   Value = YAML.load_file('$CONFIG_FILE');
   ...改动...
   File.open('$CONFIG_FILE','w') {|f| YAML.dump(Value, f)};
"
```

`-rYAML` + `-I /usr/share/openclash` 提供 `YAML.LOG_ERROR`，用它往 `/tmp/openclash.log` 记日志。

---

## 三、原生声明式覆写文件（优先于脚本）

LuCI 页面：服务 → OpenClash → 覆写设置
源码：`luci-app-openclash/luasrc/model/cbi/openclash/config-overwrite.lua`

### 文件映射表

| 文件 | UCI 开关 | 当前值 | 作用 |
|---|---|---|---|
| `openclash_custom_fake_filter.list` | `custom_fakeip_filter` | `0` | fake-ip-filter，一行一个域名 |
| `openclash_custom_domain_dns_policy.list` | `custom_name_policy` | `0` | nameserver-policy |
| `openclash_custom_proxy_server_dns_policy.list` | `custom_proxy_server_policy` | — | 节点域名解析策略 |
| `openclash_custom_fallback_filter.yaml` | `custom_fallback_filter` | `0` | fallback-filter（YAML，不是纯列表） |
| `openclash_custom_hosts.list` | `custom_host` | `0` | hosts |
| `openclash_custom_sniffer.yaml` | `enable_meta_sniffer_custom` | — | sniffer 细节 |
| `openclash_custom_rules.list` | `enable_custom_clash_rules` | `0` | 规则插到**最顶** |
| `openclash_custom_rules_2.list` | `enable_custom_clash_rules` | `0` | 规则插到 **MATCH 之前** |
| `openclash_custom_overwrite.sh` | 无开关，始终执行 | 原厂 | 任意 Ruby 改写 |

`custom_fakeip_filter` 另有 `custom_fakeip_filter_mode`：`blacklist`（默认）/ `whitelist` / `rule`。

### 其它值得注意的 LuCI 开关

| UCI 键 | 默认 | 说明 |
|---|---|---|
| `enable_respect_rules` | `0` | **DNS 连接是否跟随规则** —— 启用国际 DoH 的前提 |
| `enable_custom_dns` | `0` | 用 LuCI 的 DNS 服务器表作为上游 |
| `enable_meta_sniffer` | `1` | 官方描述：*"Sniffer Will Prevent Domain Name Proxy and DNS Hijack Failure"* |
| `enable_meta_sniffer_pure_ip` | `1` | 强制嗅探纯 IP 连接 |
| `github_address_mod` | `0` | **GitHub 地址走 CDN —— 46 个规则集大半来自 raw.githubusercontent.com，建议开** |
| `find_process_mode` | `0` | 官方描述：*"**Only Works on Routerself**"* |
| `urltest_interval_mod` | `0` | 全局改 url-test 间隔 |
| `tolerance` | `0` | url-test 组切换容差 |
| `log_level` | `0` | 内核日志级别，排障时调 `debug` |

`@dns_servers` 是 UCI 表，支持 `udp / tcp / tls / https / quic` 五种类型，
有 `group`（`nameserver` / `fallback` / `default-nameserver`）和 `enabled` 字段。

### ❌ 三选一：规则注入只能用一种机制

`openclash_custom_rules.list`（插顶）+ `_2.list`（插 MATCH 前）+ 覆写模块的 `rules!:`
**三者同时启用会产生未定义的插入顺序。**

本项目的决定：**只用覆写模块的 `rules!:` 整体替换 `rules`**，另两个保持关闭
（`enable_custom_clash_rules = 0`）。`openclash_custom_overwrite.sh` 保持**原厂模板不动**
（实测它只有 6 条有效语句：source 三个库、打日志、`exit 0`，对配置零影响）。

好处：规则链是确定的一整段，可完整 review；坏处：不能再用 LuCI 界面临时加规则。

---

## 四、不能碰的东西

| 对象 | 原因 |
|---|---|
| `proxies` | 订阅生成的节点，含服务器与密码 |
| 任何端口（7874/7892/7895/7890/7891/7893/9090） | OpenClash 生成防火墙规则时按这些端口配对，改了会失配 |
| `dns.listen` | 必须是 `0.0.0.0:7874`；dnsmasq 已配好转发到它。**写错 = 全局域网 DNS 瘫痪** |
| `authentication` | 面板密钥，由 OpenClash 管理 |
| `rule-providers` 里的 `oc-cn-domain` | OpenClash 注入的大陆域名集（556KB mrs），与大陆绕过联动 |
| `openclash_custom_firewall_rules.sh` | 防火墙层，出错直接断网 |
| `enable_custom_clash_rules` | 见上「三选一」 |

---

## 五、已确认的坑

### 1. IPv6 泄露（🔴 未修，安全问题）

```
network.lan.ip6assign='60'          LAN 分配 IPv6 前缀
dhcp.lan.ra='server'                发 RA
dhcp.lan.dhcpv6='server'
odhcpd 运行中 (PID 4781)            RA 的实际发送者
br-lan/disable_ipv6 = 0
default via fe80::1 dev eth0        有 IPv6 出口
ip6tables FORWARD policy ACCEPT     防火墙放行
全局地址 2408:824e:d21:dde0:...     中国电信公网 IPv6
```

而 mihomo 侧 `dns.ipv6: false`、OpenClash `ipv6_enable=0` → **IPv6 流量完全不过代理**。
客户端拿到 RA 下发的 IPv6 后直连出门，AI 服务看到的是真实家庭 IPv6。

**FlClash 的三层封堵（`ipv6:false` + `dns.ipv6:false` + `tun.inet6-route-address:["2000::/3"]`）在路由器上不适用**，
因为没有 TUN 接管（见坑 3）。只能走系统层，且**必须停 RA**，只关 sysctl 没用（客户端手里已分配的地址还在）。

### 2. 现有 DNS 段的 fallback 是坏的

```yaml
respect-rules: false                                    # ← DNS 不走规则
fallback: [1.1.1.1, 8.8.8.8]                            # ← 大陆直连必然被污染/超时
fallback-filter: { geosite: [gfw], geoip: true, geoip-code: CN, ... }
```

`fallback-filter` 配了 `geosite:gfw`，所以 gfw 域名的查询全部撞在这个不可达的 fallback 上。
形状与 FlClash 那个坑相同，但**在本机可修**（见第八节实测结论）。

### 3. TUN 段存在但不接管

```yaml
tun: { enable: true, stack: system, device: utun,
       auto-route: false, auto-detect-interface: false, dns-hijack: [127.0.0.1:53] }
```

OpenClash 的「混合」模式：TUN 设备存在但 `auto-route: false`，流量靠 iptables 接管。
所以 `endpoint-independent-nat` 对 UDP 有意义，但 `inet6-route-address` 那套用不上。

### 4. `fake-ip-filter` 只有一条

```yaml
fake-ip-filter:
  - rule-set:oc-cn-domain
```

`.lan` / `.local` / 路由器主机名 / `+.ts.net`（Tailscale MagicDNS）全部拿假 IP
→ 局域网发现、NAS 访问、tailnet 按名字访问都可能异常。

### 5. Tailscale 路由在 policy routing，不在主路由表

```
ip rule:  5270: from all lookup 52      ← 优先级高于 main(32766)
table 52: 12 条 100.x dev tailscale0
tailscale0: 100.101.14.109/32, fd7a:115c:a1e0::9f39:e6d/128
tailscaled: running，tailnet 10 台设备
```

`ip route show table main | grep 100.64` 查不到东西 —— **这是假阴性，不代表没占用**。
flclash 里的 `IP-CIDR,100.64.0.0/10,no-resolve` 是刚需（本机 tailnet 有 NAS 在跑大流量）。
订阅自己的规则第 510 条也有 `IP-CIDR,100.64.0.0/10,DIRECT`。

### 6. 大陆绕过不走 rules，在 ipset/防火墙层

```
/etc/openclash/china_ip_route.ipset
/etc/openclash/china_ip6_route.ipset
/etc/openclash/rule_provider/oc-cn-domain.mrs   (556KB)
```
✅ 与我们的规则链**零冲突**。

### 7. 进程规则对 LAN 客户端无效

官方源码描述：`find_process_mode` — *"Only Works on Routerself"*。
透明代理下连接由客户端进程持有，mihomo 只能查本机进程。
→ `applications`（`PROCESS-NAME`）规则集在路由器上必须砍掉。

### 8. 节点分类可交给 mihomo 原生 filter（✅ 语法已实测通过）

`proxy-groups` 每个组都支持（官方文档 + 本机 `-t` 校验双重确认）：

```yaml
- name: "🇭🇰 香港"
  type: url-test
  include-all-proxies: true        # 拉入订阅全部节点
  filter: "香港|HK|Hong Kong|🇭🇰"    # 正则包含
  empty-fallback: DIRECT            # 组空时的回退出口
  default-selected / icon / hidden / lazy / interval / tolerance
```

⚠️ **限制：`filter` / `exclude-filter` 只对 `use:`（proxy-providers）和
`include-all-proxies` / `include-all-providers` 生效，对显式 `proxies:` 列表无效。**
→ 组必须走 `include-all-proxies: true`，不能写死节点名。

→ **副产品（架构基石）：整个 `proxy-groups` 段变成与订阅无关的静态文档**，见第六节。

→ **对比 flclash：`classifyNodes()` 那 180 行 JS 在路由器上完全不需要重写。**
mihomo 自己在运行时做正则分类，而且是纯 YAML 声明。

### 9. ✅ 内核校验严格度（已实测，`clash_meta -t`）

测试配置 `/tmp/nr-verify-*/test-groups.yaml`，12 个假节点 + 10 个组 + 3 个陷阱项，
结果：**只有 `RULE-SET,NoSuchProvider` 报错，其余全部通过。**

| 陷阱项 | 结果 |
|---|---|
| `include-all-proxies: true` | ✅ 接受 |
| `filter` / `exclude-filter` | ✅ 接受 |
| `empty-fallback: DIRECT` | ✅ 接受 |
| T8 空组（有 `empty-fallback`） | ✅ 通过 |
| **T9 空组（无 `empty-fallback`）** | ✅ **也通过** |
| `RULE-SET,NoSuchProvider`（不存在的 provider） | ❌ **整份配置加载失败** |

**结论一：空组无害。** 内核容忍空策略组，`empty-fallback` **不是硬性要求**。
但仍然建议给 —— 官方文档推荐，且能让「该地区组为空」这件事在面板上有明确回退出口，
而不是静默变成一个点不动的组。

**结论二：引用不存在的 rule-provider 是硬失败，不是静默空载。**

```
level=error msg="rules[1] [RULE-SET,NoSuchProvider,DIRECT] error: rule set [NoSuchProvider] not found"
configuration file ... test failed
```

这比项目文档里记的更严重。`docs/design.md` 已知「规则指向不存在的**组** → 整份配置加载失败」，
现在补上第二类：**规则指向不存在的 **rule-provider** 同样让整份配置加载失败**。
`proxies`/`proxy-groups` 字段声明错是**静默空载**，而 `RULE-SET` 引用缺失是**硬失败**——两种表现完全不同，别混为一谈。

→ **渲染器必须做交叉引用校验**：每条 `RULE-SET,X` 的 `X` 必须在 `rule-providers` 里，
每条规则的 target 必须在 `proxy-groups` 里。见第七节「校验门」。

### 10. ✅ 正则命中率（已实测，51 个真实节点）

| 模式 | 命中 | 备注 |
|---|---|---|
| 香港 / 新加坡 / 日本 / 美国 | 5 / 12 / 15 / 12 | 现状正则，全部有效 |
| 英国 `英国\|UK\|United Kingdom\|伦敦\|🇬🇧` | 4 | 建议新增 |
| 台湾 `台湾\|台灣\|Taiwan` | 1 | 建议新增，**不要加 `🇹🇼`**（本机节点用 🇨🇳） |
| 韩国 / 德国 | 0 | 建议**保持注释**，避免面板上常驻空组 |
| 通知（现状 strict） | 2 | ✅ 零误伤，49 个真实节点无一被误判 |
| 家宽 | 0 | 该订阅无家宽节点 |
| **低倍率（现状 `低倍率\|lowrate\|低-rate\|倍率`）** | **0** | ❌ **完全失效** |
| 低倍率（扩充 `…\|0\.\d+x\|[0-9]+倍`） | 18 | ✅ |
| 流媒体（`流媒体\|解锁\|Netflix\|Disney\|IPLC\|IEPL`） | 18 | ✅ 建议新增特性 |

### 11. ⭐ 地区组禁用 `exclude-filter`（实测决定）

交叉风险表——「地区 × 排除策略」的剩余节点数：

| 地区 | 不排除 | 排流媒体 | 排低倍率 | 排两者 |
|---|---|---|---|---|
| 香港 | 5 | 5 | 5 | 5 |
| 新加坡 | 12 | 8 | 12 | 8 |
| 日本 | 15 | 11 | 13 | 9 |
| **美国** | 12 | 5 | **0** | **0** |
| **英国** | 4 | 2 | **0** | **0** |
| **台湾** | 1 | **0** | 1 | **0** |

**排低倍率会让美国、英国整组消失；排流媒体会让台湾消失。**

原因：`0.1x` / `0.01x` 标注在**这个订阅里是主流线路的常态**（美国 12 个里 10 个带倍率），
不是 flclash 设计假设的那种「另一类特供线路」。

→ **地区组只写 `filter`，一律不写 `exclude-filter`。**
`exclude-filter` 只用在「🌍 全部节点」上剔通知节点，以及特性组自身收窄时使用。

> ⚠️ 这条与 `flclash-override-1001.js` 的设计**有意不同**。
> 那边的「家宽/低倍率不进地区组」是继承自原单文件脚本的既有行为（见 `docs/design.md` 第七节已知问题 2），
> 在本订阅上会导致 3 个地区组消失。两端产物允许在这一点上分叉，各自求最优。

### 12. ⭐⭐ `[YAML]` 块里带 `|` 的行会被**静默删除**（2026-10-02 定位）

**这是本机最隐蔽的一个坑，日志无任何报错。**

现象：22 个策略组都在，但 `filter` / `exclude-filter` 键**凭空消失**，
地区组退化成「全部节点」，面板上 `35/51`，🇭🇰🇯🇵🇺🇸🇬🇧🇹🇼 六个地区组选中的都是同一个新加坡节点。
**「选香港」会连到新加坡。**

根因在 **init.d 拼 YAML 块那一行 shell**（`/etc/init.d/openclash` 的 `overwrite_file()`）：

```sh
yaml_content="${yaml_content}$(eval "echo \"$line\"")"$'\n'
```

行里的 `"` 提前闭合 shell 引号 → 后面的 `|` 变成**管道运算符** →
`echo` 输出被灌进管道 → 命令替换拿到**空串** → **整行蒸发**。路由器上直接复现：

```sh
line='    filter: "HK|Hong Kong|abc"'
eval "echo \"$line\""        # → 空
```

对照数据：整个 `[YAML]` 块含 `|` 的非注释行**正好 13 行**，
也正好是 13 个 `filter`/`exclude-filter` 键消失，其它键一个没少。

**规避**：值一律**单引号**（shell 双引号串里是字面量，能原样通过），
且**一个组只给一个正则**。单正则方案与实测命中见 `targets/openclash-override-1002.md` 第 〇之前 节。

> ⚠️ **不要用 GitHub `dev` 分支的 `YAML.rb` 推断线上行为。** `dev` 已重写为
> `overwrite_run` + fragment 文件，0.47.156 没打包进去：
> ```sh
> grep -n 'def self\.' /usr/share/openclash/YAML.rb   # 线上 24 个方法，没有 overwrite_run
> ```
> **合并层是 Psych 完整解析（`|` 安全）没错，但丢行发生在更早的抽取层。**

### 13. `/tmp/openclash.log` 会被 watchdog 清空

出现过 `[Watchdog] Log Size Limit, Clean Up All Log Records`，之后文件里只剩流量日志，
启动阶段的几十行全没了。**「日志里搜不到 X」不能推出「X 没执行」** ——
2026-10-02 因此误判过一次「模块没被处理」。

同理 `/tmp/yaml_overwrite.sh` 用完即删（`rm -rf /tmp/yaml_*`），
事后看不到编译产物。**要抓启动过程必须重启前先挂 `tail -F`。**

### 14. `clash_meta -t` 在本机会误报失败

```
path is not subpath of home directory or SAFE_PATHS: /usr/share/openclash/ui
allowed paths: [/etc/openclash]
```

OpenClash 写的 `external-ui: /usr/share/openclash/ui` 在 home 目录之外。
**连线上那份配置自己都过不了 `-t`**，极易被误判成「我改坏了」。

正确用法：

```sh
SAFE_PATHS=/etc/openclash:/usr/share/openclash \
  /etc/openclash/core/clash_meta -t -d /etc/openclash -f /etc/openclash/良心云.yaml
```

### 15. 覆写模块是从 GitHub 仓库拉取的 —— `git push` = 一次生产部署

本模块注册为 `type='http'`，URL 指向仓库里的本文件，并自带 `0 2 * * *` 的定时任务
（`/etc/crontabs/root` 可见）。**main 上这个文件的内容每天凌晨 2 点被推到路由器。**

2026-10-02 该文件在仓库里 90 分钟内换了 6 个版本，这种节奏配自动拉取极易出事故。
**已处置**：关掉自动更新，改为人工确认后手动上传 + 重启。

### 16. `behavior: classical` 配 `+.域名` 简写 = 整份规则集空载（已修）

`Reject_domainset` / `CDN_domainset` / `Download_domainset` 三个上游用 `+.域名` 简写
（Surge 风格，零条带逗号），声明成 `behavior: classical` → mihomo 逐行解析失败 →
**10.9 万 + 2.6 千 + 6 百条规则全部被丢弃**，日志刷屏十万条
`parse classical rule ... missing subsequent parameters`。

`+.域名` 是**合法的** mihomo 写法，但只对 `behavior: domain` 生效
（`component/trie/domain.go` 的 `ValidAndSplitDomain` 明确接受）。

**已改为 `behavior: domain`，实测 `ruleCount` 恢复 109004 / 2633 / 610。**

自查（比日志可靠，直接问内核要条数）：

```sh
S=$(ruby -ryaml -e 'print YAML.load_file("/etc/openclash/良心云.yaml")["secret"].to_s')
curl -s -H "Authorization: Bearer $S" http://127.0.0.1:9090/providers/rules > /tmp/p.json
ruby -ryaml -e 'j=YAML.load(File.read("/tmp/p.json")); (j["providers"]||{}).each{|k,v| puts format("  %-22s %-9s %s", k, v["behavior"], v["ruleCount"]) }'
```

---

## 六、架构：单文件覆写 + 静态声明

因为策略组改用 `include-all-proxies` + `filter` 之后，
**本项目贡献给路由器的所有内容都不含任何节点名**：

| 段 | 是否依赖订阅节点名 |
|---|---|
| `rules` | ❌ 不依赖 |
| `rule-providers` | ❌ 不依赖 |
| `proxy-groups`（filter 式） | ❌ 不依赖 |
| 基础项 `unified-delay` / `tcp-concurrent` | ❌ 不依赖 |
| `proxies` | ✅ 依赖 —— 但我们不碰 |

于是全部内容可以是**一份静态声明**，由覆写模块的 INI 文件承载：

```
PC 侧：rules/*.yaml ──(渲染)──▶ targets/openclash-override-1002.conf
                                                    │
                                      上传到覆写模块（唯一一个部署物）
                                                    ↓
路由器侧：OpenClash 编译成 /tmp/yaml_overwrite.sh → 合并进运行配置
```

**路由器侧不需要写任何脚本。** 合并由 OpenClash 自己的 `YAML.overwrite()` 完成
（Psych 完整解析），我们只提供数据。

> 历史上这里规划过「PC 侧渲染 `openclash-routes.yaml` + 路由器侧一个合并 `.sh`」
> 的两文件方案，**已废弃**：那个 `.sh` 上线后导致分组全部消失、网络不可用
> （2026-10-02 事故）。**当前只有一个部署物。**

### 路由器上没有 JS 运行时

- OpenWrt 不带 Node.js，也不带任何 JS 引擎
- OpenClash 的安装依赖里本来就有 `ruby` + `ruby-yaml`（`/etc/openclash/ruby.sh`、`YAML.rb`）
- 为覆写脚本塞 JS 解释器是本末倒置
- **需要 JS 表达力的部分（分类、建组、渲染）应该放在 PC 侧做**，产出静态 YAML 推给路由器

---

## 七、安全与回滚

### 风险分级

| 故障 | 后果 | 是否可救 |
|---|---|---|
| Ruby 报错 / YAML 写坏 | mihomo 起不来，**无代理** | ✅ 可救：LuCI 和 SSH 走局域网，不依赖代理 |
| `dns.listen` 写错 | 全局域网 DNS 瘫痪（**含 LuCI 域名访问**） | ✅ 可救：LuCI 用 IP 访问，dnsmasq 重启即可 |
| 动 `openclash_custom_firewall_rules.sh` | 防火墙层面断网 | ⚠️ 高危，本项目不碰 |
| 规则写错（分流去向不对） | 部分站点走错出口，不影响连通性 | ✅ 改配置重载 |

**关键认知：mihomo 挂掉 ≠ 路由器挂掉。** LuCI、SSH、dnsmasq 都不依赖代理进程。
但——**AI 访问依赖代理**。所以下面的回滚必须能在「代理已死」的前提下执行。

### 铁律

1. **绝不在代理失效时依赖 AI 救场。** 手上永远有一条不依赖代理的回滚路径。
2. 改配置前 `uci export network > /tmp/network.bak`。
3. 改覆写前 `cp openclash_custom_overwrite.sh openclash_custom_overwrite.sh.bak`。
4. 改完查 `/tmp/openclash.log`（Ruby's `2>/dev/null` 让失败完全静默）。
5. 一次只改一层（先 rules，再 groups，再 DNS），不要合并上线。

### ⭐ 校验门（`clash_meta -t`，本轮实测可用）

内核自带离线配置校验：

```
-t    test configuration and exit
```

**这是「写坏就断网」的结构性解法 —— 不靠小心，靠机制。**
把校验写进 `openclash_custom_overwrite.sh` 的最后一步：

```sh
# 1. 改之前先备份
cp "$CONFIG_FILE" "$CONFIG_FILE.nr-bak"

# 2. 应用合并（Ruby 块，见第六节）

# 3. 离线校验，不通过就自动回滚
if /etc/openclash/core/clash_meta -t -d /etc/openclash -f "$CONFIG_FILE" >/tmp/nr-validate.log 2>&1; then
    rm -f "$CONFIG_FILE.nr-bak"
else
    cp "$CONFIG_FILE.nr-bak" "$CONFIG_FILE"
    echo "$(date '+%F %T') [net-routing] 校验失败，已回滚" >> /tmp/openclash.log
    cat /tmp/nr-validate.log >> /tmp/openclash.log
    exit 1
fi
```

**这样 OpenClash 启动 mihomo 时拿到的永远是能通过 `-t` 的配置。**
配置写坏的后果从「断网」降级为「本次覆写被静默跳过，网络照旧」。

⚠️ 校验路径必须用 `-d /etc/openclash`（home 目录），否则找不到已下载的 geo 库和
`rule_provider/` 下的 mrs 文件，会误报失败。

### PC 侧预校验（推送前就拦住）

`-t` 只能拦住语法和引用完整性，拦不住「规则顺序写反」这类语义错误。
PC 侧渲染完再做一次交叉引用检查：

- 每条 `RULE-SET,X` 的 `X` 存在于 `rule-providers` —— **否则整份配置加载失败**
- 每条规则的 target 存在于 `proxy-groups`
- 最后两条必须是 `GEOIP,CN` 和 `MATCH`
- `GEOIP,CN` / `MATCH` 之后没有任何规则

### 回滚路径（均不依赖代理）

```sh
# 1. 查覆写有没有报错
grep -iE 'error|fail|覆盖' /tmp/openclash.log | tail -20

# 2. 恢复覆写脚本
cp /etc/openclash/custom/openclash_custom_overwrite.sh.bak \
   /etc/openclash/custom/openclash_custom_overwrite.sh

# 3. 重启 OpenClash
/etc/init.d/openclash restart
```

**若 LuCI 域名打不开**：用 IP 访问 `http://192.168.31.1`，
或 SSH 上去 `kill $(pgrep -f 'clash')` 让内核退出，再修配置。

### 手机蜂窝网络是最后一道保险

本项目的 AI 通道走 OpenClash。覆写一旦写坏，AI 会失联。
**动手前先确认手机能连蜂窝数据** —— 那是唯一不经过这台路由器的 AI 通道。

---

## 八、待验证事项

| # | 事项 | 怎么验 |
|---|---|---|
| 1 | `enable_respect_rules=1` 后国际 DoH 是否真走代理 | 改完看 `dns.google` 解析结果与出口 IP |
| 2 | `custom_domain_dns_policy.list` 是否支持 `geosite:` 语法 | ⚠️ 该文件描述是「一行一个域名」，可能只支持字面域名 |
| 3 | `custom_fakeip_filter_mode: rule` 模式的行为 | 官方只给了三态描述，未说明 `rule` 具体语义 |
| 4 | 覆写脚本与 `yml_rules_change.sh` 的确切先后 | 保持自定义规则关闭即可绕过 |

**已在本轮验证、从本节移出**：

| 原待验证项 | 结论 |
|---|---|
| 内核是否有配置测试开关 | ✅ **有**，`-t test configuration and exit` |
| `filter` / `empty-fallback` 语法是否被本内核接受 | ✅ 全部接受（见第五节 9） |
| `rules/*.yaml` 正则能否命中真实节点 | ✅ 见第五节 10、11 |
| `filter` 键丢失的根因 | ✅ **init.d 的 `eval` 抽取**，见第五节 12 |
| 覆写模块实际跑的是哪份代码 | ✅ **0.47.156 ≠ GitHub `dev`**，见第五节 12 |
| `clash_meta -t` 在本机为何误报 | ✅ 缺 `SAFE_PATHS`，见第五节 14 |

### 已验证的关键事实：国际 DoH 在本机可达

```
doh.pub:        HTTP 200  0.189s
alidns:         HTTP 200  0.175s
cloudflare DoH: HTTP 400  0.506s   ← 400 是缺 accept 头，但 TLS 握手完成、服务器已应答
google DoH:     HTTP 200  0.317s   ← 200，正文正常
```

`dns.google` 317ms 返回 200 —— 从大陆直连不可能是这个结果，
说明**路由器自身流量确实走代理，DNS 送得进隧道**。

⚠️ 结论边界：这是**路由器自身 curl** 的结果。LAN 客户端经 dnsmasq → mihomo 的路径
是否同样成立，仍需在开启 `enable_respect_rules` 后实测。

> 📌 这条推翻了 FlClash 场景的结论。「mihomo 无法把 DNS 送进代理」是 **FlClash 客户端**的限制，
> 不是 mihomo 的通病。详见 Agent Memory 对应条目。

---

## 九、常用排查命令

```sh
# 实际加载的配置文件（从进程反查，比猜 UCI 键名可靠）
tr '\0' ' ' < /proc/$(pgrep -f 'clash'|head -1)/cmdline

# 内核版本
/etc/openclash/core/clash_meta -v

# 覆写执行日志（Ruby 失败只写这里）
grep -iE 'error|fail' /tmp/openclash.log | tail -20

# 最终产物（与上面 cmdline 的 -f 路径一致）
vi /etc/openclash/良心云.yaml

# 节点名 / 规则链 / DNS 段
ruby -ryaml -e 'd=YAML.load_file(ARGV[0]); puts (d["proxies"]||[]).map{|x| x["name"]}' /etc/openclash/良心云.yaml
ruby -ryaml -e 'd=YAML.load_file(ARGV[0]); (d["rules"]||[]).each_with_index{|r,i| puts "#{i+1}|#{r}"}' /etc/openclash/良心云.yaml

# IPv6 泄漏面
uci show network.lan | grep -i ip6
uci show dhcp.lan | grep -iE 'ra|dhcpv6'
ip -6 addr show scope global
ip6tables -L FORWARD -n

# Tailscale 真实路由（主表查不到是假阴性）
ip rule show
ip route show table 52
```

### 「覆写到底生成了什么」这一组（2026-10-02 新增）

```sh
# ① 线上实际在跑的是哪份 OpenClash 代码（别拿 GitHub dev 分支推断）
grep -n 'def self\.' /usr/share/openclash/YAML.rb
grep -n 'yaml_content=' /etc/init.d/openclash

# ② 覆写模块有没有被处理（要在重启后立刻看，日志会被 watchdog 清空）
grep -E 'Processing Overwrite Module|Load YAML Override Block' /tmp/openclash.log

# ③ 策略组的 filter 有没有被吃掉（本次事故的直接验入口）
ruby -ryaml -e 'd=YAML.load_file(ARGV[0]);
  (d["proxy-groups"]||[]).each{|g|
    v=g["filter"]||g["exclude-filter"]
    puts format("  %-16s %s", g["name"].to_s, v ? v : "（无筛选 ← 不对）")}' /etc/openclash/良心云.yaml

# ④ 规则集实际载入条数（比日志可靠，直接问内核）
S=$(ruby -ryaml -e 'print YAML.load_file("/etc/openclash/良心云.yaml")["secret"].to_s')
curl -s -H "Authorization: Bearer $S" http://127.0.0.1:9090/providers/rules > /tmp/p.json
ruby -ryaml -e 'j=YAML.load(File.read("/tmp/p.json"));
  (j["providers"]||{}).each{|k,v| puts format("  %-22s %-9s %s", k, v["behavior"], v["ruleCount"])}'

# ⑤ 离线校验（两个参数都不能省，见第五节 14）
SAFE_PATHS=/etc/openclash:/usr/share/openclash \
  /etc/openclash/core/clash_meta -t -d /etc/openclash -f /etc/openclash/良心云.yaml

# ⑥ 部署的是不是仓库里那一版（自动更新已关，靠这个比对）
md5sum /etc/openclash/overwrite/openclash-override-1002.conf
uci show openclash | grep -A6 'config_overwrite\[1\]'
```

---

## 十、命名与文件约定

| 路径 | 用途 |
|---|---|
| `rules/*.yaml` | 唯一事实来源，两端共用，**路由器版不改动其结构** |
| `targets/flclash-override-1001.js` | FlClash 产物（已有） |
| `targets/openclash-override-1002.conf` | **路由器产物（唯一部署物）**，上传到覆写模块 |
| `targets/openclash-override-1002.md` | 上述产物的配套说明（改产物前先读） |
| `/etc/openclash/overwrite/openclash-override-1002.conf` | 路由器上的实际位置（下载缓存 / 手动上传） |
| `/etc/openclash/custom/openclash_custom_*.list` | OpenClash 原生声明式清单（本项目不用） |
