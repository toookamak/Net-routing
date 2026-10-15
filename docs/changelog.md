# 版本历史

本文件从 2026-10-01 起记录。版本号自 **v1.0.0** 起算。
前身单文件脚本 `TK_ClashRuleDIY` 的 v9 ~ v19 属于旧版本序列，不在本项目版本序列内。

---

## v1.0.0（2026-10-01）· 起始基线

### 项目形态

个人用的 FlClash 覆写脚本，由以下四部分组成：

```
rules/       规则定义（唯一事实来源，7 个 YAML）
rulesets/    个人规则（3 个 YAML，客户端自动拉取）
targets/     flclash-override-1001.js —— 粘进 FlClash 的自包含成品
             flclash-override-1001.md —— 产物的功能与规则说明
docs/        设计说明 / 规则集来源清单 / 本文件
```

**没有构建脚本，没有自动化测试，不需要 Node.js。**
`rules/*.yaml` 由 AI 读取后直接生成 `targets/flclash-override-1001.js`。

### 关键设计

- **两类改动的生效路径不同**
  - 改 `rulesets/*.yaml` → 提交推送即可，客户端按 `interval: 86400` 自动拉取，**不需要重新生成产物**
  - 改 `rules/*.yaml` → 必须让 AI 重新生成 `targets/flclash-override-1001.js`，否则不生效
- **三个自定义规则集用 YAML 而非 text 格式**
  `text` 格式下一行即一条规则，加注释是否被内核接受无可靠保证，写坏会导致
  provider 静默空载。YAML + `payload` 数组原生支持注释，可承载填写说明。
- **`payload` 必须写成 `[]`**
  只写 `payload:` 会解析成 `null` 而非空数组，内核会拒绝加载。

---

## v1.0.1（2026-10-01）

### 新增规则集

- **`Twitter`（X）纳入「📁 办公通讯」** —— 上游取 blackmatrix7/ios_rule_script：

  ```
  https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Twitter/Twitter.yaml
  ```

  `format: yaml` / `behavior: classical` / `interval: 172800`，落盘 `./ruleset/toookamak/Twitter.yaml`。
  内容共 33 条：26 条 `DOMAIN-SUFFIX`（含 `x.com`、`twitter.com`、`twimg.com`、`twvid.com`、
  `t.co`、`tweetdeck.com`、`vine.co` 等）、1 条 `DOMAIN-KEYWORD,twitter`、6 条 `IP-CIDR`。
  `twimg.com` 后缀覆盖 `pbs.twimg.com` / `abs.twimg.com` / `video.twimg.com`，即图片与视频 CDN。

  此前的现象是 X 相关域名没有专属规则，全部落到第 53 条 `MATCH` 的「🌍 兜底代理」；
  纳入办公通讯后，可在「📁 办公通讯」里单独指定出口，便于给 X 挑节点。

### 规则顺序

`rules/priorities.yaml` 的 `office` 段在 `Notion_ip` 之后、`Github` 之前插入 `Twitter`：

```yaml
- Figma_ip
- Notion_ip
- Twitter      # 新增
- Github
```

Figma 与 Notion 的规则**本次未新增** —— 它们早在 v1.0.0 基线时就已在 `office` 段内
（`rules/providers.yaml` 的 `Figma_ip` / `Notion_ip` 与 `priorities.yaml` 第 66–67 行）。
本次只是确认它们的目标组仍然是「📁 办公通讯」，未做改动。

### 连带更新

规则总数 53 → **54**，规则集总数 45 → **46**（远程 44 → 45，内嵌 1 不变）。
同步更新了 `README.md`、`targets/flclash-override-1001.md`（含规则链全表重新编号）、
`docs/design.md`、`docs/ruleset-sources.md`。

产物头部内容版本 v1.0.0 → **v1.0.1**，作为本次改动的确认标记。

> 本次只改 `rules/*.yaml` 与产物，**未改任何 `rulesets/*.yaml`**，
> 因此自托管三个规则集的 404 状态与本次改动无关。

---

