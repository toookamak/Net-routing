# openclash-override-1002.conf —— 功能与规则说明

> 本文与 [`openclash-override-1002.conf`](./openclash-override-1002.conf) 同级配套，描述该覆写模块**做了什么**、**产出什么配置**、以及**改的时候该动哪里**。
>
> **文件大版本：1002（2026-10-02 立项）** ｜ **内容版本：v1.1.0** ｜ **规模：51 条分流规则 / 43 个规则集 / 最多 22 个策略组**

---

## 〇、版本约定

**文件名末尾的数字是「大版本」，取立项当天的日期。**

```
openclash-override-1002.conf
                  ^^^^  =  1002  →  2026-10-02 立项
```

| 改动类型 | 该怎么做 |
|---|---|
| 换规则集源、改顺序、改参数、修 bug | **直接改 `openclash-override-1002.conf`，文件名不变** |
| 重大结构调整（策略组结构重做、规则链整体重排） | 以**当天日期**另存为新大版本文件 |

> 文件头部的 `内容版本：v1.1.0` 是**内容版本**（每次有实质改动就递增），
> 与文件名的大版本是两回事，不要混用。

---

## 一、文件定位

| 项 | 说明 |
|---|---|
| 类型 | OpenClash **覆写模块**（INI 格式，`.conf` / `.txt` 均可） |
| 位置 | `/etc/openclash/overwrite/<文件名>` |
| 部署 | LuCI → 服务 → OpenClash → **覆写模块** → 上传 → 把「启用」打开 |
| 执行时机 | 启动流程**第 ③ 步**（`yml_change.sh` → `yml_rules_change.sh` 之后） |
| 产物 | 自包含单文件，`[YAML]` 块内是纯 YAML 声明 |

### 怎么用

1. 浏览器打开 `http://192.168.31.1` → 服务 → OpenClash → 覆写模块；
2. 上传 `openclash-override-1002.conf`（后缀 `.txt` / `.conf` 都收）；
3. 在模块列表里把这一条的**「启用」打开**；
4. 重启 OpenClash。

### 合并算子速查

`[YAML]` 块用的是 OpenClash 自定义的合并算子（来自官方 `overwrite/default` 参考文件）：

| 写法 | 作用 |
|---|---|
| `key` | 默认合并，Hash 递归合并，其他类型直接覆盖 |
| `key!` | **强制覆盖整个值**，不做递归 |
| `key+` / `+key` | 数组后置追加 / 前置插入 |
| `key-` | 数组差集删除 / 非数组则删键（值为空或 `~`） |
| `key*` | 按 `where` / `set` 批量条件更新 |
| `<key>` | 键名含特殊字符时的替代写法，支持同样的后缀 |

本文件用到的算子：

| 位置 | 写法 | 为什么这么写 |
|---|---|---|
| `rules!:` | 强制覆盖 | 订阅自带 516 条，要整条换掉 |
| `proxy-groups!:` | 强制覆盖 | 22 个组全部自建，不留订阅的 3 个 |
| `rule-providers:` | **默认合并** | 要保留 OpenClash 注入的 `oc-cn-domain` |
| `nameserver!:` 等 | 强制覆盖 | 整段换掉，不用增量删 |
| `fallback-:` / `fallback-filter-:` | 删键 | 订阅自带的这两个是坏的（见第六节） |
| `fake-ip-filter+:` | **数组追加** | 追加 27 条，保留原有的 `rule-set:oc-cn-domain` |
| `nameserver-policy:` | 默认合并 | Hash 递归合并 |

### 为什么用覆写模块而不是自定义覆写脚本

两者都能做同样的事，覆写模块更合适：

| | 覆写模块（本文件） | 自定义覆写脚本 |
|---|---|---|
| 写法 | 纯 YAML 声明 | shell + Ruby |
| 表达替换整段 | `rules!:` 一个键 | 自己写 load / 改 / dump |
| 出错可见性 | 编译产物 `/tmp/yaml_overwrite.sh` 可直接看 | `ruby.sh` 带 `2>/dev/null`，**屏幕完全静默** |
| 转义坑 | 无 | shell/Ruby/YAML 三层引号嵌套 |
| emoji | YAML 原生 | Psych 默认转义成 `\U0001F1ED` |
| 执行位置 | 第 ③ 步 | 第 ④ 步（最后） |

