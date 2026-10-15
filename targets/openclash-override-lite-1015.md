# openclash-override-lite-1015.conf —— 功能与规则说明（lite 轻量版）

> 本文是 [`openclash-override-lite-1015.conf`](./openclash-override-lite-1015.conf) 的配套说明，
> 描述路由器侧覆写**做了什么**、**产出什么配置**、**改的时候该动哪里**。
>
> 全量版见 [`openclash-override-1002.conf`](./openclash-override-1002.conf) 与其说明
> [`openclash-override-1002.md`](./openclash-override-1002.md)。**那份文档里与「覆写模块机制」有关的内容
> —— `filter` 的单引号硬约束、编译产物 `/tmp/yaml_overwrite.sh`、日志会 watchdog 清空、
> 恢复入口 —— 在本产物上完全成立，本文不重复展开，只写 lite 特有的部分。**
>
> **文件大版本：1015（2026-10-15 立项）** ｜ **内容版本：v1.1.0** ｜ **规模：22 条分流规则 / 13 个规则集 / 11 个策略组**

---

## 〇、版本约定

**文件名末尾的数字是「大版本」，取立项当天的日期。**

```
openclash-override-lite-1015.conf
                       ^^^^  =  1015  →  2026-10-15 立项
```

| 改动类型 | 该怎么做 |
|---|---|
| 换规则集源、改顺序、改参数、修 bug | **直接改 `openclash-override-lite-1015.conf`，文件名不变** |
| 重大结构调整（策略组结构重做、规则链整体重排） | 以**当天日期**另存为新大版本文件 |

> 文件头部的 `内容版本：v1.1.0` 是**内容版本**（每次有实质改动就递增），与文件名的大版本是两回事，不要混用。
> **改动内容时必须同步递增它** —— 路由器上无法用 git 查部署的是哪一版，只能靠这个号人工比对：
>
> ```sh
> grep -n 'net-routing artifact' /tmp/yaml_overwrite.sh
> # 本文件应为：net-routing artifact: 1015 lite v1.1.0
> ```

### 与全量产物 `openclash-override-1002.conf` 的关系

两者**互不影响地存在于仓库里，但不能同时在路由器上启用**（见下文「怎么用」）。

| | `openclash-override-1002.conf` | `openclash-override-lite-1015.conf` |
|---|---|---|
| 定位 | 什么都能调 | 少而稳 |
| 分流规则 | 52 | **22** |
| 规则集 | 43 | **13** |
| 策略组 | 22 | **11** |
| 地区 | 6（港/新/日/美/英/台） | **4（港/新/日/美）** |
| 服务组 | 5（办公通讯 / AI / 谷歌 / 游戏 / 大流量） | **2（AI / 广告拦截）** |
| 兜底 | `MATCH` → `🌍 兜底代理` → `🧭 代理模式` | **`MATCH` → `🧭 代理模式`（少一跳）** |
| 自托管规则集 | 3（OwnDIRECT / OwnPROXY / OwnREJECT） | 3（**同一份**） |
| 内核要求 | Meta 内核 | Meta 内核（相同） |

**全量产物是 lite 的骨架来源**：lite 的 `[General]`、`[YAML]` 顶层键、DNS 段、
fake-ip-filter 全部逐行取自 `openclash-override-1002.conf`（内容版本 v1.8.0），
只按 [`rules/profile-lite-openclash.yaml`](../rules/profile-lite-openclash.yaml) 声明的白名单
重建了三个段：`rules!` / `rule-providers` / `proxy-groups!`。

> 这与 FlClash 侧的结构一致：那边也是 lite 骨架取全量、按 `rules/profile-lite.yaml` 裁剪数据段。
> **两端各自有一份裁剪白名单**，互不引用：
>
> | | FlClash | OpenClash（路由器） |
> |---|---|---|
> | 全量 | `targets/flclash-override-1001.js` | `targets/openclash-override-1002.conf` |
> | lite | `targets/flclash-override-lite-1014.js` | `targets/openclash-override-lite-1015.conf` |
> | 裁剪白名单 | `rules/profile-lite.yaml` | `rules/profile-lite-openclash.yaml` |
>
> **两边裁剪范围刻意不完全相同**（见第十节），不要「顺手统一」。

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
2. 上传 `openclash-override-lite-1015.conf`（后缀 `.txt` / `.conf` 都收）；
3. 在模块列表里把这一条的**「启用」打开**；
4. 重启 OpenClash。

> ⚠️⚠️ **本文件与全量 `openclash-override-1002.conf` 不能同时启用。**
> 两者都有 `[YAML]` 块，OpenClash 对多个模块是**依次合并**而不是「后者覆盖前者」，
> `rules!` / `proxy-groups!` 会按启用顺序互相覆盖，结果取决于列表顺序，不可预期。
> **切换顺序**：先停用全量模块 → 重载 → 再启用本模块。回退则反过来。
>
> 本文件是**替换关系**，不是叠加关系 —— lite 不是「全量的补丁」。

### `filter` 的硬约束（本产物同样踩这个坑）

OpenClash 0.47.156 拼 `[YAML]` 块时逐行执行 `eval "echo \"$line\""`，
**双引号会提前闭合引号、`|` 变成管道运算符、整行被静默删除**。
规避办法只有一条：**值一律用单引号，且一个组只给一个正则。**

lite 受影响的是 **5 个键**（全量是 13 个，因为 lite 删掉了 3 个 `filter` 与 5 个组）：