## 本次整理（并入 v1.0.0 基线）

### 版本号重置

- 产物头部版本从继承来的 **v19.0.0 重置为 v1.0.0**，作为项目起始基线重新计数。
- 移除产物头部 v9.0.1 ~ v19.0.0 共 8 段历史变更说明。版本历史归入本文件，
  产物里只保留「当前是什么形态 + 为什么这么写」。
- 清理散落在逻辑段内的 12 处 `vXX.0.0：` 版本前缀注释，改写为陈述事实与理由
  （例如 `v19.0.0：关闭 IPv6` → 直接说明关闭 IPv6 的原因）。

### 重命名

- `targets/flclash.js` → **`targets/flclash-override-1001.js`**
  原名只说明了目标客户端，未说明文件类型（覆写脚本）。改名后与 `docs/`、
  `rules/` 的语义一致：一眼能看出这是「给 FlClash 用的覆写脚本成品」。
  末尾 `-1001` 是**日期大版本**（2026-10-01 立项），详见下文「版本约定」。
- 日志前缀 `[TK RuleDIY]` → **`[net-routing]`**，与仓库名对齐（覆盖 debug / error / warn 三处）。
- 新增 `targets/flclash-override-1001.md` —— 产物的功能与规则说明（53 条规则全表、
  21 个策略组清单、45 个规则集来源、硬性约束、常见调整入口、已知问题）。

> 落盘目录 `./ruleset/toookamak/` **保持不变**。该目录名是前身脚本作者的 GitHub 用户名，
> 确实与本仓库无关，但它是 `rules/providers.yaml` 声明的值。只改产物而不改 YAML
> 会让「产物 == 事实来源」这条不变量失效。若要改名，须**同时**改
> `rules/providers.yaml` 与产物两处。

### 版本约定

产物文件名末尾的数字是**大版本**，取立项当天的日期：`flclash-override-1001.js` = 1001 → 2026-10-01。

| 改动类型 | 处理方式 |
|---|---|
| 加规则、调顺序、改注释、修 bug、调参数 | **直接改当前文件，文件名不变** |
| 重大结构调整（模块拆分、入口签名改变、策略组结构重做、规则链整体重排） | 以**当天日期**另存为新大版本，旧文件保留便于回溯 |

配套说明文档同版本改名。文件内的 `vX.Y.Z` 是内容版本，与文件名大版本是两回事，不要混用。

### 实际行为修复

- **修复 rule-provider 的 `interval` 被忽略。**
  `createRuleProviders()` 原先对所有 provider 硬写
  `CONFIG_MANAGER.UPDATE_INTERVALS.DEFAULT`（172800），完全忽略 `rules/providers.yaml`
  中逐条声明的 `interval`，再手工补一个 `applications` 覆盖块。
  结果：`CustomProxyRules` / `CustomDirectRules` / `CustomRejectRules`
  声明的 24 小时被静默改成 48 小时，与 README 的说法不符。
  改为 `config.interval || DEFAULT`，并补齐 `RULE_PROVIDER_DEFINITIONS` 中每条的
  `interval` 字段，删除手工覆盖块 —— `providers.yaml` 重新成为唯一来源。
  唯一的行为变化：三个自托管规则集从 48 小时变回声明的 24 小时。

### 死代码清理

产物中以下内容定义后从未被引用，逐一核实后删除：

| 删除项 | 说明 |
|---|---|
| `ACLS_GOOGLEFCM` / `ACLS_TELEGRAM` / `ACLS_UNBAN` | 「共享常量」在规则集定义改为 YAML 生成后被架空 |
| `BM_DIRECT` / `SUKKA_APPLE_CDN` / `SUKKA_MICROSOFT_CDN` | 同上 |
| `GAME_RULE_SETS` | 规则链直接写字符串，未引用该表 |
| `CONFIG_MANAGER.GROUP_CATEGORY` | 赋值后从未读取 |
| `CONFIG_MANAGER.UPDATE_INTERVALS.CRITICAL` / `.STATIC` | `.STATIC` 随 applications 覆盖块一起失效 |
| `CONFIG_MANAGER.SPEED_TEST.MAX_FAILED_TIMES` | 仅被已废弃的 load-balance 分支使用 |
| `ProxyGroupBuilder` 的 `load-balance` 分支 | 负载均衡组早已移除，分支成为死路 |
| `CACHE.availableRegions` / `.residentialProxies` / `.lowRateProxies` | 只写不读 |
| `RegexCache.buildExclude()` | 无调用点 |
| `IconManager.ICONS` 中 6 个未引用条目 | `CLOUD` `VIDEO` `MICROSOFT` `TRACKING` `CUSTOM_PROXY` `CUSTOM_DIRECT` |