**还有一个隐蔽的好处**：覆写模块跑在 `yml_rules_change.sh` **之后**。
自定义规则机制（`openclash_custom_rules.list`）会在那个脚本里校验每条规则的
目标组是否存在，不存在就**静默丢弃**（只在日志留一行 WARN）。
把规则放在覆写模块里就完全绕开了这个陷阱。

### 与仓库其它部分的关系

```
rules/*.yaml        ← 唯一事实来源（规则、策略组、地区、关键词、开关）
      │
      │  人工/AI 渲染
      ▼
targets/openclash-routes.yaml    · 数据源（可 diff，本 .conf 由它拼装）
      │
      ▼
targets/openclash-override-1002.conf  ← 本文件描述的对象（产物，上传到 LuCI）
```

---

## 二、它做了什么

在 OpenClash 生成的配置之上做 4 件事：

| # | 动作 | 对象 | 合并方式 |
|---|---|---|---|
| 1 | 覆盖顶层键 | `mode` / `unified-delay` / `tcp-concurrent` / `geodata-mode` | 默认合并 |
| 2 | **合并** | `dns` 段 | 保留 OpenClash 原有的 `listen` / `enhanced-mode` / `fake-ip-range`；`fake-ip-filter` 追加 |
| 3 | **强制覆盖** | `proxy-groups` | 22 个自定义策略组 |
| 4 | **合并 / 覆盖** | `rule-providers` / `rules` | 保留 OpenClash 注入的 `oc-cn-domain`；规则整条换成 51 条 |

另外在 `[General]` 段设置两个插件级开关：

| 开关 | 值 | 作用 |
|---|---|---|
| `FIND_PROCESS_MODE` | `off` | 路由器上进程规则只对路由器自身生效，留着只增加每连接开销 |
| `GITHUB_ADDRESS_MOD` | `https://cdn.jsdelivr.net/` | 43 个规则集大半来自 `raw.githubusercontent.com`，走 CDN 避免超时导致 provider 静默空载 |

### 绝不做的事

| 对象 | 原因 |
|---|---|
| `proxies` | 订阅生成的节点，含服务器与密码 |
| 任何端口 | OpenClash 生成防火墙规则时按端口配对 |
| `dns.listen` | 必须是 `0.0.0.0:7874`，dnsmasq 已配好转发到它。**写错 = 全局域网 DNS 瘫痪** |
| `authentication` | 面板密钥 |
| `tun` 段 | 混合模式自带（`auto-route: false`，流量靠 iptables 接管） |

---

## 三、策略组清单（22 个）

全部用 `include-all-proxies: true` + `filter` 正则声明，**组内不含任何节点名**，换订阅依然成立。

### 核心路由

| 组名 | 类型 | 默认项 | 说明 |
|---|---|---|---|
| 🧭 代理模式 | `select` | ⚡ 延迟优选 | **顶层唯一入口**，包含地区组 + 故障转移 + 全部节点 + DIRECT/REJECT |
| ⚡ 延迟优选 | `url-test` | 自动 | 全节点测速取最低延迟，`tolerance: 50` 防止频繁切换 |
| 🚧 故障转移 | `fallback` | 自动 | 节点抽风时的兜底，保留全量节点 |
| 🌍 全部节点 | `select` | 第一个 | 手动挑具体节点，**已剔除通知节点** |

### 地区组（url-test，选地区 = 该地区内延迟最低）

| 组名 | 正则来源 | 备注 |
|---|---|---|
| 🇭🇰 香港 / 🇸🇬 新加坡 / 🇯🇵 日本 / 🇺🇸 美国 | `rules/regions.yaml` | 原有 |
| 🇬🇧 英国 | `英国\|UK\|United Kingdom\|伦敦\|🇬🇧` | 2026-10-02 补入 |
| 🇹🇼 台湾 | `台湾\|台灣\|Taiwan\|🇹🇼` | 2026-10-02 补入。**不用单字「台」**（会误伤）；部分机场用 🇨🇳 标台湾，靠「台湾」双字命中 |

### 线路特性