| 组 | 键与写法 |
|---|---|
| 🇭🇰 香港 | `filter: '香港'` |
| 🇸🇬 新加坡 | `filter: '新加坡'` |
| 🇯🇵 日本 | `filter: '日本'` |
| 🇺🇸 美国 | `filter: '美国'` |
| ⚡ 延迟优选 / 🚧 故障转移 / 🌍 全部节点 | `exclude-filter: '剩余'` |

⚠️ lite 把全量的 `exclude-filter: '：'`（全角冒号）改成了 `'剩余'`：
全角冒号只有用「剩余流量：xxx GB」这种命名风格的那一家机场会命中，
`'剩余'` 是「剩余流量 / 剩余天数 / 距离下次重置剩余」三种写法的共同子串，更通用。

详细机理、13 行对照数据、两条已排除的弯路，见
[`openclash-override-1002.md` 第 〇之前 节](./openclash-override-1002.md)。

### 与仓库其它部分的关系

```
rules/*.yaml                        ← 唯一事实来源（规则、策略组、地区、关键词）
rules/profile-lite.yaml             ← FlClash lite 的裁剪白名单
rules/profile-lite-openclash.yaml   ← 本产物（OpenClash lite）的裁剪白名单
      │
      │  人工/AI 渲染
      ▼
targets/openclash-override-lite-1015.conf   ← 本文件描述的对象（产物）
      │
      ▼
OpenClash → mihomo 内核
```

**改规则要改 `rules/*.yaml` 再重新生成产物，不要直接改产物。**
本产物没有 `@generated` 标记（不像 `.js` 产物那样分段），
但 `rules!` / `rule-providers` / `proxy-groups!` 三段都是**整体重建**的，
直接手改这三段下次重新渲染就会被覆盖。

---

## 二、它做了什么

### 只有三处是「重建」，其余是继承

| # | `[YAML]` 内的键 | 合并算子 | lite 的动作 |
|---|---|---|---|
| 1 | `rules!` | **`!` 整体覆盖** | 重建为 22 条 |
| 2 | `rule-providers` | 默认合并 | 声明 13 本（与 OpenClash 注入的 `oc-cn-domain` 共存） |
| 3 | `proxy-groups!` | **`!` 整体覆盖** | 重建为 11 个 |
| 4 | `dns` / `mode` / `unified-delay` / `tcp-concurrent` / `geodata-mode` | 默认合并 | **与全量逐字相同**，直接继承 |

`rules!` 与 `proxy-groups!` 用 `!`（整体覆盖）而不是默认合并，是**刻意的**：
默认合并只会「加」，删不掉全量留下的组与规则。代价是**它也不会删掉底座里已有的东西**，
所以本模块只对「由覆写模块自己产生的键」负责 —— 底座订阅里没有 `proxy-groups`，
因此覆盖是安全的。

> `rule-providers` 用默认合并（无 `!`）是**必须的**：OpenClash 会往这个键里注入
> 自己的 `oc-cn-domain` 规则集（供 `fake-ip-filter` 与国内域名解析用）。
> 用 `!` 覆盖会把它一并删掉。预期产物里 `rule-providers` 共 **13 + 1 = 14** 本。

### `[General]` 段

全部取自全量 —— v1.1.0 起这一节两边逐字相同。

```
FIND_PROCESS_MODE = off
```

内核默认值。v1.1.0 之前这里曾是 `strict`，唯一原因是要让第 3 段那条
`PROCESS-NAME,tailscaled` 生效；那条规则已在 v1.1.0 删除（原因见第四节第 3 段），
UDP 打洞改由防火墙层在 TPROXY 之前放行，所以这里回到 `off`。

**若以后要重新引入任何 `PROCESS-NAME` 规则，必须同时把这行改成 `strict`** ——
内核默认 `off` 时进程规则会静默不命中，不会报错。

### lite 砍掉了什么（一句话版）

| 维度 | 全量 | lite | 说明 |
|---|---|---|---|
| 分流规则 | 52 | **22** | 删 31 条 |
| 规则集 | 43 | **13** | 删 30 本 |
| 策略组 | 22 | **11** | 删 11 个 |
| 地区组 | 6 | **4** | 删英国、台湾 |

**规则集的削减才是主要收益**（见第五节）；策略组的削减只影响界面长度。

### 空组与落空行为

删除的 11 个组里，`🏠 家宽/原生线路` 在全量上**实测命中 0**（`filter: '家宽'`），
靠 `empty-fallback: DIRECT` 兜底 —— lite 直接不建这个组，语义相同且没有空组。

lite 保留的 4 个地区组都带 `empty-fallback: DIRECT`：某个地区一个节点都没有时该组退化为直连，
**不会导致加载失败，但会让该地区的流量走直连**。切订阅后应确认 4 个地区组都有节点。

---

## 三、策略组清单（11 个）

| 分类 | 数量 | 组名 |
|---|---|---|
| 核心路由 | 4 | `🧭 代理模式` / `⚡ 延迟优选` / `🚧 故障转移` / `🌍 全部节点` |
| 地区组 | 4 | `🇭🇰 香港` / `🇸🇬 新加坡` / `🇯🇵 日本` / `🇺🇸 美国` |
| 服务组 | 2 | `🤖 AI服务` / `⛔ 广告拦截` |
| 默认路由 | 1 | `🛡️ 国内直连` |

### 核心路由

- **`🧭 代理模式`**（`select`）—— 顶层唯一入口，日常只需要碰这一个组。
  选项为 `⚡ 延迟优选` / 4 个地区组 / `🚧 故障转移` / `🌍 全部节点` / `DIRECT`，默认首项是 `⚡ 延迟优选`。
  > ⚠️ lite **删掉了全量里的 `REJECT` 选项**：兜底 `MATCH` 跟随本组，
  > 顶层误选 `REJECT` 会让全部兜底流量被拒（断网级）。同时删掉了 `🇬🇧 英国` / `🇹🇼 台湾` 两个选项
  > （目标组已不存在，留着会导致加载失败）。
