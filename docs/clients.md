# 客户端环境

本文件记录本项目**面向哪些客户端**，以及各客户端在规则、覆写与 DNS 上的实际差异。

写规则、改产物、排查故障前，先确认「这条结论在哪个客户端成立」。
本项目实测发现 **FlClash 与 OpenClash 在 DNS 上的行为结论相反、在覆写执行顺序上恰好相反** ——
直接套用会同时踩到两个坑。

---

## 一、客户端清单

| 客户端 | 项目地址 | 使用场景 | 本项目产物 |
|---|---|---|---|
| **OpenClash** | <https://github.com/vernesong/OpenClash/tree/master> | 路由器（OpenWrt） | ✅ `targets/openclash-override-1002.sh` |
| **FlClash** | <https://github.com/chen08209/FlClash> | Windows / Android | ✅ `targets/flclash-override-1001.js` |

- **OpenClash** —— 运行在 OpenWrt 上的 LuCI 插件，托管 mihomo 内核。
  其上游 README 自述为「本插件是一个可运行在 OpenWrt 上的 Mihomo(Clash) 客户端」。
- **FlClash** —— 桌面 / 移动端独立客户端，内置 mihomo 核心，支持「覆写 → 脚本」模式。

> ⚠️ `rules/` 规则层是通用的，但**产物只适配了 FlClash**。
> 路由器侧（OpenClash）已有排查用的探针脚本（`test/`，当前未提交），尚无产物。
> 适配前提见第三、四节与 `docs/design.md` 第九节。

---

## 二、DNS 行为差异（⚠️ 实测，两端结论相反）

| | FlClash | OpenClash |
|---|---|---|
| 国际 DoH 能否**经代理**送达上游 | ❌ **不能** | ✅ **能** |
| 实测现象 | `dns.resolve failed: context deadline exceeded`（固定 5 秒） | `dns.google` 317ms 返回 HTTP 200；`cloudflare-dns.com` 506ms 内完成 TLS 握手并应答 |
| debug 日志 | DoH 上游反复 `re-creating the http client ... context deadline exceeded`，**无规则匹配行** | — |
| 内核 | FlClash 打包的 mihomo | `alpha-ge183c58`（go1.26.5，2026-08 构建） |

### 结论的适用范围（重要）

**这是 FlClash 客户端的限制，不是 mihomo 的通病。**
遇到 DNS 超时，**先确认用的是哪个客户端**，别把 FlClash 的结论套到路由器上。

### 两条常见修法在 FlClash 上均无效（已实测）

| 做法 | 结果 |
|---|---|
| `respect-rules: true` | ❌ 不代理 DoH 查询。debug 日志里普通流量有 `match ... using <出口>`，而 DoH 上游**没有任何规则匹配行**，就是直连超时 |
| `nameserver: ["https://dns.cloudflare.com/dns-query#代理组"]` | ❌ `#代理名` 语法需 mihomo ≥ v1.15，低版本**静默不生效** |

### 影响面比想象中小

走代理出口的流量**不需要本地解析**（域名直接交给远端节点），
所以**只有「命中 DIRECT 出口 + 境外域名」才会炸**。
排查时先看日志里的 `match ... using DIRECT` 确认命中了直连出口，再怀疑 DNS。

> 别被 `/dns/query` API 的 500 误导 —— 该接口强制走本地解析，
> 代理正常的站点在它下面一样会失败。

### 本项目当前采用的 DNS 设计

默认 `nameserver` **只用国内 DoH**（`doh.pub` / `alidns`），**不配 `fallback` / `fallback-filter`**。

理由：国内 DoH 对境外 CDN 域名能返回正确 IP（实测 alidns 正确返回了 Cloudflare 的
`104.26.3.74` 等），所以直连境外 CDN 也能工作；而走代理的流量由远端解析，完全不受影响。

> ⚠️ 该设计的直接动因是 FlClash。OpenClash 侧可正常经代理使用国际 DoH，
> 但**未验证**「国内 DoH-only」方案在路由器上的实际表现，适配时需重新评估。

---

## 三、覆写机制差异（⚠️ 执行顺序相反）

两者都叫「覆写」，但**配置冲突时谁赢是相反的**。这是适配时最容易出事的地方。

| | FlClash | OpenClash |
|---|---|---|
| 形态 | 独立客户端，内置 mihomo | OpenWrt LuCI 插件，托管 mihomo |
| 覆写入口 | 客户端内「覆写 → 脚本」三选一 | `/etc/openclash/custom/openclash_custom_overwrite.sh` |
| 覆写实现 | JS：`function main(params) { ... return params }` | `/bin/sh` + ruby，用 `ruby_*` 辅助函数**直接改写 YAML 文件** |
| 执行顺序 | 产物脚本 → 客户端自身覆写 | OpenClash 自身脚本 → 自定义覆写 |
| **冲突时谁赢** | ❌ **客户端赢** | ✅ **自定义覆写赢** |
| 其他覆写入口 | `overrideDns` 开关 | `openclash_custom_rules.list` / `_2.list` |