| 组名 | 类型 | 生成条件 |
|---|---|---|
| 🏠 家宽/原生线路 | `select` | 存在家宽节点（当前订阅为 0，走 `empty-fallback` 落 DIRECT） |
| 💰 低倍率节点 | `select` | `低倍率\|lowrate\|低-rate\|倍率\|0\.\d+x\|[0-9]+倍` → 18 个 |
| 📺 流媒体节点 | `select` | `流媒体\|解锁\|Netflix\|Disney\|IPLC\|IEPL` → 18 个 |
| 📢 订阅信息 | `select` | 机场的流量/到期提示节点，正常不该选 |

### 服务组

| 组名 | 类型 | 默认项 | 选项范围 |
|---|---|---|---|
| 📁 办公通讯 | `select` | 第一个 | 代理模式 + 延迟优选 + 故障转移 + 全部节点 + DIRECT + REJECT |
| 🤖 AI服务 | `select` | 第一个 | 同上 |
| 🔍 谷歌服务 | `select` | 第一个 | 同上 |
| 游戏平台 | `select` | 第一个 | 同上 |
| 📺 大流量通道 | `select` | 第一个 | 同上但**不含 REJECT** |
| ⛔ 广告拦截 | `select` | REJECT | **固定 `[REJECT, DIRECT]`** |

> **每一项服务组都含 `DIRECT`** —— 不改任何规则，就能把某一类流量临时改成直连。
> 路由器场景下 homelab 机器没人去面板上点，这个设计更关键。

### 默认路由

| 组名 | 类型 | 默认项 | 接入的规则 |
|---|---|---|---|
| 🛡️ 国内直连 | `select` | **DIRECT** | 第 50 条 `GEOIP,CN` |
| 🌍 兜底代理 | `select` | 第一个 | 第 51 条 `MATCH` |

### 关于空组

所有用正则筛出来的组都配了 `empty-fallback: DIRECT`。

实测本机内核**容忍空组**（`clash_meta -t` 验证：不配 `empty-fallback` 的空组也能通过校验），
所以这不是硬性要求。仍然建议保留 —— 它让「该类别无节点」在面板上有明确回退出口，
而不是变成一个点不动的组。

### 与 flclash 版的一处缺失

flclash 版有个「🌐 其他地区」组，兜住未命中任何地区的节点。**路由器版做不出来** ——
正则无法表达「不匹配上述任何地区」（Go RE2 不支持否定前瞻）。
这些节点仍然能从「🌍 全部节点」进。

---

## 四、规则链全表（51 条）

mihomo 规则**从上到下匹配，命中即停** —— 顺序即优先级。下表是实际输出顺序。

### 第 1 段 · 免拦截白名单（1–2）→ `DIRECT`

| # | 规则 | 作用 |
|---|---|---|
| 1 | `RULE-SET,UnBan,DIRECT` | 广告误伤白名单 |
| 2 | `RULE-SET,DirectNoResolve,DIRECT` | 全球直连修正 |

> **必须排在所有 REJECT 之前**，否则白名单形同虚设。
> 理由：误伤广告规则的代价（装不上、登不进）远大于漏放几个广告。

### 第 2 段 · 广告拦截（3–8）→ `⛔ 广告拦截`

| # | 规则 |
|---|---|
| 3 | `RULE-SET,Reject_no_ip,⛔ 广告拦截` |
| 4 | `RULE-SET,Reject_domainset,⛔ 广告拦截` |
| 5 | `RULE-SET,Reject_no_ip_drop,⛔ 广告拦截` |
| 6 | `RULE-SET,Reject_no_ip_no_drop,⛔ 广告拦截` |
| 7 | `RULE-SET,Reject_ip,⛔ 广告拦截` |
| 8 | `RULE-SET,CustomRejectRules,⛔ 广告拦截` ← 你的规则（`rulesets/OwnREJECTRules.yaml`） |

> 路由器版的广告拦截是 homelab 机器的**唯一防线** —— NAS / PVE / CI 上装不了 FlClash。

### 第 3 段 · tailnet 内网（9–11）→ `DIRECT`

| # | 规则 | 作用 |
|---|---|---|
| 9 | `IP-CIDR,100.64.0.0/10,DIRECT,no-resolve` | Tailscale CGNAT 段 |
| 10 | `IP-CIDR,100.100.100.100/32,DIRECT,no-resolve` | MagicDNS 解析器 |
| 11 | `DOMAIN-SUFFIX,ts.net,DIRECT` | MagicDNS 域名 |

