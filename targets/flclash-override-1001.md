# flclash-override-1001.js —— 功能与规则说明

> 本文与 [`flclash-override-1001.js`](./flclash-override-1001.js) 同级配套，描述该覆写脚本**做了什么**、**产出什么配置**、以及**改的时候该动哪里**。
>
> **文件版本：1001（2026-10-01 立项）** ｜ **内容版本：v1.0.0** ｜ **规模：53 条分流规则 / 45 个规则集 / 最多 21 个策略组**

---

## 〇、版本约定

**文件名末尾的数字是「大版本」，取立项当天的日期。**

```
flclash-override-1001.js
             ^^^^  =  1001  →  2026-10-01 立项
```

| 改动类型 | 该怎么做 |
|---|---|
| 加规则、调顺序、改注释、修 bug、调整参数 | **直接改 `flclash-override-1001.js`，文件名不变** |
| 重大结构调整（模块拆分、入口签名改变、策略组结构重做、规则链整体重排） | 以**当天日期**另存为新大版本文件 |

重大结构调整时的做法：

```
flclash-override-1001.js   →   flclash-override-1108.js
        （旧文件保留在仓库里，便于回溯与对照）
```

同时更新本文档，改名为 `flclash-override-1108.md` 继续配套。

> 文件内的 `vX.Y.Z` 是**内容版本**（每次有实质改动就递增），与文件名的大版本是两回事，不要混用。

---

## 一、文件定位

| 项 | 说明 |
|---|---|
| 类型 | mihomo 覆写脚本（override script） |
| 入口 | `main(params)` —— 标准覆写签名 |
| 运行位置 | FlClash 客户端内，随配置渲染时执行，**不是** Node.js 脚本 |
| 依赖 | mihomo 内核 ≥ v1.19.25（FlClash ≥ 0.8.93 打包该内核） |
| 产物 | 自包含单文件，无任何 import / require |

### 怎么用

1. FlClash → 配置 → 覆写（Override）→ 新建；
2. 整份粘贴 `flclash-override-1001.js` 的内容；
3. 保存并切换到该配置。脚本会在订阅原始配置之上做整体改写。

### 与仓库其它部分的关系

```
rules/*.yaml   ← 唯一事实来源（规则、策略组、地区、关键词、开关）
      │
      │  人工/AI 渲染
      ▼
targets/flclash-override-1001.js   ← 本文件描述的对象（产物，不要手改数据段）
      │
      ▼
FlClash → mihomo 内核
```

**改规则要改 `rules/*.yaml` 再重新生成产物，不要直接改产物里的数据段**（`@generated:begin/end` 之间）。
脚本内标注「@generated」之外的代码是逻辑段，可直接维护。

---

## 二、它做了什么

`main()` 依次执行 7 个模块。**顺序有依赖，不可随意调整**：

| # | 模块 | 职责 | 为何必须在这个位置 |
|---|---|---|---|
| 1 | Basic Options | 端口、IPv6 开关、geodata、指纹等全局项 | 最先，后续模块依赖 `ipv6: false` 等前提 |
| 2 | Sniffer | 流量嗅探、TLS/HTTP 解析、APNs 与 Telegram 排除 | 独立，但须在规则前就位 |
| 3 | Tailscale | 注入 `TS-TAILSCALE` 出站节点 | **必须在节点分类前**，否则该节点会被当成机场节点参与测速 |
| 4 | Proxy Groups | 分类订阅节点，构建全部策略组 | **必须在规则前**，规则的目标组必须已存在 |
| 5 | Rules | 按优先级拼装 53 条规则 + 45 个 rule-provider | 依赖策略组名 |
| 6 | DNS | fake-ip、DoH 分流、fake-ip-filter | 独立 |
| 7 | TUN | TUN 接管、IPv6 封堵、MTU | 收尾 |

### 容错行为

- **单个模块失败不会中断整体生成**，但结束时一定会在控制台汇总打印失败模块与原因。
- `STRICT_MODE = true` 时改为直接抛异常，阻断半成品配置。
- `DEBUG_MODE = true` 打开详细日志（注意：`logError` 与失败汇总**始终**输出，不受此开关影响）。
- 订阅异常（`proxies` 缺失或为空）时直接原样返回，不做任何改写。

### 节点分类规则

订阅节点在**单趟遍历**中完成全部判定，结果决定哪些策略组会被创建：

