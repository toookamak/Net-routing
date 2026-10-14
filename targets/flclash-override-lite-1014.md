# flclash-override-lite-1014.js —— 功能与规则说明（lite 轻量版）

> 本文与 [`flclash-override-lite-1014.js`](./flclash-override-lite-1014.js) 同级配套，描述该覆写脚本**做了什么**、**产出什么配置**、以及**改的时候该动哪里**。
>
> **文件版本：lite-1014（2026-10-14 立项）** ｜ **内容版本：v1.0.0** ｜ **规模：23 条分流规则 / 13 个规则集 / 最多 12 个策略组**

---

## 〇、版本约定

**文件名末尾的数字是「大版本」，取立项当天的日期。**

```
flclash-override-lite-1014.js
                     ^^^^  =  1014  →  2026-10-14 立项
```

| 改动类型 | 该怎么做 |
|---|---|
| 加规则、调顺序、改注释、修 bug、调整参数 | **直接改 `flclash-override-lite-1014.js`，文件名不变** |
| 重大结构调整（模块拆分、入口签名改变、策略组结构重做、规则链整体重排） | 以**当天日期**另存为新大版本文件 |

> 文件内的 `vX.Y.Z` 是**内容版本**（每次有实质改动就递增），与文件名的大版本是两回事，不要混用。

### 与全量产物 `flclash-override-1001.js` 的关系

两者**互不影响，可以同时存在**：

| | `flclash-override-1001.js` | `flclash-override-lite-1014.js` |
|---|---|---|
| 定位 | 什么都能调 | 少而稳 |
| 分流规则 | 54 | **23** |
| 规则集 | 46 | **13** |
| 策略组上界 | 23 | **12** |
| 地区 | 6（港/新/日/美/英/台） | **4（港/新/日/美）+ 🌐 其他地区** |
| 内核要求 | mihomo ≥ v1.19.25（Tailscale 出站） | **无额外要求**（不使用 tailscale 出站） |

**全量产物是 lite 的骨架来源**：lite 的代码骨架取自 `flclash-override-1001.js`（内容版本 v1.1.0，2026-10-14），
按 [`rules/profile-lite.yaml`](../rules/profile-lite.yaml) 声明的白名单裁剪数据段。两边的**基础设施代码完全相同**
（DNS / TUN / sniffer / IPv6 三层封堵 / 容错与校验），差异只在数据段与策略组构建函数。

---

## 一、文件定位

| 项 | 说明 |
|---|---|
| 类型 | mihomo 覆写脚本（override script） |
| 入口 | `main(params)` —— 标准覆写签名 |
| 运行位置 | FlClash 客户端内，随配置渲染时执行，**不是** Node.js 脚本 |
| 依赖 | **无额外内核要求**；不使用 mihomo 的 `tailscale` 出站，因此全量产物那条「mihomo ≥ v1.19.25」在本产物中不适用 |
| 产物 | 自包含单文件，无任何 import / require |

### 怎么用

1. FlClash → 配置 → 覆写（Override）→ 新建；
2. 整份粘贴 `flclash-override-lite-1014.js` 的内容；
3. 保存并切换到该配置。脚本会在订阅原始配置之上做整体改写。

> ⚠️ FlClash 的「覆写 DNS」开关**必须保持关闭**。开着会用客户端 DNS 整段替换脚本写入的值，
> 症状是「规则全对、DNS 全错」。这一条与全量产物相同。

### 与仓库其它部分的关系

```
rules/*.yaml            ← 唯一事实来源（规则、策略组、地区、关键词、开关）
rules/profile-lite.yaml ← lite 的裁剪白名单（保留哪些段/组/规则集）
      │
      │  人工/AI 渲染
      ▼
targets/flclash-override-lite-1014.js   ← 本文件描述的对象（产物，不要手改数据段）
      │
      ▼
FlClash → mihomo 内核
```