> **必须早于 `GEOSITE,cn` 与 `GEOIP,CN`**，否则内网 IP 会被「国内直连」抢走。
>
> ⚠️ **与 flclash 版的唯一结构差异**：目标直接是 `DIRECT`，不建「🔗 Tailscale」策略组。
> tailscaled 是系统服务，tailnet 路由由它自己的 `ip rule → table 52` 处理，
> mihomo 再插一层只会添乱。**刚需理由**：本机 tailnet 里有 `fnos`(NAS)、`nas6418`、`pve`，
> homelab 机器之间要互访，走代理就断了。

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

### 第 5 段 · 自定义直连（20）→ `DIRECT`（锁死，不建组）

| # | 规则 |
|---|---|
| 20 | `RULE-SET,CustomDirectRules,DIRECT` ← 你的规则（`rulesets/OwnDIRECTRules.yaml`） |

### 第 6 段 · 办公通讯与开发工具链（21–31）→ `📁 办公通讯`

| # | 规则 | 覆盖对象 |
|---|---|---|
| 21 | `RULE-SET,Github,📁 办公通讯` | GitHub |
| 22 | `RULE-SET,Figma_ip,📁 办公通讯` | Figma |
| 23 | `RULE-SET,Notion_ip,📁 办公通讯` | Notion |
| 24 | `RULE-SET,Twitter,📁 办公通讯` | X / Twitter |
| 25 | `RULE-SET,OneDrive,📁 办公通讯` | OneDrive |
| 26 | `RULE-SET,Dropbox,📁 办公通讯` | Dropbox |
| 27 | `RULE-SET,Telegram_ip,📁 办公通讯` | Telegram |
| 28 | `RULE-SET,Microsoft_no_ip,📁 办公通讯` | 微软全线 |
| 29 | `RULE-SET,Docker,📁 办公通讯` | Docker Hub（切 DIRECT 可让 `docker pull` 直连） |
| 30 | `RULE-SET,Npm,📁 办公通讯` | npm / Node.js 包源（**内嵌规则**，无外部依赖） |
| 31 | `RULE-SET,CustomProxyRules,📁 办公通讯` | 你的规则（`rulesets/OwnPROXYRules.yaml`） |

> homelab 权重最高的一段：`git clone` / `docker pull` / `npm` / CI 都在这。

### 第 7 段 · AI 服务（32–34）→ `🤖 AI服务`

| # | 规则 |
|---|---|
| 32 | `RULE-SET,OpenAI,🤖 AI服务` |
| 33 | `RULE-SET,AI_no_ip,🤖 AI服务` |
| 34 | `RULE-SET,Gemini,🤖 AI服务` |

### 第 8 段 · 谷歌服务（35–37）→ `🔍 谷歌服务`

| # | 规则 |
|---|---|
| 35 | `RULE-SET,Google,🔍 谷歌服务` |
| 36 | `RULE-SET,YouTube,🔍 谷歌服务` |
| 37 | `RULE-SET,GoogleFCM_ip,🔍 谷歌服务` |

### 第 9 段 · 大流量通道（38–44）→ `📺 大流量通道`

| # | 规则 |
|---|---|
| 38 | `RULE-SET,MicrosoftCDN_no_ip,📺 大流量通道` |
| 39 | `RULE-SET,CDN_domainset,📺 大流量通道` |
| 40 | `RULE-SET,CDN_no_ip,📺 大流量通道` |
| 41 | `RULE-SET,Download_domainset,📺 大流量通道` |
| 42 | `RULE-SET,Download_no_ip,📺 大流量通道` |
| 43 | `RULE-SET,GameDownload,📺 大流量通道` |
| 44 | `RULE-SET,Stream_ip,📺 大流量通道` |

### 第 10 段 · 游戏平台（45–49）→ `游戏平台`

| # | 规则 |
|---|---|
| 45 | `RULE-SET,Steam,游戏平台` |
| 46 | `RULE-SET,UnrealRules,游戏平台` |
| 47 | `RULE-SET,Origin,游戏平台` |
| 48 | `RULE-SET,Sony,游戏平台` |
| 49 | `RULE-SET,Nintendo,游戏平台` |