| 判定 | 关键词 | 后果 |
|---|---|---|
| 通知节点 | `自动\|故障\|流量\|官网\|套餐\|机场\|订阅\|年付\|月付\|…` | **剔除出「全部节点」**，只留在「📢 订阅信息」组 |
| 家宽 / 原生 | `家宽\|原生\|residential\|home` | 归入「🏠 家宽/原生线路」，**不进入任何地区组** |
| 低倍率 | `低倍率\|lowrate\|低-rate\|倍率` | 归入「💰 低倍率节点」，**不进入任何地区组** |
| 地区 | `香港\|HK\|…` 等 | 归入对应地区组（url-test） |
| Tailscale | `proxy.type === 'tailscale'` | **完全排除**在分类、测速、地区之外 |

> **已知取舍**：命中家宽/低倍率的节点会被排除在地区组之外。真实订阅中「香港 家宽」这类节点
> **只出现在「🌍 全部节点」和特性组中**。若某地区节点全是家宽/低倍率，该地区组不会被创建，
> 选项列表中相应条目也会消失。这是继承自原单文件脚本的既有行为。

---

## 三、策略组清单

满配 21 个。地区组与特性组按订阅实际节点动态增减。

### 核心路由

| 组名 | 类型 | 默认项 | 说明 |
|---|---|---|---|
| 🧭 代理模式 | `select` | ⚡ 延迟优选 | **顶层唯一入口**，日常只需要碰这一个组 |
| ⚡ 延迟优选 | `url-test` | 自动 | 全节点测速取最低延迟，`lazy` 按需测速 |
| 🚧 故障转移 | `fallback` | 自动 | 节点抽风时的兜底，`lazy` 按需测速 |
| 🌍 全部节点 | `select` | 第一个 | 手动挑具体节点的入口 |
| 🔗 Tailscale | `select` | **DIRECT（关闭）** | 切到 `TS-TAILSCALE` 才登录 tailnet；不切不建连，零开销 |

### 地区组（url-test，选地区 = 该地区内自动选最低延迟）

| 组名 | 生成条件 |
|---|---|
| 🇭🇰 香港 / 🇸🇬 新加坡 / 🇯🇵 日本 / 🇺🇸 美国 | 该地区存在**至少一个非特性节点** |
| 🌐 其他地区 | 存在未命中任何地区的普通节点 |

### 线路特性

| 组名 | 类型 | 生成条件 |
|---|---|---|
| 🏠 家宽/原生线路 | `select` | 存在家宽节点 |
| 💰 低倍率节点 | `select` | 存在低倍率节点 |
| 📢 订阅信息 | `select` | 存在通知节点（正常不该选） |

### 服务组

| 组名 | 类型 | 默认项 | 选项范围 |
|---|---|---|---|
| 📁 办公通讯 | `select` | 🧭 代理模式 | 代理模式 + 自动策略 + 节点来源 + DIRECT + REJECT |
| 🤖 AI服务 | `select` | 🧭 代理模式 | 同上 |
| 🔍 谷歌服务 | `select` | 🧭 代理模式 | 同上 |
| 游戏平台 | `select` | 🧭 代理模式 | 同上 |
| ⛔ 广告拦截 | `select` | **REJECT** | **固定两项 `[REJECT, DIRECT]`，不可选其他出口** |
| 📺 大流量通道 | `select` | 🧭 代理模式 | 代理模式 + 自动策略 + 节点来源 + DIRECT（无 REJECT） |

### 默认路由

| 组名 | 类型 | 默认项 | 接入的规则 |
|---|---|---|---|
| 🛡️ 国内直连 | `select` | **DIRECT** | 第 52 条 `GEOIP,CN` |
| 🌍 兜底代理 | `select` | 🧭 代理模式 | 第 53 条 `MATCH` |

---

## 四、规则链全表（53 条）

mihomo 规则**从上到下匹配，命中即停** —— 顺序即优先级。下表是实际输出顺序。

### 第 1 段 · 免拦截白名单（1–2）→ `DIRECT`

| # | 规则 | 作用 |
|---|---|---|
| 1 | `RULE-SET,UnBan,DIRECT` | 广告误伤白名单，捞回直连 |
| 2 | `RULE-SET,DirectNoResolve,DIRECT` | 全球直连修正（267 条，含 `PROCESS-NAME`） |

> **必须排在所有 REJECT 之前**，否则白名单形同虚设。

### 第 2 段 · 广告拦截（3–8）→ `⛔ 广告拦截`