**改规则要改 `rules/*.yaml` 再重新生成产物，不要直接改产物里的数据段**（`@generated:begin/end` 之间）。
脚本内标注「@generated」之外的代码是逻辑段，可直接维护。

---

## 二、它做了什么

`main()` 依次执行 **6 个模块**（比全量产物少一个 Tailscale 注入）。**顺序有依赖，不可随意调整**：

| # | 模块 | 职责 | 为何必须在这个位置 |
|---|---|---|---|
| 1 | Basic Options | 端口、IPv6 开关、geodata、指纹等全局项 | 最先，后续模块依赖 `ipv6: false` 等前提 |
| 2 | Sniffer | 流量嗅探、TLS/HTTP 解析、APNs 与 Telegram 排除 | 独立，但须在规则前就位 |
| 3 | Proxy Groups | 分类订阅节点，构建全部策略组 | **必须在规则前**，规则的目标组必须已存在 |
| 4 | Rules | 按优先级拼装 23 条规则 + 13 个 rule-provider | 依赖策略组名 |
| 5 | DNS | fake-ip、DoH、fake-ip-filter | 独立 |
| 6 | TUN | TUN 接管、IPv6 封堵、MTU | 收尾 |

### 容错行为

- **单个模块失败不会中断整体生成**，但结束时一定会在控制台汇总打印失败模块与原因。
- `STRICT_MODE = true` 时改为直接抛异常，阻断半成品配置。
- `DEBUG_MODE = true` 打开详细日志（注意：`logError` 与失败汇总**始终**输出，不受此开关影响）。
- 订阅异常（`proxies` 缺失或为空）时直接原样返回，不做任何改写。

### 节点分类规则

订阅节点在**单趟遍历**中完成判定：

| 判定 | 关键词 / 条件 | 后果 |
|---|---|---|
| 通知节点 | `自动\|故障\|流量\|官网\|套餐\|机场\|订阅\|年付\|月付\|…` | **剔除出「全部节点」与所有策略组**（本产物没有「📢 订阅信息」组） |
| 地区 | 港 / 新 / 日 / 美 四组正则 | 归入对应地区组（url-test） |
| 其他地区 | 未命中上述四组、且不是通知节点 | 归入「🌐 其他地区」（url-test） |
| Tailscale | `proxy.type === 'tailscale'` | **完全排除**在分类与所有策略组之外 |

> **与全量产物的两处差异**：
> 1. **不再有家宽 / 低倍率判定**。全量产物把「家宽 / 原生 / 低倍率」节点视为特殊节点、排除出地区组；
>    lite 取消了这层判定，这类节点与普通节点同等参与地区归属 —— 既在「🌍 全部节点」里，也回到所属地区组。
>    （全量产物「家宽节点被排除出地区组」这个已知问题，在 lite 中不存在。）
> 2. **通知节点不再有落脚的组**。全量产物里它们进「📢 订阅信息」；lite 删了该组，
>    通知节点只是被排除出所有组（仍留在 `proxies` 列表里，不会影响任何分流）。

---

## 三、策略组清单

满配 **12 个**。地区组与「🌐 其他地区」按订阅实际节点动态增减。

### 核心路由（4）

| 组名 | 类型 | 默认项 | 说明 |
|---|---|---|---|
| 🧭 代理模式 | `select` | ⚡ 延迟优选 | **顶层唯一入口**，日常只需要碰这一个组 |
| ⚡ 延迟优选 | `url-test` | 自动 | 全节点测速取最低延迟，`lazy` 按需测速 |
| 🚧 故障转移 | `fallback` | 自动 | 节点抽风时的兜底，`lazy` 按需测速 |
| 🌍 全部节点 | `select` | 第一个 | 手动挑具体节点的集合入口 |

### 「🧭 代理模式」的选项（lite 特有）

选项顺序（第一项即默认选中项）：

```
⚡ 延迟优选 → 地区组（港/新/日/美）→ 🌐 其他地区 → 🌍 全部节点 → 🚧 故障转移 → DIRECT
→ 全部具体节点名（内联）
```