> homelab 场景下几乎用不到。流媒体解锁走「📺 流媒体节点」特性组，不走这里。

### 第 11 段 · 兜底（50–51）

| # | 规则 | 作用 |
|---|---|---|
| 50 | `GEOIP,CN,🛡️ 国内直连` | 国内 IP 兜底 |
| 51 | `MATCH,🌍 兜底代理` | 其余全部走代理 |

> **这两条必须是最后两条。** 脚本的自检会强制校验这一点，不符合就中止并回滚。

### 带 `no-resolve` 的规则

当前仅 3 条，全部为内联 `IP-CIDR`：

```
第  9 条  IP-CIDR,100.64.0.0/10,DIRECT,no-resolve
第 10 条  IP-CIDR,100.100.100.100/32,DIRECT,no-resolve
第 13 条  GEOIP,private,DIRECT,no-resolve
```

> ⚠️ provider 名里的 `_ip` / `_no_ip` 后缀表示**规则集的内容类型**（含 IP 规则 / 纯域名规则），
> **不是** mihomo 的 `no-resolve` 参数。这是最容易误解的地方。

### 相比 flclash 版少掉的规则（3 条）

| 删掉的 | 原因 |
|---|---|
| `RULE-SET,applications,📺 大流量通道` | 全部 `PROCESS-NAME`。官方源码原话 *"Only Works on Routerself"* —— 透明代理下连接由客户端进程持有，路由器上查不到，对 LAN 客户端永不命中 |
| `RULE-SET,Telegram_no_ip,...` | 与 `Telegram_ip` 同 URL 同 path，功能完全重复 |
| `RULE-SET,GoogleFCM_no_ip,...` | 同上 |

> 后两条是 flclash 版「已知问题 1」。FlClash 有个「Provider Path Mapping」把 path 重映射成哈希路径，
> **把这个 bug 掩盖了**；OpenClash 尊重声明的 path，两个 provider 会竞争写同一个文件。
> 在路由器上会真实触发，所以这里直接删掉重复项。

---

## 五、规则集清单（43 个）

| 类型 | 数量 | 用途 |
|---|---|---|
| 远程 http | 41 | 广告、免拦截、直连、办公、AI、谷歌、大流量、游戏 |
| 自托管（`rulesets/*.yaml`） | 3 | `CustomRejectRules` / `CustomDirectRules` / `CustomProxyRules` |
| 内嵌（`type: inline`） | 1 | `Npm` —— npm 源域名稳定，但自建仓库随时可能转私有 |

### `format` 与 `behavior` 为什么必须声明准确

声明错时 **mihomo 不报错，只会静默空载**：

- `format` 声明 `yaml` 但文件是纯文本 → 解析失败
- `behavior: classical` 配纯域名列表 → 解析失败
- `behavior: domain` 配混合内容 → 部分规则失效

症状统一是「订阅更新成功、面板一切正常、但某类流量分流不生效」。这是最难自查的一类故障。

> `AppleCNCDN_no_ip` 是唯一用 `behavior: domain` 的条目（纯域名集，更快）。

### 自托管规则集

| 文件 | provider 名 | 生效位置 | 间隔 |
|---|---|---|---|
| `rulesets/OwnREJECTRules.yaml` | `CustomRejectRules` | 第 8 条（广告段末尾） | 24h |
| `rulesets/OwnDIRECTRules.yaml` | `CustomDirectRules` | 第 20 条（锁死 DIRECT） | 24h |
| `rulesets/OwnPROXYRules.yaml` | `CustomProxyRules` | 第 31 条（办公段末尾） | 24h |

**这三个文件的地址只允许出现在规则层一处。** 产物里如果出现第二处硬编码定义，
会在运行时把 YAML 生成的值整个覆盖掉，且 mihomo 静默空载不报错。

---

## 六、DNS

源配置里有一个**真 bug**：

```yaml
respect-rules: false                                    # DNS 不走规则
fallback: [1.1.1.1, 8.8.8.8]                            # 大陆直连必然被污染/超时
fallback-filter: { geosite: [gfw], geoip: true, geoip-code: CN }
```

`fallback-filter` 配了 `geosite:gfw`，所以 gfw 域名的查询全部撞在这个不可达的 fallback 上。
**形状与 flclash 版踩的坑相同，但在本机可修**（原因见下）。