- **`⚡ 延迟优选`**（`url-test`，`include-all-proxies: true`，`interval: 1800`）
- **`🚧 故障转移`**（`fallback`）
- **`🌍 全部节点`**（`select`，`include-all-proxies: true`）

后两个与 `⚡ 延迟优选` 一样用 `exclude-filter: '剩余'` 把通知节点排除在外 ——
通知节点（`剩余流量：917.91 GB`）不是线路，参与测速只会误导。

### 地区组（`url-test`，选地区 = 该地区内自动选最低延迟）

| 组 | filter | 全量实测命中（2026-10-02，51 节点） |
|---|---|---|
| 🇭🇰 香港 | `'香港'` | 5 |
| 🇸🇬 新加坡 | `'新加坡'` | 12 |
| 🇯🇵 日本 | `'日本'` | 15 |
| 🇺🇸 美国 | `'美国'` | 12 |

> ⚠️ **命中率是「换订阅必须重核」的东西。** 这组数字来自 2026-10-02 的全量实测，
> 与 lite 的 filter 完全相同，因此仍然适用 —— 但只对**当时那家订阅**适用。
> 换订阅后用 `tools/check-node-match.mjs` 对新节点名核一次。
>
> 已删除的三个 filter 的实测命中（留档，将来要加回时参考）：
> `'英国'` 4、`'台湾'` 1、`'流媒体'` 18、`'[0-9]x'` 18、`'家宽'` 0。

### 服务组（2）

| 组 | 类型 | 谁在用 |
|---|---|---|
| `🤖 AI服务` | `select` | 第 18–20 条（OpenAI / AI_no_ip / Gemini） |
| `⛔ 广告拦截` | `select`，默认 `REJECT` | 第 3–4 条 |

### 默认路由（1）

- **`🛡️ 国内直连`**（`select`，默认 `DIRECT`）—— 第 21 条 `GEOIP,CN` 的目标。

### lite 删掉的 11 个组

| 分类 | 组名 | 删除原因 |
|---|---|---|
| 地区 | `🇬🇧 英国` `🇹🇼 台湾` | 节点少（实测 4 / 1），地区组收窄到 4 个 |
| 线路特性 | `🏠 家宽/原生线路` | 实测命中 0，一直靠 `empty-fallback` 兜底 |
| 线路特性 | `💰 低倍率节点` | 保留可调性不如少一个能点错的组 |
| 线路特性 | `📺 流媒体节点` | 同上 |
| 线路特性 | `📢 订阅信息` | 通知节点没有落地价值 |
| 服务组 | `📁 办公通讯` | 该段 10 条规则已删（见第四节） |
| 服务组 | `🔍 谷歌服务` | 整段删除 |
| 服务组 | `游戏平台` | 整段删除 |
| 服务组 | `📺 大流量通道` | 整段删除，同时去掉 3 个 domainset 大集 |
| 默认路由 | `🌍 兜底代理` | `MATCH` 直投 `🧭 代理模式`，少一跳 |

---

## 四、规则链全表（22 条）

**段号沿用全量产物的编号，跳过的段号（8 / 9 / 10）表示整段已删** ——
这样两边的「第 N 段」始终指同一件事，对着两份文档看不会错位。

| 段 | 条数 | 目标 |
|---|---|---|
| 1 · 免拦截白名单 | 1–2 | `DIRECT` |
| 2 · 广告拦截 | 3–4 | `⛔ 广告拦截` |
| 3 · tailnet 内网 / Tailscale | 5–8 | `DIRECT` |
| 4 · 私有网络与国内直连 | 9–15 | `DIRECT` |
| 5 · 自定义直连 | 16 | `DIRECT`（锁死，不建组） |
| 6 · 自定义代理 | 17 | `🧭 代理模式` |
| 7 · AI 服务 | 18–20 | `🤖 AI服务` |
| ~~8 · 谷歌服务~~ | — | **整段删除（3 条）** |
| ~~9 · 大流量通道~~ | — | **整段删除（7 条）** |
| ~~10 · 游戏平台~~ | — | **整段删除（5 条）** |
| 11 · 单主机 UDP 直连例外 | 21 | `DIRECT` |
| 12 · 兜底 | 22–23 | `🛡️ 国内直连` / `🧭 代理模式` |

### 第 1 段 · 免拦截白名单（1–2）→ `DIRECT`

```
RULE-SET,UnBan,DIRECT
RULE-SET,DirectNoResolve,DIRECT
```

必须最先。误伤广告规则的代价（装不上、登不进）远大于漏放几个广告。**与全量完全相同。**

### 第 2 段 · 广告拦截（3–4）→ `⛔ 广告拦截`

```
RULE-SET,Reject_no_ip,⛔ 广告拦截
RULE-SET,CustomRejectRules,⛔ 广告拦截
```

> ⚠️ **这是 lite 最实质的代价。** 全量这一段的 6 条里，
> `Reject_domainset` / `Reject_no_ip_drop` / `Reject_no_ip_no_drop` / `Reject_ip` 四本都删了，
> 只剩 `Reject_no_ip`（第三方主集）与 `CustomRejectRules`（自托管）。
>
> 丢掉的四本里，`Reject_domainset` 是**十万量级条目**的 domainset 大集，
> 它是体积与更新流量的主要来源 —— 删它也是 lite 提速的主要原因。
> 代价是**漏拦会明显增加**：部分广告域名不再被拦。缓解办法是往自托管的
> `rulesets/OwnREJECTRules.yaml` 里补（见第十一节）。
>
> **不要通过把 `Reject_no_ip` 换成 `Reject_domainset` 来「补回来」** ——
> 那等于把 lite 的主要收益又还回去了。要补就补自托管那份。