**末尾内联了全部具体节点**，因此可以直接把「🧭 代理模式」指定为某一个节点，
不必先进「🌍 全部节点」再挑一层。mihomo 允许 `select` 的 `proxies` 列表里混放策略组与具体节点。

> 代价：节点多时这个下拉列表会很长（100 个节点就是 100 项）。
> 想退回「只列组、不列节点」，删掉 `buildCoreGroups()` 里的 `...inlineNodes` 即可。

> ⚠️ **lite 已从「🧭 代理模式」的选项中移除 `REJECT`。**
> 全量产物里该组含 `REJECT`，而兜底规则 `MATCH` 又指向「🌍 兜底代理」（默认跟随「🧭 代理模式」），
> 顶层误选 `REJECT` 会让全部兜底流量被拒 —— 断网级的隐患。lite 把 `REJECT` 只留在「⛔ 广告拦截」组里。

### 地区组（`url-test`，选地区 = 该地区内自动选最低延迟）

| 组名 | 生成条件 |
|---|---|
| 🇭🇰 香港 / 🇸🇬 新加坡 / 🇯🇵 日本 / 🇺🇸 美国 | 该地区存在**至少一个非通知节点** |
| 🌐 其他地区 | 存在未命中任何地区、且不是通知节点的节点 |

> lite 只保留**港 / 新 / 日 / 美**四个地区组。英国、台湾以及其它地区的节点
> 统一进「🌐 其他地区」，不再单独成组。

### 服务组（2）

| 组名 | 类型 | 默认项 | 选项范围 |
|---|---|---|---|
| 🤖 AI服务 | `select` | 🧭 代理模式 | 代理模式 + 自动策略 + 节点来源 + DIRECT + REJECT |
| ⛔ 广告拦截 | `select` | **REJECT** | **固定两项 `[REJECT, DIRECT]`，不可选其他出口** |

### 默认路由（1）

| 组名 | 类型 | 默认项 | 接入的规则 |
|---|---|---|---|
| 🛡️ 国内直连 | `select` | **DIRECT** | 第 22 条 `GEOIP,CN` |

> lite 没有「🌍 兜底代理」组 —— 第 23 条 `MATCH` **直接指向「🧭 代理模式」**，
> 少一层中间组。该组默认选中「⚡ 延迟优选」，即「其余一切走代理」。

---

## 四、规则链全表（23 条）

mihomo 规则**从上到下匹配，命中即停** —— 顺序即优先级。下表是实际输出顺序。

### 第 1 段 · 免拦截白名单（1–2）→ `DIRECT`

| # | 规则 | 作用 |
|---|---|---|
| 1 | `RULE-SET,UnBan,DIRECT` | 广告误伤白名单，捞回直连 |
| 2 | `RULE-SET,DirectNoResolve,DIRECT` | 全球直连修正（含 `PROCESS-NAME`） |

> **必须排在所有 REJECT 之前**，否则白名单形同虚设。

### 第 2 段 · 广告拦截（3–4）→ `⛔ 广告拦截`

| # | 规则 | 作用 |
|---|---|---|
| 3 | `RULE-SET,Reject_no_ip,⛔ 广告拦截` | 广告拦截（主集，纯域名） |
| 4 | `RULE-SET,CustomRejectRules,⛔ 广告拦截` | **你自己的拦截规则**（`rulesets/OwnREJECTRules.yaml`） |

> lite 只保留两本。全量产物还挂了 `Reject_domainset` / `Reject_no_ip_drop` /
> `Reject_no_ip_no_drop` / `Reject_ip` 四本（见第九节「被移除的规则集」）。

### 第 3 段 · Tailscale 硬直连（5–9）→ `DIRECT`