| # | 规则 | 作用 |
|---|---|---|
| 3 | `RULE-SET,Reject_no_ip,⛔ 广告拦截` | 广告拦截（纯域名） |
| 4 | `RULE-SET,Reject_domainset,⛔ 广告拦截` | 广告拦截（domainset） |
| 5 | `RULE-SET,Reject_no_ip_drop,⛔ 广告拦截` | 丢弃型广告规则 |
| 6 | `RULE-SET,Reject_no_ip_no_drop,⛔ 广告拦截` | 非丢弃型广告规则 |
| 7 | `RULE-SET,Reject_ip,⛔ 广告拦截` | 广告 IP 段 |
| 8 | `RULE-SET,CustomRejectRules,⛔ 广告拦截` | **你自己的拦截规则**（`rulesets/OwnREJECTRules.yaml`） |

### 第 3 段 · Tailscale 内网（9–11）→ `🔗 Tailscale`

| # | 规则 | 作用 |
|---|---|---|
| 9 | `IP-CIDR,100.64.0.0/10,🔗 Tailscale,no-resolve` | Tailscale 固定 CGNAT 段 |
| 10 | `IP-CIDR,100.100.100.100/32,🔗 Tailscale,no-resolve` | MagicDNS 解析器 |
| 11 | `DOMAIN-SUFFIX,ts.net,🔗 Tailscale` | MagicDNS 域名 |

> **必须早于 `GEOSITE,cn` 与 `GEOIP,CN`**，否则内网 IP 会被「国内直连」先抢走。

### 第 4 段 · 私有网络与国内直连（12–19）→ `DIRECT`

| # | 规则 | 作用 |
|---|---|---|
| 12 | `GEOSITE,private,DIRECT` | 私有域名 |
| 13 | `GEOIP,private,DIRECT,no-resolve` | 私有 IP 段 |
| 14 | `RULE-SET,MicrosoftCNCDN_no_ip,DIRECT` | 国内备案微软 CDN |
| 15 | `RULE-SET,AppleCNCDN_no_ip,DIRECT` | 国内备案 Apple CDN |
| 16 | `GEOSITE,cn,DIRECT` | **国内域名** |
| 17 | `RULE-SET,Lan_ip,DIRECT` | 局域网 IP |
| 18 | `RULE-SET,SteamCN_ip,DIRECT` | Steam 国内服务器 |
| 19 | `RULE-SET,Domestic_no_ip,DIRECT` | 国内直连补充 |

### 第 5 段 · 应用级分流（20）→ `📺 大流量通道`

| # | 规则 | 作用 |
|---|---|---|
| 20 | `RULE-SET,applications,📺 大流量通道` | 按进程名匹配（`PROCESS-NAME`） |

### 第 6 段 · 自定义直连（21）→ `DIRECT`（锁死，不建组）

| # | 规则 | 作用 |
|---|---|---|
| 21 | `RULE-SET,CustomDirectRules,DIRECT` | **你自己的直连规则**（`rulesets/OwnDIRECTRules.yaml`） |

### 第 7 段 · 办公通讯与开发工具链（22–32）→ `📁 办公通讯`

| # | 规则 | 覆盖对象 |
|---|---|---|
| 22 | `RULE-SET,Figma_ip,📁 办公通讯` | Figma |
| 23 | `RULE-SET,Notion_ip,📁 办公通讯` | Notion |
| 24 | `RULE-SET,Github,📁 办公通讯` | GitHub |
| 25 | `RULE-SET,OneDrive,📁 办公通讯` | OneDrive |
| 26 | `RULE-SET,Dropbox,📁 办公通讯` | Dropbox |
| 27 | `RULE-SET,Telegram_ip,📁 办公通讯` | Telegram |
| 28 | `RULE-SET,Telegram_no_ip,📁 办公通讯` | Telegram（重复，见已知问题） |
| 29 | `RULE-SET,Microsoft_no_ip,📁 办公通讯` | 微软全线 |
| 30 | `RULE-SET,Docker,📁 办公通讯` | Docker Hub（切 DIRECT 可让 `docker pull` 直连） |
| 31 | `RULE-SET,Npm,📁 办公通讯` | npm / Node.js 包源（**内嵌规则**，无外部依赖） |
| 32 | `RULE-SET,CustomProxyRules,📁 办公通讯` | **你自己的代理规则**（`rulesets/OwnPROXYRules.yaml`） |

### 第 8 段 · AI 服务（33–35）→ `🤖 AI服务`