### 第 3 段 · tailnet 内网 / Tailscale 域名（5–7）→ `DIRECT`

```
IP-CIDR,100.64.0.0/10,DIRECT,no-resolve
IP-CIDR,100.100.100.100/32,DIRECT,no-resolve
DOMAIN-SUFFIX,ts.net,DIRECT
```

> ⚠️ **这是路由器版与 FlClash 版唯一的规则结构差异**：目标直接是 `DIRECT`，不建策略组。
> tailscaled 是系统服务，tailnet 路由由它自己处理（`ip rule` → `table 52`），mihomo 再插一层只会添乱。
>
> 刚需理由：tailnet 里有 `fnos`(NAS) / `nas6418` / `pve`，homelab 机器之间要互访，走代理就断了。
>
> - **第 5–7 条** 是 tailnet 自身地址：CGNAT 段、MagicDNS 解析器与 `*.ts.net`。
> - ⚠️ **v1.1.0 删掉了原本的第 5 条 `PROCESS-NAME,tailscaled,DIRECT`**：它当时想接住
>   tailscaled 自己发出的 **UDP**（STUN 3478、打洞 41641）—— 发往任意对端 IP、没有域名，
>   默认被兜底代理接走 → P2P 打洞失败只剩中继，而中继都在大陆之外，这就是「访问家里
>   设备绕路国外」的主因。但**这件事在规则层做不到**：OpenClash 的透明代理会先把 UDP
>   收进 mangle 表自己创建的 `openclash` 链，从那一刻起流量已由 mihomo 接管，链内再写
>   任何规则（包括进程规则）都只是给 mihomo 自己看。正确做法是在**接管之前**放行 ——
>   在防火墙 `PREROUTING` / `OUTPUT` 的 `TPROXY` 之前对 Tailscale 目标 `RETURN`，
>   脚本与验证四步见全量文档
>   [`targets/openclash-override-1002.md`](./openclash-override-1002.md) 的「已知问题 10」。
>   因此 `[General]` 的 `FIND_PROCESS_MODE` 也回到内核默认的 `off`。
> - Tailscale 的**服务端域名**（controlplane / login / api / derpN / pkgs / log）不在这里，
>   而是走自托管规则集：[`rulesets/OwnDIRECTRules.yaml`](../rulesets/OwnDIRECTRules.yaml)
>   → provider `CustomDirectRules` → **第 15 条**。放规则集是为了两个产物共用同一份名单。
> - ⚠️ 顺序：域名规则落在第 15 条，晚于第 12 条 `GEOSITE,cn`；段 4 的目标全是 `DIRECT`，
>   两者功能等价，不需要为顺序挪动。
> - ⚠️ 与 FlClash lite 的差异：这里只有 3 条，**没有 `PROCESS-NAME,tailscaled.exe`**
>   —— 路由器是 OpenWrt / Linux，不存在 `.exe`。

### 第 4 段 · 私有网络与国内直连（8–14）→ `DIRECT`

```
GEOSITE,private,DIRECT
GEOIP,private,DIRECT,no-resolve
RULE-SET,MicrosoftCNCDN_no_ip,DIRECT
RULE-SET,AppleCNCDN_no_ip,DIRECT
GEOSITE,cn,DIRECT
RULE-SET,Lan_ip,DIRECT
RULE-SET,Domestic_no_ip,DIRECT
```

> lite 相对全量去掉了 `SteamCN_ip`（8 条变 7 条）。Steam 国区 IP 在 lite 里落到 `MATCH` → 走代理；
> 若发现国区商店变慢，把这条加回段 4 末尾即可。

### 第 5 段 · 自定义直连（15）→ `DIRECT`（锁死，不建组）

```
RULE-SET,CustomDirectRules,DIRECT
```

`CustomDirectRules` 是**自托管**的（`rulesets/OwnDIRECTRules.yaml`），
承载 Tailscale 服务端域名等需要长期维护的直连名单。目标直接是 `DIRECT`，**不建策略组**。

> ⚠️ FlClash 版在段 5 之后还有一段「应用级分流（`PROCESS-NAME`）」，路由器版**不存在**：
> 那条依赖 `PROCESS-NAME`，对 LAN 客户端永不命中（官方源码原话 `Only Works on Routerself`）。
> 路由器版不做按设备分流 —— homelab 机器的流量特征由服务组覆盖。

### 第 6 段 · 自定义代理（16）→ `🧭 代理模式`

```
RULE-SET,CustomProxyRules,🧭 代理模式
```

自托管（`rulesets/OwnPROXYRules.yaml`），放**必须走代理**的域名。

> ⚠️ 全量产物这一条是「段 6 · 办公通讯与开发工具链」的**最后一条**，目标是 `📁 办公通讯`。
> lite 删掉了 `📁 办公通讯` 组，改投顶层 `🧭 代理模式`（默认 `⚡ 延迟优选`）。
> **该组默认首项就是 `🧭 代理模式`，所以这个改动不改变当前行为**；失去的是可调性：
> 「把 `📁 办公通讯` 切成 `DIRECT` 让 docker pull / git clone 直连」这个动作不再可用。
> 全量该段另外 10 条（Github / Docker / Npm / Telegram_ip / Microsoft_no_ip / OneDrive /
> Dropbox / Twitter / Notion_ip / Figma_ip）已删，这些流量落到 `MATCH` → **仍走代理**。

### 第 7 段 · AI 服务（17–19）→ `🤖 AI服务`