| # | 规则 | 作用 |
|---|---|---|
| 5 | `IP-CIDR,100.64.0.0/10,DIRECT,no-resolve` | Tailscale 固定 CGNAT 段（隧道流量） |
| 6 | `IP-CIDR,100.100.100.100/32,DIRECT,no-resolve` | MagicDNS 解析器 |
| 7 | `DOMAIN-SUFFIX,ts.net,DIRECT` | MagicDNS 域名 |
| 8 | `PROCESS-NAME,tailscaled,DIRECT` | Linux / macOS 的 tailscaled 进程 |
| 9 | `PROCESS-NAME,tailscaled.exe,DIRECT` | Windows 的 tailscaled.exe 进程 |

**为什么是这五条**：lite **不接管 Tailscale、也不注入 mihomo 的 tailscale 出站** ——
由系统自带的 Tailscale 客户端负责建连，clash 只保证这些流量不被绕进代理。

- 第 5、6 条接住 tailnet 网段。`*.ts.net` 在 `fake-ip-filter` 里，拿到的是真实 `100.x` 地址，所以这两条能命中；
- 第 7 条接住 MagicDNS 域名的其它形态；
- 第 8、9 条接住 **tailscaled 只带公网 IP 的连接** —— DERP / STUN 打洞没有域名，只有进程名兜得住
  （控制面 `controlplane.tailscale.com` 也由此覆盖）。

> ⚠️ `PROCESS-NAME` 需要 `find-process-mode` 非 `off`（本配置为 `strict`）。
> **Android 上 FlClash 拿不到其它应用的进程名**，第 8、9 条在手机上不生效 ——
> 但不生效也无副作用，只是退回「没有这两条」的行为（隧道 IP 与 `ts.net` 仍由第 5–7 条接住）。
>
> `tailscale.com` / `tailscale.io` 的域名**故意不直连**：它们是登录页与管理后台，
> 属于普通网站，交给正常分流即可；客户端自身的控制面流量已由进程规则覆盖。

> **必须早于 `GEOSITE,cn` 与 `GEOIP,CN`**，否则内网 IP 会被「国内直连」先抢走。

### 第 4 段 · 私有网络与国内直连（10–16）→ `DIRECT`

| # | 规则 | 作用 |
|---|---|---|
| 10 | `GEOSITE,private,DIRECT` | 私有域名 |
| 11 | `GEOIP,private,DIRECT,no-resolve` | 私有 IP 段 |
| 12 | `RULE-SET,MicrosoftCNCDN_no_ip,DIRECT` | 国内备案微软 CDN |
| 13 | `RULE-SET,AppleCNCDN_no_ip,DIRECT` | 国内备案 Apple CDN |
| 14 | `GEOSITE,cn,DIRECT` | **国内域名** |
| 15 | `RULE-SET,Lan_ip,DIRECT` | 局域网 IP |
| 16 | `RULE-SET,Domestic_no_ip,DIRECT` | 国内直连补充 |

### 第 5 段 · 自定义直连（17）→ `DIRECT`（锁死，不建组）

| # | 规则 | 作用 |
|---|---|---|
| 17 | `RULE-SET,CustomDirectRules,DIRECT` | **你自己的直连规则**（`rulesets/OwnDIRECTRules.yaml`） |

### 第 6 段 · 自定义代理（18）→ `🧭 代理模式`

| # | 规则 | 作用 |
|---|---|---|
| 18 | `RULE-SET,CustomProxyRules,🧭 代理模式` | **你自己的代理规则**（`rulesets/OwnPROXYRules.yaml`） |

> 全量产物这里投的是「📁 办公通讯」；lite 没有该组，直接投顶层「🧭 代理模式」。

### 第 7 段 · AI 服务（19–21）→ `🤖 AI服务`

| # | 规则 | 覆盖对象 |
|---|---|---|
| 19 | `RULE-SET,OpenAI,🤖 AI服务` | OpenAI / ChatGPT |
| 20 | `RULE-SET,AI_no_ip,🤖 AI服务` | AI 服务补充规则 |
| 21 | `RULE-SET,Gemini,🤖 AI服务` | Google Gemini |

### 第 8 段 · 兜底（22–23）

