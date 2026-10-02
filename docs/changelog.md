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