> 沿用本项目既有政策：删除误导性的死配置，不留「看起来能配、实际不生效」的开关。

### 注释修正

- `tun.mtu` 上方「修复前遗留：device 是 mihomo 内部保留名」与 `mtu` 无关，属残留错位注释，已删除。
- `overwriteRules` 上方重复的两段 JSDoc，删除前一段。
- 日志落盘的 provider 路径自检此前会把 inline 类型（无 `path`）计入，已加 `cfg.path` 判空。

### 文档同步

- `docs/design.md` —— 清除全部指向**已不存在**的构建脚本的描述
  （`build.js` / `template.js` / `check-sources.js` / `regression.js` / `fuzz.js` /
  `test/validate.js`）。改为如实说明「无构建脚本、无自动校验」及其代价。
- `docs/ruleset-sources.md` —— 移除「由 `check-sources.js` 自动生成」的失效说明。
- `README.md` —— 文件名、目录结构、产物说明、告警文本同步更新。

### 数量订正

- 策略组满配值 **20 → 21**（实测枚举：4 核心 + 1 Tailscale + 5 地区
  + 2 特性 + 1 通知 + 5 服务 + 1 大流量 + 2 默认路由）。README / 本文件原为 20。
- 规则数 53、规则集 45、含 `no-resolve` 规则 3 条 —— 经实际运行核对，均无误。

### 当前规模

| 项 | 数量 |
|---|---|
| 分流规则 | 53 |
| 规则集 provider | 45（含 3 个自托管 + 1 个内嵌） |
| 策略组 | 最多 21（随订阅节点动态增减） |
| 带 `no-resolve` 的规则 | 3 |

### 已知遗留

- `Telegram_ip`/`Telegram_no_ip` 与 `GoogleFCM_ip`/`GoogleFCM_no_ip`
  各自共用同一 `path`，运行时会有「多个 provider 共用同一路径」告警
- 家宽 / 低倍率节点不进入地区组（`classifyNodes` 中 `if (!isSpecial)`），
  继承自原单文件脚本的既有行为
- 改策略组名没有任何自动校验，组名同时出现在 `STRATEGY_NAMES`、
  `RULE_PRIORITIES` 和各 `build*Groups()` 里，需人工确认三处同步
- `rulesets/*.yaml` 没有本地前置校验（YAML 语法、`payload` 类型、规则格式），
  错误只能等推送后在客户端侧暴露

### 出处

前身是单文件覆写脚本 `TK_ClashRuleDIY.js`。
规则内容来自 ACL4SSR、blackmatrix7、RealSeek、Loyalsoldier、SukkaW 等第三方项目。

---

## 文档补充：客户端环境（2026-10-02）

**本次不涉及产物与规则层变更，产物内容版本保持 v1.0.1。**

### 新增 `docs/clients.md`

补记本项目面向的客户端清单 —— **这是此前文档的空白**：
README 与设计说明此前只提 FlClash，未记录路由器侧实际在用的 OpenClash。

- **客户端清单** —— OpenClash（路由器 / OpenWrt）、FlClash（Windows / Android），含项目地址
- **DNS 行为实测结论相反** —— FlClash 无法把 DNS 查询送进代理（`respect-rules: true` 无效），
  OpenClash + 较新 mihomo 内核实测国际 DoH 经代理可达。
  强调这是**客户端限制、不是 mihomo 通病**，排查前先确认用的是哪个客户端