- **FlClash**：先跑产物脚本，再套用客户端自己的覆写。所以 `overrideDns` 一旦打开，
  就用 FlClash 自带 DNS **整段替换**产物 `overwriteDns` 写入的值，而 `rules` / `proxy-providers` 不受影响。
  症状是「规则全对、DNS 全错」，不看源码根本猜不到是谁赢。详见 `README.md` 硬性约束 #7。
- **OpenClash**：该脚本由 `/etc/init.d/openclash` 调用，官方注释明确写着自定义脚本
  「will be take effect **after** the OpenClash own scripts」—— 即**在客户端自身脚本之后**执行，
  因此自定义覆写的值会保留下来。

> 两者都**没有** Clash Verge Rev 那种「合并 / 替换」覆写类型。别把 Ve 的概念套进来。
> 本项目产物对应 FlClash 的「脚本」模式；OpenClash 对应的是 shell + ruby 的自定义覆写文件。

### OpenClash 覆写可用的 API

`openclash_custom_overwrite.sh` 开头 source 了 `/usr/share/openclash/ruby.sh`、
`/usr/share/openclash/log.sh`、`/lib/functions.sh`，配置路径由 `$1`（`CONFIG_FILE`）传入。
可用函数：

| 函数 | 用途 |
|---|---|
| `ruby_edit` | 覆盖单个键值 |
| `ruby_map_edit` | 覆盖 map 内的单个键 |
| `ruby_merge_hash` | 合并 / 新增整个 hash（provider 增删走这个） |
| `ruby_arr_edit` | 数组内按 key 匹配后改值 |
| `ruby_arr_insert` / `ruby_arr_insert_hash` / `ruby_arr_insert_arr` | 按位置插入值 / hash / 数组 |
| `ruby_arr_add_file` | 从指定 YAML 文件取键值插入数组 |
| `ruby_delete` | 删键 / 删数组中的某个值 |

也可在脚本里直接写 `ruby -ryaml` 块自行改写整个配置。

> 本地工作副本 `test/openclash_custom_overwrite.sh` 目前**全是注释**（未启用任何覆写）。
> 路由器上是否同样未改，由探针第 5 节确认。

---

## 四、待验证事项（适配 OpenClash 前）

`test/openclash-probe.sh` 是为此准备的**只读探针**（v2，改用运行中内核进程的
`/proc/<pid>/cmdline` 反查配置路径，修掉了 v1 的定位失败）。用法：

```
scp .\test\openclash-probe.sh root@192.168.31.1:/tmp/probe.sh
ssh 登录后：sh /tmp/probe.sh 2>&1 | tee /tmp/probe-out.txt
```

输出以 `###PROBE_DONE###` 结束。**尚未得到结论**的问题：

- [ ] **探针是否已跑完并回贴输出** —— 下面多数条目都依赖它的结果
- [ ] provider `path` 是否被重映射 —— FlClash 会重映射；OpenClash 若不重映射，
      则 `Telegram_ip` / `Telegram_no_ip` 与 `GoogleFCM_ip` / `GoogleFCM_no_ip`
      这两对共用 path 的问题会**真实触发**（见 `docs/design.md` 第七节）
- [ ] TUN 与 IPv6 三层防护在路由器场景下是否仍需全部三层
      （探针第 2 节查 RA / DHCPv6 / odhcpd / 全局 IPv6 地址与默认路由）
- [ ] 「区域绕过 = 大陆」是通过 `rules` 注入还是防火墙层实现
      —— 若是后者，本项目 `GEOSITE,cn` / `GEOIP,CN` 的位置假设需要重估
- [ ] `PROCESS-NAME` 规则在路由器上无进程概念，是报错还是静默空载
- [ ] Tailscale 出站是否仍有必要 —— OpenWrt 可能已用策略路由处理
      （`100.64.0.0/10` 不在主路由表，`ip rule` 才是检查入口，探针第 4 节）

---

## 五、适配步骤

见 `docs/design.md` 第九节「扩展到其它客户端」。

核心前提：`rules/` 规则层**不需要任何改动** —— 规则层与客户端解耦，正是本项目分层的意义。
第 0 步是跑通第四节那个只读探针，把结论贴回来。

---

## 相关文件

- [`docs/design.md`](design.md) —— 设计说明（第九节：扩展到其它客户端）
- [`README.md`](../README.md) —— 硬性约束 #7：FlClash 的「覆写 DNS」开关
- [`targets/flclash-override-1001.md`](../targets/flclash-override-1001.md) —— 产物功能与规则说明
- `test/openclash-probe.sh`、`test/openclash_custom_overwrite.sh` —— OpenClash 侧工作脚本（**未提交到仓库**）