| # | 规则 | 覆盖对象 |
|---|---|---|
| 33 | `RULE-SET,OpenAI,🤖 AI服务` | OpenAI / ChatGPT |
| 34 | `RULE-SET,AI_no_ip,🤖 AI服务` | AI 服务补充规则 |
| 35 | `RULE-SET,Gemini,🤖 AI服务` | Google Gemini |

### 第 9 段 · 谷歌服务（36–39）→ `🔍 谷歌服务`

| # | 规则 | 覆盖对象 |
|---|---|---|
| 36 | `RULE-SET,YouTube,🔍 谷歌服务` | YouTube |
| 37 | `RULE-SET,GoogleFCM_ip,🔍 谷歌服务` | Google 推送（重复，见已知问题） |
| 38 | `RULE-SET,Google,🔍 谷歌服务` | Google 全线 |
| 39 | `RULE-SET,GoogleFCM_no_ip,🔍 谷歌服务` | Google 推送（重复，见已知问题） |

### 第 10 段 · 大流量通道（40–46）→ `📺 大流量通道`

| # | 规则 | 覆盖对象 |
|---|---|---|
| 40 | `RULE-SET,MicrosoftCDN_no_ip,📺 大流量通道` | 微软 CDN |
| 41 | `RULE-SET,CDN_domainset,📺 大流量通道` | CDN 域名集 |
| 42 | `RULE-SET,CDN_no_ip,📺 大流量通道` | CDN 补充 |
| 43 | `RULE-SET,Download_domainset,📺 大流量通道` | 下载站域名集 |
| 44 | `RULE-SET,Download_no_ip,📺 大流量通道` | 下载站补充 |
| 45 | `RULE-SET,GameDownload,📺 大流量通道` | 游戏下载分发平台 |
| 46 | `RULE-SET,Stream_ip,📺 大流量通道` | 流媒体 |

### 第 11 段 · 游戏平台（47–51）→ `游戏平台`

| # | 规则 | 覆盖对象 |
|---|---|---|
| 47 | `RULE-SET,UnrealRules,游戏平台` | Epic / Unreal |
| 48 | `RULE-SET,Steam,游戏平台` | Steam（商店与下载，CN 服务器除外，见第 18 条） |
| 49 | `RULE-SET,Origin,游戏平台` | EA Origin |
| 50 | `RULE-SET,Sony,游戏平台` | PlayStation |
| 51 | `RULE-SET,Nintendo,游戏平台` | Switch |

### 第 12 段 · 兜底（52–53）

| # | 规则 | 作用 |
|---|---|---|
| 52 | `GEOIP,CN,🛡️ 国内直连` | 国内 IP 兜底 |
| 53 | `MATCH,🌍 兜底代理` | 其余全部走代理 |

> **这两条必须是最后两条。** 提前会让后面的规则永远不生效。

### 带 `no-resolve` 的规则

当前仅 3 条，全部为内联 `IP-CIDR` / `GEOIP`：

```
第  9 条  IP-CIDR,100.64.0.0/10,🔗 Tailscale,no-resolve
第 10 条  IP-CIDR,100.100.100.100/32,🔗 Tailscale,no-resolve
第 13 条  GEOIP,private,DIRECT,no-resolve
```

> ⚠️ provider 名里的 `_ip` / `_no_ip` 后缀表示**规则集的内容类型**（含 IP 规则 / 纯域名规则），
> **不是** mihomo 的 `no-resolve` 参数。这是最容易误解的地方。

---

## 五、规则集清单（45 个）