```
RULE-SET,OpenAI,🤖 AI服务
RULE-SET,AI_no_ip,🤖 AI服务
RULE-SET,Gemini,🤖 AI服务
```

**与全量完全相同。** 保留独立的 `🤖 AI服务` 组是有意的：
AI 服务对出口地区敏感，需要能单独换一个组而不影响其他流量。

### ~~第 8 / 9 / 10 段~~ · 已整段删除（15 条）

全量段 8（谷歌服务，3 条）、段 9（大流量通道，7 条）、段 10（游戏平台，5 条）在 lite 中不存在。
这些流量落到 `MATCH` → **仍走代理**，只失去「单独换出口」的可调性。

> ⚠️ 段 9 含 **3 个 domainset 大集**，是体积与更新流量的主要来源 ——
> 删它同时是 lite 提速的另一个主要原因。
> 代价：下载类流量回落到 `MATCH` 走代理，可能跑满代理带宽。

### 第 11 段 · 单主机 UDP 直连例外（20）→ `DIRECT`

```
AND,((NETWORK,udp),(SRC-IP-CIDR,192.168.31.7/32)),DIRECT
```

只为 `192.168.31.7`（LAN 上的常用终端）加：它自己的 Tailscale UDP 打洞
（STUN 3478、WireGuard/DISCO 发往对端公网 IP）目标与端口都不固定，
按域名和单端口都抓不全，所以整机 UDP 放行。

- 为什么不能像路由器那样用进程规则：LAN 客户端的进程在路由器上查不到，
  只能用「来源 IP」近似。路由器自身的 UDP 打洞改由防火墙层在 TPROXY 之前放行
  （见段 3 与全量文档「已知问题 10」），不靠这条。
- ⚠️ **代价**：该主机的**所有** UDP 都直连 —— QUIC/HTTP3、游戏、其他 UDP 全部绕开代理，
  这个主机不再有「防泄露」可言。若哪天想堵住 QUIC，在本条之前加：

  ```
  AND,((NETWORK,udp),(SRC-IP-CIDR,192.168.31.7/32),(DST-PORT,443)),REJECT
  ```

  （QUIC 被拒后浏览器会回落到 TCP 走代理）；不需要这条例外时整段删掉。
- ⚠️ **位置**：必须排在兜底之前，因为 `GEOIP,CN` 与 `MATCH` 必须是最后两条；
  对该主机发往国内 IP 的 UDP 也先命中这里，结果与 `GEOIP,CN` 一致。
- ⚠️ 这是 **OpenClash 独有的一段**，FlClash lite 没有对应内容。lite 保留它，
  理由见 [`rules/profile-lite-openclash.yaml`](../rules/profile-lite-openclash.yaml) 的 `sections.udp-exception`。

### 第 12 段 · 兜底（21–22）

```
GEOIP,CN,🛡️ 国内直连
MATCH,🧭 代理模式
```

这两条必须是最后两条，提前会让后面所有规则永不生效。

> ⚠️ 全量的 `MATCH` 投 `🌍 兜底代理`（一个默认跟随 `🧭 代理模式` 的 `select`）；
> lite 删掉中间组，直接指向 `🧭 代理模式`。理由与 FlClash 侧一致：多一层 `select` 只是多一个能点错的地方。

### 带 `no-resolve` 的规则

```
IP-CIDR,100.64.0.0/10,DIRECT,no-resolve      （第 5 条）
IP-CIDR,100.100.100.100/32,DIRECT,no-resolve （第 6 条）
GEOIP,private,DIRECT,no-resolve              （第 9 条）
```

`no-resolve` 表示**命中不了就跳过、不触发出站 DNS 查询**。
这三条的目标都是 `DIRECT` 且都是「本地/内网」性质，加上它可以避免
「为了判断一条内网 IP 规则而先去解析一个外网域名」这种自伤行为。

⚠️ **新增 `IP-CIDR` 类规则时，如果目标是 `DIRECT` 或内网，务必带 `no-resolve`**；
漏掉会让解析发生在规则判定之前，可能出现 `DNS 解析绕路 + 判定结果错误`。

### 相比全量少掉的 30 条规则

| 段 | 删掉的条数 | 具体 |
|---|---|---|
| 2 · 广告拦截 | 4 | `Reject_domainset` / `Reject_no_ip_drop` / `Reject_no_ip_no_drop` / `Reject_ip` |
| 4 · 国内直连 | 1 | `SteamCN_ip` |
| 6 · 办公通讯 | 10 | Github / Docker / Npm / Telegram_ip / Microsoft_no_ip / OneDrive / Dropbox / Twitter / Notion_ip / Figma_ip |
| 8 · 谷歌服务 | 3 | 整段 |
| 9 · 大流量通道 | 7 | 整段 |
| 10 · 游戏平台 | 5 | 整段 |
| **合计** | **30** | 53 → 23 |

---

## 五、规则集清单（13 个）

| # | 名称 | 目标 | 来源 | 说明 |
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
> OpenClash 按 `interval: 86400` 自动拉取，**不用重新生成产物、不用重传模块**。

### 为什么规则集数量才是 lite 的主要收益

两个维度的影响完全不同：

| 维度 | 影响 | lite 的削减 |
|---|---|---|
| 策略组数量 | **只影响界面**（分组列表长度） | 22 → 11 |
| 规则集条目数 | **影响启动解析、常驻内存、更新流量** | 43 → 13 |

三个 domainset 大集（`Reject_domainset` 等）单本就有十万量级条目，是路由器内存与更新流量的主要来源 ——
lite 全部不挂，这是单项最大的收益，代价是漏拦变多（见第九节）。