| # | 规则 | 作用 |
|---|---|---|
| 22 | `GEOIP,CN,🛡️ 国内直连` | 国内 IP 兜底 |
| 23 | `MATCH,🧭 代理模式` | 其余全部走代理 |

> **这两条必须是最后两条。** 提前会让后面的规则永远不生效。

### 带 `no-resolve` 的规则

当前 **3 条**，全部为内联 `IP-CIDR` / `GEOIP`：

```
第  5 条  IP-CIDR,100.64.0.0/10,DIRECT,no-resolve
第  6 条  IP-CIDR,100.100.100.100/32,DIRECT,no-resolve
第 11 条  GEOIP,private,DIRECT,no-resolve
```

语义：**不为了匹配这条规则而去做 DNS 解析**。只在已经拿到目标 IP（直接连 IP、
或已有缓存映射）时才参与匹配，避免「为了一条 IP 规则触发解析」造成额外延迟。

### 「要不要走代理」到底按什么判断

不是单看 `geoip`。真实判定链是**域名优先、IP 兜底、最后 MATCH**：

1. **域名 / 进程类规则先匹配**（不依赖 DNS 解析，mihomo 直接用域名比）：
   白名单 → 广告 → 私有域名 → 国内 CDN → `GEOSITE,cn`（国内域名库）→ 局域网 →
   自定义直连 → 自定义代理 → AI 服务；
2. 域名类都没命中时，**才**看 IP 类规则：`GEOIP,private`（私有网段）、
   `GEOIP,CN`（国内 IP 库 `geoip.dat`）→「🛡️ 国内直连」；
3. 都没命中 → 第 23 条 `MATCH` →「🧭 代理模式」（默认「⚡ 延迟优选」）→ **走代理**。

两点容易误解的地方：

- `GEOSITE` 是**域名库**，`GEOIP` 是**IP 库**，两者数据源不同、判定时机也不同；
- 本配置是 **fake-ip** 模式（`enhanced-mode: fake-ip`，`198.18.0.1/16`）。域名类规则完全不受影响；
  而 IP 类规则只在「已拿到真实 IP」时才有机会命中 —— 所以国内流量的主要兜底其实是
  `GEOSITE,cn` + 各国内规则集，`GEOIP,CN` 是最后一层保险。

---

## 五、规则集清单（13 个）

| # | 名称 | 目标组 | 来源 | 说明 |
|---|---|---|---|---|
| 1 | `UnBan` | `DIRECT` | 第三方 | 广告误伤白名单 |
| 2 | `DirectNoResolve` | `DIRECT` | 第三方 | 全球直连修正 |
| 3 | `Reject_no_ip` | `⛔ 广告拦截` | 第三方 | 广告拦截主集 |
| 4 | `CustomRejectRules` | `⛔ 广告拦截` | **自托管** | `rulesets/OwnREJECTRules.yaml` |
| 5 | `MicrosoftCNCDN_no_ip` | `DIRECT` | 第三方 | 国内备案微软 CDN |
| 6 | `AppleCNCDN_no_ip` | `DIRECT` | 第三方 | 国内备案 Apple CDN |
| 7 | `Lan_ip` | `DIRECT` | 第三方 | 局域网 IP |
| 8 | `Domestic_no_ip` | `DIRECT` | 第三方 | 国内直连补充 |
| 9 | `CustomDirectRules` | `DIRECT` | **自托管** | `rulesets/OwnDIRECTRules.yaml` |
| 10 | `CustomProxyRules` | `🧭 代理模式` | **自托管** | `rulesets/OwnPROXYRules.yaml` |
| 11 | `OpenAI` | `🤖 AI服务` | 第三方 | OpenAI / ChatGPT |
| 12 | `AI_no_ip` | `🤖 AI服务` | 第三方 | AI 服务补充 |
| 13 | `Gemini` | `🤖 AI服务` | 第三方 | Google Gemini |