### 本脚本的 DNS 改动

| 项 | 从 | 到 | 理由 |
|---|---|---|---|
| `respect-rules` | `false` | **`true`** | 让 DNS 连接本身也走规则，国际 DoH 才能穿隧道 |
| `fallback` / `fallback-filter` | 坏的 | **删掉** | 1.1.1.1/8.8.8.8 直连不可达 |
| `nameserver` | 三个明文 UDP | 国内 DoH（alidns / doh.pub） | 加密、免明文劫持，实测 175–189ms |
| `proxy-server-nameserver` | 同上 | 国内 DoH | **单独隔离**：机场节点域名被污染就永远连不上。路由器是全家入口，这条比客户端更要命 |
| `nameserver-policy` | 无 | `geosite:gfw,geolocation-!cn` → 国际 DoH | 境外域名走未被污染的源 |
| `default-nameserver` | 三个明文 UDP | 223.5.5.5 / 119.29.29.29 | 引导层，只用来解析上面两个 DoH 的域名，必须明文直连可达 |
| `fake-ip-filter` | 只有 1 条 | **+27 条**（叠加不替换） | 见下 |

**保持不动的键**（合并脚本不会碰）：

```
listen           0.0.0.0:7874    ← dnsmasq 已配好转发到它，绝不能动
enhanced-mode    fake-ip
fake-ip-range    198.18.0.1/16  ← 与本机 LAN 192.168.31.0/24 不冲突
use-hosts        true
```

### fake-ip-filter 补了什么

原配置只有 `rule-set:oc-cn-domain` 一条，意味着**所有**非中国大陆域名都拿假 IP。
补的 27 条覆盖：

| 类别 | 内容 | 不加会怎样 |
|---|---|---|
| 局域网 | `.lan` `.local` `.localdomain` `.home.arpa` `.internal` … | mDNS/SSDP 广播发现失效，NAS、打印机、智能家居互相看不见 |
| **Tailscale** | `+.ts.net` | **MagicDNS 按名字访问全部失败**（IP 访问不受影响） |
| 连通性检测 | `connectivitycheck.gstatic.com` `*.msftconnecttest.com` … | 系统判定「无网络」，影响更新与唤醒逻辑 |
| 时间同步 | `time.*.com` `ntp.*.com` | NTP 按 IP 校验，握手失败 |
| IoT / 智能家居 | `*.esphome.io` `*.homeassistant.io` `*.mi.com` … | 本地证书校验或广播发现依赖 |
| 银行 / 支付 | `+.icbc.com.cn` `+.alipay.com` … | 依赖真实出口 IP 校验，会误判风险 |

> 合并时是**叠加**不是替换 —— OpenClash 注入的 `rule-set:oc-cn-domain` 会保留，
> 所以中国大陆域名仍然走 fake-ip，不会因为加了这些而全部退回真实解析。

### 为什么本机能用国际 DoH 而 FlClash 不能

实测（2026-10-02，路由器自身）：

```
doh.pub:        HTTP 200  0.189s
alidns:         HTTP 200  0.175s
cloudflare DoH: HTTP 400  0.506s   ← 400 是缺 accept 头，但 TLS 握手完成、服务器已应答
google DoH:     HTTP 200  0.317s   ← 200，正文正常
```

`dns.google` 317ms 返回 200 —— 从大陆直连不可能是这个结果，说明**路由器自身流量确实走代理，
DNS 送得进隧道**。

> ⚠️ 结论边界：这是**路由器自身 curl** 的结果。LAN 客户端经 dnsmasq → mihomo 的路径
> 是否同样成立，需在生效后实测（打开面板连接页看出口 IP）。

> 📌 FlClash 版「只能用国内 DoH」的结论**不适用于这里** —— 那是 FlClash 客户端的限制，
> 不是 mihomo 的通病。

### 回退方案

出问题就把数据段里的整个 `dns:` 段删掉，合并脚本会自动跳过 DNS 改动、恢复 OpenClash 原生配置。

若只想关掉国际 DoH、保留 DoH 加密，把 `respect-rules` 改回 `false` 并删掉 `nameserver-policy` 即可。

---

## 七、怎么确认生效 / 出问题怎么定位

### 编译产物可直接看

OpenClash 会把覆写模块**编译成 shell 脚本**再执行：