> 路由器是 7×24 常驻设备，内存比手机紧张得多，这个削减在路由器上的收益**大于** FlClash 端。

### `format` 与 `behavior` 为什么必须声明准确

这两项声明错了**不会报错**，而是整份规则集**静默空载**：

- `Reject_domainset` 这类 domainset 的上游是 `+.域名` 简写格式，必须 `behavior: domain`；
  写成 `classical` 会整份解析失败并丢弃 —— 表现为「广告拦截实际为空」（lite 未使用该集）；
- `applications` 的 URL 后缀是 `.txt` 但内容是 YAML，必须 `format: yaml`（lite 未使用该集）。

自检办法：改完规则集源后，看 OpenClash 日志里该 provider 的 `ruleCount` 是否为 0。

### lite 删掉的 30 本规则集

段 2 的 4 本广告类、段 4 的 1 本 Steam、段 6 的 10 本办公通讯类、
段 8/9/10 的 15 本（含 3 个 domainset 大集）。
**删除清单与理由逐条记录在
[`rules/profile-lite-openclash.yaml`](../rules/profile-lite-openclash.yaml) 的 `providers.drop` 一节**，
将来要加回某一本时先看那里写的「为什么删」。

---

## 六、DNS 与网络层

**本产物这一层与全量产物逐字相同，没有任何 lite 特有的改动。** 要点复述如下（细节见全量文档第六节）：

| 项 | 值 | 为什么 |
|---|---|---|
| `dns.respect-rules` | `true` | 国际 DoH 连接必须走代理才能穿出隧道（实测 `dns.google` 317ms 返回 200） |
| `dns.fallback` | **已删** | 订阅自带的 `[1.1.1.1, 8.8.8.8]` 从大陆直连必被污染/超时 |
| `dns.fallback-filter` | **已删** | 与 `fallback` 配套，留着会让 `geosite:gfw` 的查询全撞在已删的 fallback 上 |
| `dns.nameserver` | 国内 DoH | 实测 alidns 175ms / doh.pub 189ms |
| `dns.proxy-server-nameserver` | 国内 DoH | 节点域名解析单独隔离，被污染就永远连不上 |
| `dns.nameserver-policy` | 国际 DoH | `'geosite:gfw,geolocation-!cn'` → `dns.google` / `cloudflare-dns.com` |
| `dns.fake-ip-filter+` | 22 条 | `+` 追加而非替换，保留 OpenClash 注入的 `rule-set:oc-cn-domain` |
| `dns.listen` | **不碰** | 必须与 dnsmasq 的转发配置对得上 |
| IPv6 | **本文件不解决** | 是系统层问题，见全量文档第九节 |
| `ENABLE_META_SNIFFER(_PURE_IP)` | `1` / `1` | homelab 机器之间不少是直连 IP 的（NAS 挂载、数据库直连），嗅探把域名捞回来 |

---

## 七、怎么确认生效 / 出问题怎么定位

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

**预期：`22 / 11 / 14 / true / 0.0.0.0:7874 / nil`**

> 与全量对照：全量是 `52 / 22 / 44 / true / 0.0.0.0:7874 / nil`。
> `rule-providers` 是 **13 + 1**（OpenClash 注入的 `oc-cn-domain`）= 14。
> `fallback` 必须是 `nil`（已删）。

### 看编译产物（最快的自检）

```sh
grep -n 'net-routing artifact' /tmp/yaml_overwrite.sh   # 应输出：1015 lite v1.1.0
grep -c '^  - "' /tmp/yaml_overwrite.sh                 # 规则条数相关
cat /tmp/yaml_overwrite.sh | head -50
```

> ⚠️ `/tmp/yaml_overwrite.sh` **用完即删**（OpenClash 收尾会 `rm -rf /tmp/yaml_*`），
> 事后看不到，要看只能在重启过程中抓。日志 `/tmp/openclash.log` 会被 watchdog 清空，
> 「日志里搜不到 X」**不能**推出「X 没执行」。详见全量文档第七节。

### 校验 5 个 filter 有没有被吃掉（本产物最容易出的问题）

```sh
ruby -ryaml -e 'd=YAML.load_file(ARGV[0]);
  (d["proxy-groups"]||[]).each{|g|
    v=g["filter"]||g["exclude-filter"]
    puts format("  %-14s %s", g["name"].to_s, v ? v : "（无筛选 ← 不对）")}' /etc/openclash/良心云.yaml
```

**预期：7 个组有筛选值**（4 个地区组 + `⚡ 延迟优选` / `🚧 故障转移` / `🌍 全部节点`），
其余 4 个用显式 `proxies:` 列表所以本来就该没有。

出现「（无筛选 ← 不对）」就是踩了第一节那个 `eval` 坑。
面板上的信号更直接：4 个地区组应显示 `5/51`、`12/51` 这种数；
**4 个地区组全部显示 `35/51` 且选中的是同一个节点，就是筛选没生效。**

### 确认引用没有指向已删除的组

这是删除 11 个组之后**最容易出加载失败的原因**，报错是
`ProxyGroup not found` / `ProxyGroup loop`：

```sh
grep -iE 'ProxyGroup|not found|loop' /tmp/openclash.log | tail -20
```

> 本产物与 [`rules/profile-lite-openclash.yaml`](../rules/profile-lite-openclash.yaml)
> 的 `reference_fixups` 一节已对齐，所有指向已删组的引用都清理过；
> **手工改本文件后必须再核一遍那一节。**

### 逐条打印规则链

```sh
ruby -ryaml -e 'd=YAML.load_file(ARGV[0]);
  (d["rules"]||[]).each_with_index{|r,i| puts format("%2d  %s", i+1, r)}' /etc/openclash/良心云.yaml
```