> 13 本里有 3 本是**自托管**的：改 `rulesets/Own*.yaml` 后只需提交推送，
> 客户端按 `interval: 86400` 自动拉取，**不用重新生成产物**。

### 为什么规则集数量才是 lite 的主要收益

两个维度的影响完全不同：

| 维度 | 影响 | lite 的削减 |
|---|---|---|
| 策略组数量 | **只影响界面**（分组列表长度） | 23 → 12 |
| 规则集条目数 | **影响启动解析、常驻内存、更新流量** | 46 → 13 |

三个 domainset 大集（`Reject_domainset` 等）单本就有十万量级条目，是体积与更新流量的主要来源 ——
lite 全部不挂，这是单项最大的收益，代价是漏拦变多（见第九节）。

### `format` 与 `behavior` 为什么必须声明准确（继承自全量产物）

这两项声明错了**不会报错**，而是整份规则集**静默空载**：

- `Reject_domainset` 这类 domainset 的上游是 `+.域名` 简写格式，必须 `behavior: domain`；
  写成 `classical` 会整份解析失败并丢弃 —— 表现为「广告拦截实际为空」；
- `applications` 的 URL 后缀是 `.txt` 但内容是 YAML，必须 `format: yaml`（lite 未使用该集）。

---

## 六、网络层配置

### IPv6 泄露封堵（三层，缺一层就失效）

| 层 | 位置 | 值 |
|---|---|---|
| 1 | `overwriteBasicOptions` | `ipv6: false` |
| 2 | `overwriteDns` | `dns.ipv6: false` |
| 3 | `overwriteTunnel` | `tun.inet6-route-address: ["2000::/3"]` |

只设前两层**无效**：系统自身的 IPv6 路由会绕过 TUN 直连，必须由 TUN 把全球单播段
抓进来丢弃，浏览器才会回退到 IPv4 走代理。`fe80::/10` 与 `::1` 不在此段内，不受影响。

### DNS

- `enhanced-mode: fake-ip`，`fake-ip-range: 198.18.0.1/16`
- 默认 DNS 只用国内 DoH：`doh.pub` + `dns.alidns.com`；`proxy-server-nameserver` 同
- **没有 `fallback`**，不配国际 DoH

> **为什么不用国际 DoH**：FlClash 内置的 mihomo 内核**无法把 DNS 查询送进代理**
> （2026-10-02 实测：`respect-rules: true` 与 `nameserver` 的 `#代理名` 后缀都无效）。
> 国外 DoH 从大陆直连必然超时（实测 cloudflare DoH 直连 5652ms、走代理 215ms），
> 稳定超过 mihomo 的 5 秒 DNS 超时，于是 `dns resolve failed: context deadline exceeded`。
> 而走代理出口的流量**不需要本地解析**（域名直接交给远端节点），所以国内 DoH 够用。
> 代价是失去「防 DNS 污染」能力 —— 这是当前内核版本下的取舍。

- `fake-ip-filter` 27 条：局域网 / 组播、小米与苹果、QQ 登录、Windows 连通性检测、
  银行支付、IoT、以及 **`+.ts.net`**（让 MagicDNS 拿到真实 `100.x` 地址，Tailscale 规则才命中）

### TUN

- `stack: mixed`，`mtu: 1400`（不是 1500：降低大包被丢弃的概率，减少卡顿与断流）
- `dns-hijack: ["any:53"]`、`auto-route: true`、`strict-route: false`

### 流量嗅探

- 强制 DNS 映射、纯 IP 也嗅探，**不改写目的地地址**（改写会破坏连接复用）
- 排除 APNs 推送（否则收不到推送）与 Telegram 机房段

---

## 七、硬性约束（改动时不能破坏）

1. **凡是从「🧭 代理模式」可选中的组，都不能设 `hidden`**
   `hidden` 的组不出现在客户端分组列表里，用户选中后找不到入口配置，形成死路。
   `hidden` 仅适用于「用户永不直接碰、仅被内部引用」的内部组。