- **覆写机制执行顺序相反** —— FlClash 是「产物脚本 → 客户端覆写」，**客户端赢**；
  OpenClash 的 `openclash_custom_overwrite.sh` 官方注释写明在客户端自身脚本**之后**执行，
  **自定义覆写赢**。同时记录 OpenClash 覆写可用的 `ruby_*` 辅助函数清单
- **顺带重申与 Clash Verge Rev 的「合并 / 替换」不是一回事** —— 两者都没有这个概念
- **待验证事项** —— 只读探针 `test/openclash-probe.sh` 的用法，以及适配前待确认的 5 条：
  provider `path` 是否重映射、TUN / IPv6 三层防护、「区域绕过 = 大陆」的实现层次、
  `PROCESS-NAME` 行为、Tailscale 策略路由

### 连带更新

- `README.md` —— 目录结构补 `docs/clients.md`；「当前能力」注明路由器侧尚无产物
- `docs/design.md` —— 第九节补「目标客户端的实际状态」表与指向 `docs/clients.md` 的链接；
  第八节订正「项目没有 `test/` 目录」这一失效描述（`test/` 下实为 OpenClash 排查脚本）

---

## lite 轻量产物（2026-10-14）

### 新增产物 `targets/flclash-override-lite-1014.js`

同客户端（FlClash）的第二个产物：**23 条分流规则 / 13 个规则集 / 12 个策略组上界**
（全量：54 / 46 / 23）。骨架取自 `flclash-override-1001.js`（内容版本 v1.1.0），
按新增的裁剪白名单渲染，产物内容版本 **v1.0.0**。

**动机**：全量产物的分流策略过多，日常只想要「能用、稳、少选项」。
两个维度的收益不同 —— 策略组数量只影响界面，**规则集条目数才影响启动解析 / 常驻内存 / 更新流量**，
所以裁剪重点放在规则集上（46 → 13）。

### 新增 `rules/profile-lite.yaml`（裁剪白名单）

声明 lite 与全量的全部差异：保留的规则段与目标组、删除的规则集（32 本 http + 内嵌 `Npm`）、
保留的策略组、地区白名单、「🧭 代理模式」是否内联节点、以及必须与全量逐字一致的部分。

**为什么用白名单**：产物是渲染结果，手改会与 `rules/` 漂移 —— 全量产物的 tailscale 段
就漏同步过两条域名。白名单把差异集中到一处，产物可重放。

### 相对全量的主要裁剪

| 类别 | 省下 | 代价 |
|---|---|---|
| 广告拦截收窄（3 个 domainset + 2 个 drop 集 + `Reject_ip`） | 4 个规则集（含约 10.8 万条广告域名） | 漏拦变多，失去 `drop` 语义 |
| 服务组整段删除（办公通讯 / 谷歌服务 / 游戏平台 / 大流量通道） | 17 个规则集 | 流量落到 `MATCH` 仍走代理，只失去可调性 |
| 删 `applications` / `SteamCN_ip` / 内嵌 `Npm` | 3 个规则集 | 桌面端失去按进程分流 |
| 删家宽 / 低倍率判定与两组 | 2 个策略组 | **换来家宽节点回到地区组**（修掉已知问题 2） |
| 删「📢 订阅信息」组 | 1 个策略组 | 通知节点不再有落脚的组 |
| 删 Tailscale 出站与「🔗 Tailscale」组 | 1 个策略组 + 内核版本要求 | 改为系统 Tailscale 客户端 + 规则硬直连 + `PROCESS-NAME` |
| 删「🌍 兜底代理」组 | 1 个策略组 | `MATCH` 直接指向「🧭 代理模式」 |
| 地区收窄为港 / 新 / 日 / 美 | 2 个地区组 | 其余地区节点统一进「🌐 其他地区」 |

保留的关键决定：**🚧 故障转移保留全量节点**、地区组 `url-test` 测速、`lazy: true`、
IPv6 三层封堵、MTU 1400。

### lite 特有的两个设计