**预期：22 条，第 21 条是 `GEOIP,CN,🛡️ 国内直连`，第 22 条是 `MATCH,🧭 代理模式`。**
这两条必须是最后两条。

### 验证 Tailscale 这一段（第 3 段 3 条）

先确认规则进了产物：

```sh
ruby -ryaml -e 'd=YAML.load_file(ARGV[0]);
  (d["rules"]||[])[0,11].each_with_index{|r,i| puts format("%2d  %s", i+1, r)}' /etc/openclash/良心云.yaml
```

预期第 5–7 条是 CGNAT 段、MagicDNS 解析器与 `*.ts.net`；第 15 条应是
`RULE-SET,CustomDirectRules,DIRECT`。

再确认 **UDP 有没有真的直连** —— v1.1.0 起这件事由防火墙层脚本负责，不在规则链里：

```sh
tailscale netcheck              # 看 UDP: true
tailscale status --peers        # 对端应显示 direct，而不是 relay "xxx"
tailscale ping <对端主机名>     # 直连：pong ... via <IP>:41641；中继：via DERP(...)
```

> ⚠️ **这三条必须实测**。`netcheck` 里 `UDP: false`、或 `tailscale ping` 一直走
> `via DERP(...)`，说明防火墙层那几条 `RETURN` 没生效 —— 脚本与排查四步见全量文档
> [`targets/openclash-override-1002.md`](./openclash-override-1002.md) 的「已知问题 10」。
> 段 3 剩下的 3 条只管 TCP 与域名，不受影响。
>
> LAN 客户端那一侧（`192.168.31.7`）是**另一条独立的规则**（第 20 条），同样未实测。
> 详见全量文档第七节的「验证 Tailscale 这一段」。

### 手动校验配置合法性

```sh
SAFE_PATHS=/etc/openclash:/usr/share/openclash \
  /etc/openclash/core/clash_meta -t -d /etc/openclash -f /etc/openclash/良心云.yaml
```

> **两个参数都不能省。**
> `-d /etc/openclash`：不带 home 目录找不到已下载的 geo 库，会误报失败；
> `SAFE_PATHS`：OpenClash 写的 `external-ui` 在 home 目录之外，不给会报 `path is not subpath of home directory`。

预期结尾：`configuration file ... test is successful`，退出码 0。

---

## 八、出问题怎么恢复

**最快的办法** —— LuCI 覆写模块页面把本模块的「启用」关掉，重启 OpenClash。

```
http://192.168.31.1/cgi-bin/luci/admin/services/openclash
```

**要回到全量行为**：停用本模块 → 启用 `openclash-override-1002.conf` → 重启。
两个模块**不要同时启用**（见第一节）。

**要回到原厂状态**（丢弃全部覆写模块）：

```
http://<路由器IP>/cgi-bin/luci/admin/services/openclash/restore
```

> 这个入口会清掉脚本、DNS、fake-ip-filter，**所有覆写模块都会失效**（不只是本文件）。
> 恢复后需要重新上传并启用你想用的那一个。

---

## 九、已知问题

### 1. 🔴 广告拦截覆盖面明显窄于全量

删掉了 4 本广告规则集（含十万量级的 `Reject_domainset`），**这是 lite 已知的最实质代价**。
表现为部分广告域名不再被拦。缓解办法：把常用的补充域名写进自托管的
[`rulesets/OwnREJECTRules.yaml`](../rulesets/OwnREJECTRules.yaml)（不用重新生成产物）。

### 2. 策略组名与规则目标组之间没有自动校验

删组、改名、手改规则链都可能留下悬空引用，而**报错只在启动日志里**，
表现为整份配置加载失败。删除任何组之后，必须同步清理
`🧭 代理模式` 的 `proxies` 列表、规则链目标、以及其它组的 `proxies` 列表。

### 3. 依赖 GitHub raw 的规则集

13 本里有 10 本来自 `raw.githubusercontent.com`（大陆直连经常超时）。
`GITHUB_ADDRESS_MOD = https://cdn.jsdelivr.net/` 会把 URL 重写成 CDN 地址，但 CDN 也可能失效。
最坏情况是某些规则集拉不到、静默空载 —— 分流退化，但配置仍能加载。

### 4. `filter` 只能是单正则，换订阅必须重核命中率

一个组只能给一个模式（不能用 `|` 做 alternation）。换订阅后
`'香港'` / `'新加坡'` / `'日本'` / `'美国'` 四个词的命中率可能变化，
用 `tools/check-node-match.mjs` 核一次。

### 5. Tailscale 的 UDP 直连：v1.1.0 起改用防火墙层脚本（**尚未实测**）

原先靠第 3 段第 5 条 `PROCESS-NAME,tailscaled`（配 `FIND_PROCESS_MODE = strict`）让
tailscaled 自己发出的 UDP 直连。v1.1.0 已删除该条 —— **它在规则层做不到**：UDP 进入
mangle 表的 `openclash` 链时流量已被 mihomo 接管，链内规则只是给 mihomo 自己看。
替代方案是在 `PREROUTING` / `OUTPUT` 的 `TPROXY` **之前** `RETURN`，脚本与排查四步见
全量文档 [`openclash-override-1002.md`](./openclash-override-1002.md) 的「已知问题 10」。
**那个脚本尚未在设备上实测**；第 20 条（`192.168.31.7` 的整机 UDP）同样未实测。
两者的验证步骤都在第七节，验不过各自删掉即可，其余规则不受影响。

### 6. 没有自动化测试

本产物没有 lint / 生成期校验。改动后至少跑一遍第七节的
「验证最终配置」（`22 / 11 / 14`）与「校验 5 个 filter」。