2. **规则段之间不可调换顺序**
   段内可自由增删规则，段与段的先后不可动。三条硬顺序：
   - 白名单（第 1 段）必须在所有 REJECT 之前；
   - Tailscale 段必须在 `GEOSITE,cn` 与 `GEOIP,CN` 之前；
   - `GEOIP,CN` 与 `MATCH` 必须是最后两条。

3. **`no-resolve` 必须排在目标组之后**
   ```
   GEOIP,private,DIRECT,no-resolve     ✅
   GEOIP,private,no-resolve,DIRECT     ❌ 报 proxy [no-resolve] not found
   ```
   统一由 `buildRule()` / `parseRule()` 处理，不要手写字符串拼接。

4. **Tailscale 节点必须排除在节点分类之外**
   `classifyNodes` 中显式 `if (proxy.type === 'tailscale') return;`。
   否则它会混入「全部节点」、进入 url-test / fallback 组导致测速打向未连接的节点。

5. **策略组选项的来源必须与「组是否被创建」同生共死**
   `buildNodeSourceOptions()` 里推入的地区组名必须用 `classification.availableRegions`
   （真正建组的条件）判定；推入一个不存在的组名会让 mihomo 报 `ProxyGroup loop` 或
   `group not found`，整份配置加载失败。

6. **模块执行顺序不可调整**（见第二节表格）

7. **自托管规则集的地址只能出现在 `rules/providers.yaml` 一处**

8. **「覆写 DNS」开关保持关闭**（见第一节）

---

## 八、常见调整入口

| 想改什么 | 改哪里 |
|---|---|
| 加一条自己的分流规则 | `rulesets/Own*.yaml` → 提交推送，**不用重新生成产物** |
| 让某个地区重新单独成组（如英国） | `rules/regions.yaml` + `rules/profile-lite.yaml` 的 `regions.keep` |
| 换规则集源 / 改更新间隔 / 改 format | `RULE_PROVIDER_DEFINITIONS`（数据段） |
| 调整规则顺序、改分流目标 | `RULE_PRIORITIES`（数据段） |
| 增删策略组、改组名 | `STRATEGY_NAMES` + 各 `build*Groups()` |
| 让「🧭 代理模式」不再内联具体节点 | `buildCoreGroups()` 里删掉 `...inlineNodes` |
| 改通知节点关键词 | `FILTER_KEYWORDS.NOTIFICATION` |
| 改测速间隔 | `CONFIG_MANAGER.SPEED_TEST_INTERVAL` |
| 改国内 IP 默认直连还是走代理 | `CONFIG_MANAGER.DOMESTIC_TRAFFIC_DEFAULT` |
| 让 `tailscale.com` / `tailscale.io` 也直连 | `RULE_PRIORITIES` 的 `tailscale` 段加两条 `DOMAIN-SUFFIX` |
| 开关 IPv6 封堵 | `overwriteBasicOptions` + `overwriteDns` + `overwriteTunnel`（**三层一起**） |
| 开关调试日志 / 严格模式 | `DEBUG_MODE` / `STRICT_MODE` |

---

## 九、与全量产物的差异（取舍记录）

### 被移除的 9 类东西，以及代价