1. **「🧭 代理模式」选项末尾内联全部具体节点** —— 可直接把顶层指定为某一个节点，
   不必先进「🌍 全部节点」。mihomo 允许 `select` 的 `proxies` 混放策略组与具体节点。
2. **从「🧭 代理模式」移除 `REJECT`** —— 全量产物该组含 `REJECT`，而 `MATCH` 跟随该组，
   顶层误选会让全部兜底流量被拒（断网级）。**该隐患在全量产物上仍存在，本次未动**（待办）。

### Tailscale 处理方式变更（仅 lite）

不再用 mihomo 的 `tailscale` 出站替代客户端，改为「系统客户端负责建连 + clash 保证不绕代理」：
段 3 硬写 `DIRECT`（两条 `IP-CIDR` + `DOMAIN-SUFFIX,ts.net`），并新增
`PROCESS-NAME,tailscaled` / `PROCESS-NAME,tailscaled.exe` 兜住「只带公网 IP、不带域名」的
DERP / STUN 流量（依赖 `find-process-mode: strict`）。
Android 上拿不到其它应用的进程名，那两条在手机上不生效但无害。

### 一次性校验（未纳入仓库）

渲染后跑了「构造假订阅 → 执行 `main()` → 逐项断言」的冒烟测试：
组数 / 规则数 / 规则集数、规则目标组无悬空引用、`no-resolve` 位置、IPv6 三层、
「🧭 代理模式」内联节点且无 `REJECT`、家宽节点回到地区组、tailscale 段硬直连。
**这些校验不会随改动自动重跑**，仓库仍无构建脚本与自动化测试。

### 连带更新

- 新增 `targets/flclash-override-lite-1014.md` —— lite 产物的功能与规则说明
- `README.md` —— 目录结构补 lite 三件套与 `profile-lite.yaml`；「当前能力」改为两个产物的对照表
  （顺带订正策略组上界 21 → 23）；常用改动表补 `rules/profile-lite.yaml`；已知问题 2 标注 lite 已修
- `docs/design.md` —— 第五节补「lite 产物的取舍」；第七节已知问题 2 标注 lite 已修；
  第九节补「同一客户端的第二个产物：白名单裁剪」与产物状态表

---

## OpenClash lite 轻量产物（2026-10-15）

### 新增产物 `targets/openclash-override-lite-1015.conf`

路由器侧的第二个产物：**22 条分流规则 / 13 个规则集 / 11 个策略组**（全量：52 / 43 / 22）。
骨架取自 `openclash-override-1002.conf`（内容版本 v1.8.0），按新增的裁剪白名单渲染，
产物内容版本 **v1.0.0**（同日因 Tailscale 回退升至 **v1.1.0**，见下一节）。

**动机**：FlClash lite（2026-10-14）验证了「同骨架 + 裁剪白名单」这条路可行，
路由器侧同样存在「规则太多、组太多、日常只用一个入口」的问题；
且路由器是 7×24 常驻设备、内存比手机紧张，规则集削减的收益比客户端更大。
与 FlClash lite 一样，裁剪重点放在**规则集**上（43 → 13）。

**破坏性约束**：本模块与全量 `openclash-override-1002.conf` **不能同时启用** ——
两者都有 `[YAML]` 块，OpenClash 对多个模块是依次合并而非后者覆盖，
`rules!` / `proxy-groups!` 会按启用顺序互相覆盖。切换时必须先停用另一个。

### 新增 `rules/profile-lite-openclash.yaml`（裁剪白名单）

声明 OpenClash lite 与全量的全部差异：保留的规则段与目标组、删除的 30 本规则集、
保留的 11 个策略组、地区白名单，以及**必须与全量逐字一致**的部分
（`[General]`、DNS 段、fake-ip-filter）。另含 `reference_fixups` 一节，
逐条记录「删掉某个组之后哪些引用必须同步清理」—— 路由器侧删组最容易出事的地方，
悬空引用会直接导致整份配置 `ProxyGroup not found` 加载失败。

### 相对全量的主要裁剪