```sh
cat /tmp/yaml_overwrite.sh
```

这是覆写模块相对自定义脚本最大的优势 —— **编译结果肉眼可读**。
自定义脚本里 Ruby 出错会被 `2>/dev/null` 吞掉、屏幕完全静默，而这里能直接看到 OpenClash 到底理解成了什么。

### 运行日志

```sh
grep -iE 'overwrite|error|fail' /tmp/openclash.log | tail -30
```

### 验证最终配置

```sh
ruby -ryaml -e 'd=YAML.load_file(ARGV[0]);
  puts "规则数  : #{(d["rules"]||[]).size}";
  puts "策略组  : #{(d["proxy-groups"]||[]).size}";
  puts "规则集  : #{(d["rule-providers"]||{}).size}";
  puts "respect : #{(d["dns"]||{})["respect-rules"]}";
  puts "listen  : #{(d["dns"]||{})["listen"]}";
  puts "fallback: #{(d["dns"]||{})["fallback"].inspect}"' /etc/openclash/良心云.yaml
```

预期：`51 / 22 / 43 / true / 0.0.0.0:7874 / nil`

`fallback` 应为 `nil`（已删）。`rule-providers` 应为 43 + 1（OpenClash 的 `oc-cn-domain`）= 44。

### 手动校验配置合法性

```sh
/etc/openclash/core/clash_meta -t -d /etc/openclash -f /etc/openclash/良心云.yaml
```

> `-d /etc/openclash` 不能省 —— 不带 home 目录找不到已下载的 geo 库，会误报失败。

---

## 八、出问题怎么恢复

**最快的办法** —— LuCI 覆写模块页面把本模块的「启用」关掉，重启 OpenClash。
或在覆写设置页面顶部的官方恢复入口：

```
http://<路由器IP>/cgi-bin/luci/admin/services/openclash/restore
```

后者会回到原厂状态，脚本、DNS、fake-ip-filter 全清。

**如果只是分流不对**（网络还通）：改 `[YAML]` 块里的 `rules!:` 或 `proxy-groups!:`，
在模块编辑器里保存，重启。

> **关键认知：mihomo 起不来 ≠ 路由器起不来。** LuCI、SSH、dnsmasq 都不依赖代理进程。
> 最坏情况是「没有代理但局域网正常」，LuCI 用 `http://192.168.31.1` 照样进。
> 但**本项目的 AI 通道依赖代理** —— 动手前请确认手机能连蜂窝数据，
> 那是唯一不经过这台路由器的 AI 通道。

---

## 九、已知问题

### 1. 🔴 IPv6 泄露（本脚本不解决，需单独处理）

```
network.lan.ip6assign='60'          LAN 分配 IPv6 前缀
dhcp.lan.ra='server'                odhcpd 在发 RA
default via fe80::1 dev eth0        有 IPv6 出口
ip6tables FORWARD policy ACCEPT     防火墙放行
全局地址 2408:824e:d21:dde0:...     中国电信公网 IPv6
```

OpenClash 侧 `ipv6_enable=0`、mihomo 侧 `dns.ipv6: false` → **IPv6 流量完全不过代理**。
客户端拿到 RA 下发的 IPv6 后直连出门，AI 服务看到的是真实家庭 IPv6。

**FlClash 的三层封堵（`ipv6:false` + `dns.ipv6:false` + `tun.inet6-route-address:["2000::/3"]`）
在路由器上不成立** —— 那里没有 TUN 接管（OpenClash 混合模式的 `tun.auto-route: false`）。

只能在系统层解决，且**必须停 RA**，只关 sysctl 没用（客户端手里已分配的地址还在）：

```sh
uci set network.lan.ip6assign='0'
uci set dhcp.lan.ra='disabled'
uci set dhcp.lan.dhcpv6='disabled'
uci commit network; uci commit dhcp
/etc/init.d/odhcpd restart; /etc/init.d/network restart
```

> 副作用：tailnet 走 IPv6 的设备（`maxxieha`）会改走 IPv4，日常使用不受影响。
> **改之前先 `uci export network > /tmp/network.bak`。**

### 2. 家宽 / 低倍率节点不进入地区组 —— 本版**有意不同**