| 移除项 | 省下 | 代价 |
|---|---|---|
| 广告拦截收窄（删 3 个 domainset + `Reject_no_ip_drop` + `Reject_no_ip_no_drop` + `Reject_ip`） | **4 个规则集**（含约 10.8 万条广告域名） | 漏拦变多；失去 `drop`（丢弃连接）语义，只剩 `REJECT` |
| 服务组整段删除（办公通讯 / 谷歌服务 / 游戏平台 / 大流量通道） | 17 个规则集 | 这些流量全部落到 `MATCH` → 走代理，不能单独换出口 |
| 删 `applications`（进程级分流） | 1 个规则集 | 桌面端失去「按进程分流」能力 |
| 删 `SteamCN_ip` | 1 个规则集 | Steam 国内服务器不再显式直连（仍可能被 `GEOSITE,cn` 兜住） |
| 删内嵌 `Npm` 规则集 | 1 个内嵌集 | npm 源不再单独直连 |
| 删家宽 / 低倍率判定与两组 | 2 个策略组 + 2 条正则 | 失去「只看家宽 / 只看低倍率」的筛选入口；**换来家宽节点回到地区组** |
| 删「📢 订阅信息」组 | 1 个策略组 | 通知节点不再有落脚的组（只是被排除） |
| 删 Tailscale 出站与「🔗 Tailscale」组 | 1 个策略组 + 1 个节点 + 内核版本要求 | 不再能用 clash 代替 Tailscale 客户端；改为系统客户端 + 硬直连规则 |
| 删「🌍 兜底代理」组 | 1 个策略组 | 兜底不再有独立开关，`MATCH` 直接跟随「🧭 代理模式」 |

> **为什么删服务组不会导致「断网」**：mihomo **命中即停**，服务组只是「让该类流量换出口」的开关。
> 删掉某个服务组、连同它的规则一起删掉后，那些流量会落到 `MATCH` 兜底 —— 仍然走代理。
> 丢的是**可调性**（不能单独给它换出口），不是**可用性**。

### 保留的关键决定

| 决定 | 说明 |
|---|---|
| 保留 🚧 故障转移（全量节点） | `docs/design.md` 第五节把「故障转移保留全量节点」记为**功能**取舍；lite 维持该决定，不为省电牺牲兜底覆盖 |
| 保留地区组测速（`url-test`） | 选地区 = 该地区内自动选最低延迟，不退化成手动挑节点 |
| 保留 `lazy: true` | 纯减少无谓工作，不改任何行为 |
| 保留 IPv6 三层封堵 / MTU 1400 / 国内域名直连 | 与全量产物完全一致 |

---

## 十、已知问题

### 1. 改策略组名没有自动校验

组名同时出现在 `STRATEGY_NAMES`、`RULE_PRIORITIES` 和各 `build*Groups()` 三处，
需人工确认三处同步。改漏会产出「规则指向不存在的组」的坏配置 ——
表现为整份配置加载失败，但排查成本极高。

### 2. Android 端进程规则不生效

见第四节第 3 段：Android 上 FlClash 拿不到其它应用的进程名，
`PROCESS-NAME,tailscaled` 两条在手机上不生效（隧道 IP 与 `ts.net` 仍由 IP / 域名规则接住）。

### 3. 广告拦截覆盖面比全量产物窄

lite 只挂两本广告规则集，`Reject_domainset` 等大集未挂。若发现漏拦，
把对应规则集加回 `RULE_PROVIDER_DEFINITIONS` 与 `RULE_PRIORITIES` 的 `adblock` 段即可。

### 4. 没有自动化测试

仓库没有构建脚本、没有自动校验（`test/` 下是路由器侧 OpenClash 的排查脚本）。
lite 产物由 AI 依 `rules/*.yaml` + `rules/profile-lite.yaml` 渲染，
本次渲染后做过一次「构造假订阅 → 跑 `main()` → 逐项断言」的冒烟测试
（12 组 / 23 规则 / 13 规则集、组引用完整性、`no-resolve` 位置、IPv6 三层等），
但**没有纳入仓库、不会随改动自动重跑**。

---

## 十一、免责声明

本文件与 `flclash-override-lite-1014.js` 均为个人学习用途的脚本存档，由 AI 辅助生成后自行审阅调整，
**未经完整的人工逐行审计**，可能存在逻辑缺陷与错误注释。

配置会接管系统网络栈、修改 DNS 并改写路由表，**配置错误可能导致系统网络不可用**。
使用前请自行审阅全部代码并备份原始网络配置。

第三方规则内容的著作权与许可协议归原作者所有，**须遵守各上游项目自身的许可协议**。
`rulesets/` 随仓库公开，请勿填入不希望公开的内网域名或内部服务地址。