| 类别 | 省下 | 代价 |
|---|---|---|
| 广告拦截收窄（3 个 domainset + 2 个 drop 集 + `Reject_ip`） | 4 个规则集（含约 10.8 万条广告域名） | 漏拦变多（**lite 最实质的代价**） |
| 服务组整段删除（办公通讯 / 谷歌服务 / 游戏平台 / 大流量通道） | 17 个规则集 + 4 个策略组 | 流量落到 `MATCH` 仍走代理，只失去可调性 |
| 删 `SteamCN_ip` | 1 个规则集 | 国区 Steam 回落到走代理 |
| 删 `applications` 与进程规则 | 2 个规则集 | 路由器侧本来就对 LAN 客户端无效 |
| 删家宽 / 低倍率 / 流媒体 / 订阅信息 四组 | 4 个策略组 | 失去按线路特性筛节点的可调性 |
| 删「🌍 兜底代理」组 | 1 个策略组 | `MATCH` 直接指向「🧭 代理模式」 |
| 地区收窄为港 / 新 / 日 / 美 | 2 个地区组 | 英台节点只能走「🌍 全部节点」 |

保留的关键决定：`🤖 AI服务` 与 `🛡️ 国内直连` 两个服务组、第 11 段单主机 UDP 直连例外、
自托管 3 本规则集（`Own*.yaml`）、`FIND_PROCESS_MODE = off`（当晚由 `strict` 改回，见下一节）。

### lite 特有的设计

1. **从「🧭 代理模式」移除 `REJECT`** —— 与 FlClash lite 同样是断网级隐患的预防；
   OpenClash 侧**同时删掉「🇬🇧 英国」「🇹🇼 台湾」两个选项**，否则目标组不存在会直接导致加载失败。
2. **`rule-providers` 用默认合并而非 `!` 覆盖** —— 必须保留 OpenClash 注入的 `oc-cn-domain`
   规则集（预期产物 13 + 1 = 14 本），用 `!` 会把它一并删掉。
3. **`filter` 从 `'：'` 改为 `'剩余'`** —— 兼容「剩余流量 / 剩余天数 / 距离下次重置剩余」三种通知节点命名。
4. ~~**`FIND_PROCESS_MODE` 由 `off` 改回 `strict`** —— 让第 5 条 `PROCESS-NAME,tailscaled`
   兜住 tailscaled 自己发出的 UDP（STUN 3478 / 打洞 41641），它是「访问家里设备绕路国外」的主因。~~
   **已于同日撤回**：TPROXY 接管后链内规则接不住这段 UDP，该条与 `strict` 一起移除，
   改在防火墙层 `RETURN`（见下一节）。

### 两处刻意的跨端差异（不要统一）

| 维度 | FlClash lite | OpenClash lite | 原因 |
|---|---|---|---|
| 「🌐 其他地区」组 | 有 | **没有** | OpenClash 的 `filter` 只能单正则，做不出「未命中四地区」的排除式匹配 |
| 段 3 Tailscale | 5 条（含 `.exe`） | **3 条** | 路由器是 Linux 不存在 `.exe`；当晚又删了进程规则（见下一节） |
| 段 5 应用级分流 | 有（`PROCESS-NAME`） | **没有** | 路由器上对 LAN 客户端永不命中（`Only Works on Routerself`） |

### 一次性校验（未纳入仓库）

渲染后跑了静态校验：从产物里提取 `rule-providers` 名称集合、`proxy-groups` 名称集合、
规则链里的 `RULE-SET` 引用与目标组引用，断言无悬空引用。结论：
**13 个 provider / 11 个组 / 22 条规则，`BAD provider refs` / `BAD target refs` /
`BAD proxies refs` 全为 `<none>`**。**这些校验不会随改动自动重跑。**

### 连带更新

- 新增 `targets/openclash-override-lite-1015.md` —— lite 产物的功能与规则说明
- `README.md` —— 目录树补 OpenClash lite 两件套与 `profile-lite-openclash.yaml`；
  新增「OpenClash 侧能力（两个产物）」对照表；常用改动表补 `profile-lite-openclash.yaml`；
  顺带订正目录树里 `openclash-override-1002` 的后缀（`.sh` → `.conf`，
  自 v1.2.0 起它已是单文件覆写模块而非自定义覆写脚本）