### 7. 覆写模块是从 GitHub 仓库拉取的

`git push` 等于一次生产部署。**本文件没有灰度机制**，改完推上去、
下次 OpenClash 拉取覆写模块时就会生效。

---

## 十、与全量产物的差异（取舍记录）

### 被移除的 11 个组与 30 条规则，以及代价

| 移除项 | 代价 | 是否可恢复 |
|---|---|---|
| 4 本广告规则集 | 漏拦增加（**最实质**） | 往自托管 `OwnREJECTRules.yaml` 补 |
| `🇬🇧 英国` / `🇹🇼 台湾` | 无法按这两个地区单独出口 | 加回组 + 加回 `🧭 代理模式` 选项 |
| `💰 低倍率节点` | 无法一键只选低倍率节点 | 加回组（filter `'[0-9]x'`，实测 18） |
| `📺 流媒体节点` | 无法按「流媒体解锁」筛节点 | 加回组（filter `'流媒体'`，实测 18） |
| `📢 订阅信息` | 通知节点不再有落脚组（仅此） | 无实际收益，不建议加回 |
| `🏠 家宽/原生线路` | 无（全量实测命中 0） | 不建议加回 |
| `📁 办公通讯` | 无法让 docker/git 一键直连 | 该段 10 条规则需一并加回 |
| `🔍 谷歌服务` / `游戏平台` / `📺 大流量通道` | 无法按服务单独换出口 | 整段加回（共 15 条 + 若干大集） |
| `🌍 兜底代理` | 无（少一跳，行为相同） | 不建议加回 |

**所有流量都仍有出口**：删掉的规则命中的流量落到 `MATCH` → `🧭 代理模式`，
只是失去了「单独换出口 / 单独直连」的**可调性**，不是分流失效。

### 保留的关键决定

| 决定 | 理由 |
|---|---|
| 保留 `🤖 AI服务` 组 | AI 服务对出口地区敏感，必须能单独换 |
| 保留 `🛡️ 国内直连` 组 | 需要能临时把国内流量也送进代理排查问题 |
| 保留第 11 段（单主机 UDP 例外） | OpenClash 独有，删了会影响 `192.168.31.7` 的 tailnet 打洞 |
| 保留自托管的 3 本规则集 | 是「不重新生成产物就能改规则」的唯一通道 |
| 删除 `REJECT` 顶层选项 | 防止顶层误选导致断网级事故 |
| `rule-providers` 不用 `!` | 必须保留 OpenClash 注入的 `oc-cn-domain` |

### 与 FlClash lite 裁剪范围的两处**有意**不同

| | FlClash lite | OpenClash lite | 为什么不同 |
|---|---|---|---|
| 「🌐 其他地区」组 | 有 | **没有** | OpenClash 的 `filter` 单正则做不出「未命中四地区」的排除式匹配 |
| 段 3 Tailscale | 5 条（含 `.exe` 进程） | **3 条** | 路由器是 Linux 不存在 `.exe`；v1.1.0 又删了进程规则（见全量文档「已知问题 10」） |
| 段 5 应用级分流 | 有（`PROCESS-NAME`） | **没有** | 路由器上对 LAN 客户端永不命中 |

**这些差异是刻意的，不要「顺手统一」。**

---

## 十一、常见调整入口

| 想做什么 | 改哪里 | 要不要重新生成产物 |
|---|---|---|
| 加一个直连域名 | `rulesets/OwnDIRECTRules.yaml` | **不用**（等自动拉取） |
| 加一个拦截域名 | `rulesets/OwnREJECTRules.yaml` | **不用** |
| 加一个必须走代理的域名 | `rulesets/OwnPROXYRules.yaml` | **不用** |
| 换某个规则集的源 | 本文件 `rule-providers` 段 | **要**（重传模块） |
| 把 Steam 国区加回直连 | 本文件第 4 段末尾 + `SteamCN_ip` provider | **要** |
| 让 docker / git 直连 | 加回 `📁 办公通讯` 组 + 该段 10 条规则 | **要** |
| 关掉 Tailscale UDP 直连 | 删掉防火墙脚本里的那几条 `RETURN`（路由器本地文件，见全量文档「已知问题 10」） | **不用**（改本地文件后重启 OpenClash） |
| 删掉单主机 UDP 例外 | 删整段 11 | **要** |
| 堵住 `192.168.31.7` 的 QUIC | 在第 20 条前加一条 `AND,...,DST-PORT,443,REJECT` | **要** |
| 调整 CLAUDE/代理模式默认项 | 本文件 `🧭 代理模式` 的 `proxies` 顺序 | **要** |
| 改地区分类词 | 本文件 4 个地区组的 `filter`（**保持单引号 + 单正则**） | **要** |
| 调整裁剪范围本身 | [`rules/profile-lite-openclash.yaml`](../rules/profile-lite-openclash.yaml) | 按需 |

> 改完本文件后：递增头部 `内容版本` → 更新 `net-routing artifact` 版本标记 →
> 重传模块 → 重启 → 跑第七节的验证。

---

## 十二、免责与来源

- 本文描述的是**本仓库自己维护**的覆写模块，不是 OpenClash 官方组件。
- 第三方规则集版权归各自作者（ACL4SSR、blackmatrix7 等）。
- 自托管规则集（`rulesets/Own*.yaml`）由本仓库维护。
- 覆写模块机制、`eval` 硬约束、编译产物与恢复入口的原始出处是
  [`openclash-override-1002.md`](./openclash-override-1002.md)（2026-10-02 事故复盘）与
  [`docs/openclash.md`](../docs/openclash.md)（路由器侧实测）。