| 来源 | 数量 | 格式 | 更新间隔 | 用途 |
|---|---|---|---|---|
| [RealSeek/Clash_Rule_DIY](https://github.com/RealSeek/Clash_Rule_DIY) | 14 | yaml / classical | 48h | 广告拦截、国内直连、CDN、下载、流媒体、AI 补充 |
| [ACL4SSR](https://github.com/ACL4SSR/ACL4SSR) | 12 | text / classical | 48h | UnBan、Google、YouTube、Telegram、OneDrive、主机商店 |
| [blackmatrix7/ios_rule_script](https://github.com/blackmatrix7/ios_rule_script) | 12 | yaml / classical | 48h | GitHub、Docker、OpenAI、Gemini、Figma、Notion、Dropbox、Steam、Epic、游戏下载 |
| [SukkaW/ruleset](https://ruleset.skk.moe) | 2 | text / classical+domain | 48h | 国内备案微软 / Apple CDN |
| [Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules) | 1 | text / classical | 24h | `applications`（进程名分流） |
| 自托管（`rulesets/*.yaml`） | 3 | yaml / classical | 24h | 你自己的 DIRECT / PROXY / REJECT 规则 |
| 内嵌（`type: inline`） | 1 | 内联 | — | npm / Node.js 包源 |

### format 与 behavior 为什么必须声明准确

声明错时 **mihomo 不报错，只会静默空载**：

- `format` 声明 `yaml` 但文件是纯文本 → 解析失败
- `behavior: classical` 配纯域名列表 → 解析失败
- `behavior: domain` 配混合内容 → 部分规则失效

症状统一是「订阅更新成功、面板一切正常、但某类流量分流不生效」。这是最难自查的一类故障。

> `AppleCNCDN_no_ip` 是唯一用 `behavior: domain` 的条目（纯域名集，更快）。
> 注意 Sukka 的 `non_ip/apple_cdn.txt` 已废弃，必须用 `domainset` 版本。

### 自托管规则集

| 文件 | provider 名 | 生效位置 | 间隔 |
|---|---|---|---|
| `rulesets/OwnREJECTRules.yaml` | `CustomRejectRules` | 第 8 条（广告拦截段末尾） | 24h |
| `rulesets/OwnDIRECTRules.yaml` | `CustomDirectRules` | 第 21 条（锁死 DIRECT） | 24h |
| `rulesets/OwnPROXYRules.yaml` | `CustomProxyRules` | 第 32 条（办公通讯段末尾） | 24h |

**这三个文件的地址只允许出现在 `rules/providers.yaml` 一处。** 产物里如果出现第二处硬编码定义，
会在运行时把 YAML 生成的值整个覆盖掉，且 mihomo 静默空载不报错。

---

## 六、网络层配置

### IPv6 泄露封堵（三层，缺一层就失效）

```js
ipv6: false                            // 全局：不走 IPv6 出站
dns.ipv6: false                         // DNS：不返回 AAAA 记录
tun.inet6-route-address: ["2000::/3"]   // TUN：接管全球 IPv6 单播段
```

**只设前两层是无效的。** 系统从宽带/手机卡拿到的 IPv6 地址，浏览器发现网站支持 IPv6
就直接走网卡出去 —— 流量根本没进 TUN，mihomo 看不见，`MATCH` 也管不到。

第三层让 TUN 把 `2000::/3` 抓进来、因 `ipv6: false` 而丢弃，浏览器自动回退 IPv4 走代理。

`fe80::/10`（链路本地）与 `::1`（回环）不在 `2000::/3` 内，不受影响。

> 代价：IPv6-only 网站不可用。ChatGPT / HuggingFace 等均为双栈，实际无损。

### DNS

| 项 | 值 | 理由 |
|---|---|---|
| 增强模式 | `fake-ip` | 性能与分流准确度优于 `redir-host` |
| 默认 DNS | Cloudflare DoH + Google DoH | 防止未知域名泄露给国内 DNS |
| 引导 DNS | 223.5.5.5 / 119.29.29.29 / 1.1.1.1 / 8.8.8.8 | 仅用于解析上面两个 DoH 的域名 |
| 代理节点域名 | 同国外 DoH | 防止被污染导致连不上节点 |
| 分流策略 | `geosite:cn,private,apple` → 阿里 DoH + 腾讯 DoH | 国内域名走国内 DNS，国内网站保持一层直连 |

`fake-ip-filter` 共 27 条，覆盖局域网、IoT、银行支付、系统连通性检测、Tailscale MagicDNS。
这些服务拿到假 IP 就无法工作（无法回连、心跳、局域网发现或真实 IP 校验）。

### TUN

| 项 | 值 | 理由 |
|---|---|---|
| `stack` | `mixed` | 兼容性最好 |
| `mtu` | **1400** | 1500 易导致大包丢弃、网页卡顿与下载断流 |
| `auto-redirect` | `false` | mihomo 稳定后已无必要 |
| `strict-route` | `false` | 避免与系统路由表冲突 |

### 流量嗅探

- 强制 DNS 映射、纯 IP 也嗅探，**不改写目的地地址**（改写会破坏连接复用）
- 排除 APNs 推送（否则收不到推送）与 Telegram 机房段

---

## 七、硬性约束（改动时不能破坏）

1. **凡是从「🧭 代理模式」可选中的组，都不能设 `hidden`**
   `hidden` 的组不出现在客户端分组列表里，用户选中后找不到入口配置，形成死路。
   `hidden` 仅适用于「用户永不直接碰、仅被内部引用」的内部组。

2. **规则段之间不可调换顺序**
   段内可自由增删规则，段与段的先后不可动。三条硬顺序见第四节的段标题。

3. **`no-resolve` 必须排在目标组之后**
   ```
   GEOIP,private,DIRECT,no-resolve     ✅
   GEOIP,private,no-resolve,DIRECT     ❌ 报 proxy [no-resolve] not found
   ```
   统一由 `buildRule()` / `parseRule()` 处理，不要手写字符串拼接。

4. **Tailscale 节点必须排除在节点分类之外**
   `classifyNodes` 中显式 `if (proxy.type === 'tailscale') return;`。
   否则它会混入「全部节点」、进入 url-test / fallback 组导致测速打向未连接的节点。

5. **模块执行顺序不可调整**（见第二节表格）

6. **自托管规则集的地址只能出现在 `rules/providers.yaml` 一处**

---

## 八、常见调整入口

| 想改什么 | 改哪里 |
|---|---|
| 加一条自己的分流规则 | `rulesets/Own*.yaml` → 提交推送，**不用重新生成产物** |
| 换规则集源 / 改更新间隔 / 改 format | `RULE_PROVIDER_DEFINITIONS`（数据段） |
| 调整规则顺序、改分流目标 | `RULE_PRIORITIES`（数据段） |
| 增删策略组、改组名 | `STRATEGY_NAMES` + 各 `build*Groups()` |
| 增删地区 | `REGION_CONFIG`（数据段） |
| 改通知 / 家宽 / 低倍率关键词 | `FILTER_KEYWORDS` |
| 改测速间隔 | `CONFIG_MANAGER.SPEED_TEST_INTERVAL` |
| 改国内 IP 默认直连还是走代理 | `CONFIG_MANAGER.DOMESTIC_TRAFFIC_DEFAULT` |
| 开关 Tailscale、改设备名 | `TAILSCALE_CONFIG` |
| 开关 IPv6 封堵 | `overwriteBasicOptions` + `overwriteDns` + `overwriteTunnel`（**三层一起**） |
| 开关调试日志 / 严格模式 | `DEBUG_MODE` / `STRICT_MODE` |

---

## 九、已知问题

### 1. 两组 provider 共用同一 `path`（未修复）

`Telegram_ip` / `Telegram_no_ip` 与 `GoogleFCM_ip` / `GoogleFCM_no_ip` 各自指向**完全相同**的
url 与 `path`。运行时必定输出告警：

```
[net-routing Warn] 多个 provider 共用同一路径: ./ruleset/toookamak/Telegram.list -> Telegram_ip, Telegram_no_ip
[net-routing Warn] 多个 provider 共用同一路径: ./ruleset/toookamak/GoogleFCM.list -> GoogleFCM_ip, GoogleFCM_no_ip
```

**后果**：两个 provider 竞争写入同一缓存文件，更新时可能互相覆盖；
且这两对规则在功能上完全重复（两者都不带 `no-resolve`）。
合并需改规则名，待办。

### 2. 家宽 / 低倍率节点不进入地区组（设计取舍）

见第二节「节点分类规则」。真实订阅中「香港 家宽」「新加坡 低倍率」这类节点
只出现在「🌍 全部节点」和特性组中。若某地区节点全是特性节点，该地区组不会被创建。

### 3. 改策略组名没有自动校验

组名同时出现在 `STRATEGY_NAMES`、`RULE_PRIORITIES` 和各 `build*Groups()` 三处，
需人工确认三处同步。改漏会产出「规则指向不存在的组」的坏配置 ——
表现为整份配置加载失败，但排查成本极高。

### 4. Android 端 Tailscale 权限

mihomo v1.19.25 修复了 netlink 权限问题，但 Android 平台仍可能有未覆盖的场景。
桌面端已验证，Android 需实测。

---

## 十、免责声明

本文件与 `flclash-override-1001.js` 均为个人学习用途的脚本存档，由 AI 辅助生成后自行审阅调整，
**未经完整的人工逐行审计**，可能存在逻辑缺陷与错误注释。

配置会接管系统网络栈、修改 DNS 并改写路由表，**配置错误可能导致系统网络不可用**。
使用前请自行审阅全部代码并备份原始网络配置。

第三方规则内容的著作权与许可协议归原作者所有，**须遵守各上游项目自身的许可协议**。
`rulesets/` 随仓库公开，请勿填入不希望公开的内网域名或内部服务地址。

> ⚠️ 跨境网络访问相关行为可能违反当地法律法规，使用前请自行评估并承担全部责任。