- `docs/design.md` —— 第九节产物状态表补 OpenClash lite 行并订正后缀；补「另一客户端的 lite 产物」说明

---

## Tailscale UDP 直连改用防火墙层方案（2026-10-15 · 同日后续）

### 触发

参考外站文章 [Tailscale 与 OpenClash](https://blog.hex2rgb.top/posts/tailscale-openclash/)
的讨论，复核了产物里那条 `PROCESS-NAME,tailscaled,DIRECT` 的可行性。

### 结论：机理不成立，方案撤回

那条规则本意是让 tailscaled 自己发出的 UDP 不走代理。问题**不在**进程匹配本身，
而在**规则链的位置**：UDP 流量进入 mangle 表的 `openclash` 链时已被 mihomo 的 TPROXY
接管，链内规则（含进程规则）只对首次连接生效，接不住这条流。
所以它并非「未实测所以不确定」，而是**原理上不可能生效**。

### 改动

| 文件 | 改动 |
|---|---|
| `targets/openclash-override-1002.conf` | 内容版本 **v1.7.0 → v1.8.0**；删第 9 条 `PROCESS-NAME,tailscaled`；`FIND_PROCESS_MODE` `strict → off`；规模 53 → **52** 条 |
| `targets/openclash-override-lite-1015.conf` | 内容版本 **v1.0.0 → v1.1.0**；删第 5 条同一规则；`FIND_PROCESS_MODE` `strict → off`；规模 23 → **22** 条 |
| `rules/profile-lite-openclash.yaml` | `content_version` → v1.8.0；段 3 改为 3 条，行号映射整体前移 |
| `rules/priorities.yaml` | 段 3 注释里「当前的实际差异」改为「曾经的差异（v1.8.0 已撤）」 |
| `rulesets/OwnDIRECTRules.yaml` | UDP 注释改为指向防火墙层方案与「已知问题 10」 |
| `targets/openclash-override-1002.md` / `-lite-1015.md` | 同步全部数字与段落；重写「已知问题 10」与「验证 Tailscale」排查步骤 |
| `docs/openclash.md` | 第 7 节补「路由器自身的进程规则在 TPROXY 下同样不可靠」；风险分级表标注唯一有条件的例外 |
| `README.md` / `docs/design.md` | 对照表数字 53 → 52、23 → 22；Tailscale 行去掉 `PROCESS-NAME` |

规则段编号随之整体前移：全量段 3 变为 9-11、lite 段 3 变为 5-7，
其后各段与文档里所有「第 N 条」引用都已同步。

### 新方案（**尚未实测**）

在 `openclash_custom_firewall_rules.sh` 里，于 mangle 表 `PREROUTING` / `OUTPUT` 的
`TPROXY` **之前**插入 `RETURN`，匹配 `100.64.0.0/10` 与 UDP 3478 / 41641。
脚本、插入位置、四步排查与回退方式见
[`../targets/openclash-override-1002.md`](../targets/openclash-override-1002.md)「已知问题 10」。

⚠️ 这打破了 `docs/openclash.md` 原先「本项目不碰防火墙脚本」的约定。风险等级不变
（防火墙层出错会断网），但这是**唯一有条件的例外**，且随时可删掉脚本恢复。

### 一次性校验

- 全量：**52 条规则**（段 1-2 / 3-8 / 9-11 / 12-19 / 20 / 21-31 / 32-34 / 35-37 / 38-44 / 45-49 / 50 / 51-52）
- lite：**22 条规则**（段 1-2 / 3-4 / 5-7 / 8-14 / 15 / 16 / 17-19 / 20 / 21-22）
- 两个产物中都已无任何实际的 `PROCESS-NAME` 规则（`grep` 命中全部落在注释里）
- 组数、规则集数、引用完整性不受本次改动影响