flclash 版把家宽/低倍率节点排除出所有地区组（见 `docs/design.md` 已知问题 2）。
**本版不这么做**，因为实测该订阅里 `0.1x` / `0.01x` 标注是主流线路的常态
（美国 12 个节点里 10 个带倍率），排除会让美英两组直接清空。

代价：地区组的 url-test 可能在低倍率节点里选。如果某个地区组总是选到不理想的线路，
可以在该组的 `exclude-filter` 里加 `0\.01x`（只排最可疑的超低倍率节点）——
**注意加之前先确认该地区仍有节点**。

### 3. 「🌐 其他地区」组做不出来

正则无法表达「不匹配上述任何地区」（Go RE2 不支持否定前瞻）。
未命中任何地区的节点只能从「🌍 全部节点」进。

### 4. 策略组名与规则目标组之间没有自动校验

组名同时出现在 `proxy-groups` 和 `rules` 里。改组名必须两处同步。
**脚本的自检能拦住漏改**（中止并回滚），但 PC 侧开发时应当先人工核对。

### 5. 依赖 GitHub raw 的规则集

43 个规则集里大部分来自 `raw.githubusercontent.com`。从大陆直连经常超时，
而 mihomo 对 provider 下载失败是**静默空载**。

→ 建议在 LuCI **覆写设置 → 常规设置**里把「GitHub 地址代理」设成一个 CDN
（`https://cdn.jsdelivr.net/` 等）。OpenClash 的 `yml_rules_change.sh` 会自动把
`raw.githubusercontent.com` 开头的 URL 重写成 CDN 地址。

---

## 十、常见调整入口

| 想改什么 | 改哪里 | 需要重新渲染产物？ |
|---|---|---|
| 加一条自己的分流规则 | `rulesets/Own*.yaml` | **不用** —— 提交推送后内核按 24h 间隔自动拉取 |
| 换规则集源 / 改格式 / 改间隔 | `rules/providers.yaml` | ✅ |
| 调整规则顺序 / 改分流目标 | `rules/priorities.yaml` | ✅ |
| 增删策略组、改组名 | `rules/groups.yaml` | ✅ |
| 增删地区、改地区正则 | `rules/regions.yaml` | ✅ |
| 改通知/家宽/低倍率/流媒体关键词 | `rules/filters.yaml` | ✅ |
| 改 DNS（DoH 源、policy、fake-ip-filter） | `[YAML]` 块的 `dns:` | ✅ |
| 改合并语义 | `[YAML]` 块里的键名后缀（`!` / `+` / `-`） | ✅ |

**两类改动的区别很重要**：

- 改 `rulesets/*.yaml` —— 只提交推送即可，内核按 `interval: 86400`（24 小时）自动拉取，
  **不用碰产物**。这是日常最常用的入口。
- 改 `rules/*.yaml` —— 只是改了「事实来源」，**产物不会自动同步**。
  必须重新渲染 `openclash-override-1002.conf` 再上传回 LuCI。

---

## 十一、免责与来源

本文件与 `openclash-override-1002.conf` 均为个人学习用途的脚本存档，
由 AI 辅助生成后自行审阅调整，**未经完整的人工逐行审计**，可能存在逻辑缺陷与错误注释。

配置会接管系统流量、修改 DNS，**配置错误可能导致部分流量不可用**。使用前请自行审阅全部代码。

第三方规则内容的著作权与许可协议归原作者所有，**须遵守各上游项目自身的许可协议**。
`rulesets/` 随仓库一起公开，请勿填入不希望公开的内网域名或内部服务地址。

> ⚠️ 跨境网络访问相关行为可能违反当地法律法规，使用前请自行评估并承担全部责任。

**上游项目**：[OpenClash](https://github.com/vernesong/OpenClash)（MIT，
本体是 MetaCubeX/mihomo 的前端与 OpenWrt 集成）、
[mihomo 内核文档](https://wiki.metacubex.one/)。
规则内容来自 [ACL4SSR](https://github.com/ACL4SSR/ACL4SSR)、
[blackmatrix7](https://github.com/blackmatrix7/ios_rule_script)、
[RealSeek](https://github.com/RealSeek/Clash_Rule_DIY)、
[Loyalsoldier](https://github.com/Loyalsoldier/clash-rules)、
[SukkaW](https://ruleset.skk.moe)。
