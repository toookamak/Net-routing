# 设计说明

本文档解释 net-routing 的架构决策与背后的原因。改代码前请先读「硬性约束」一节。

---

## 一、核心架构：规则是资产，脚本是渲染器

```
rules/*.yaml  ──(人工/AI 渲染)──▶  targets/flclash-override-1001.js
     ↑                                      │
     └────────── 改规则只动这里 ────────────┘
```

**为什么这样分**

原始形态是一个 1800 行的 JS 覆写脚本，规则定义、渲染逻辑、硬编码常量全部混在一起。改一条规则要在 1800 行里翻找，换一个客户端就得整体重写。

拆分之后：
- **规则层**（YAML）是可读、可审阅、可 diff 的纯数据
- **产物**（`targets/flclash-override-1001.js`）既是逻辑层也是可直接粘贴的成品

换客户端时只需新增一份产物，规则层完全复用。

**生成方式**

项目**没有构建脚本，也没有自动化测试**，不需要 Node.js。`rules/*.yaml` 由 AI（或人工）读取后，
直接渲染出 `targets/flclash-override-1001.js`。渲染时只替换 `@generated:begin/end` 之间的代码块：

```
// @generated:begin STRATEGY_NAMES
const STRATEGY_NAMES = Object.freeze({ ... });   ← 由 groups.yaml 生成
// @generated:end STRATEGY_NAMES
```

标记之间是数据（人改 YAML），标记之外是逻辑（人改产物）。两边互不干扰。

**产物文件名带日期大版本**

产物命名为 `flclash-override-<MMDD>.js`，末尾数字取立项当天的日期：

```
flclash-override-1001.js        ← 1001 = 2026-10-01 立项
```

| 改动类型 | 处理方式 |
|---|---|
| 加规则、调顺序、改注释、修 bug、调参数 | **直接改当前文件，文件名不变** |
| 重大结构调整（模块拆分、入口签名改变、策略组结构重做、规则链整体重排） | 以**当天日期**另存为新大版本，旧文件保留便于回溯 |

配套的说明文档同版本改名（`flclash-override-1001.md`）。

> 文件内另有 `vX.Y.Z` 内容版本，每次实质改动递增。**内容版本与文件名大版本是两回事**，
> 前者回答「改了多少次」，后者回答「结构是哪一天的形态」。

**⚠️ 没有自动校验的代价**

`priorities.yaml` 里的每个目标组名是否存在于 `groups.yaml`、每个 provider 名是否在
`priorities.yaml` 中被引用，**都没有自动检查**。改组名忘了改规则，就会产出
「规则指向不存在的组」的坏配置 —— 这类错误在客户端里表现为整份配置加载失败，排查成本极高。
改组名后必须人工确认 `STRATEGY_NAMES`、`RULE_PRIORITIES`、各 `build*Groups()` 三处同步。

---

## 二、规则层

| 文件 | 职责 |
|---|---|
| `providers.yaml` | 46 个第三方规则集的 URL、格式、behavior、更新间隔 |
| `priorities.yaml` | 规则顺序与目标组 —— 顺序即优先级 |
| `groups.yaml` | 策略组定义与命名规范 |
| `regions.yaml` | 地区匹配正则 |
| `filters.yaml` | 节点特征关键词（通知 / 家宽 / 低倍率） |
| `options.yaml` | 运行时开关（ipv6 / tun / 测速 / interval / tailscale） |
| `inline-rules.yaml` | 内嵌规则，不依赖外部 URL |

### 为什么 provider 要记录 format 和 behavior

这两个字段声明错，mihomo **不会报错，只会静默空载**。

- `format` 声明 yaml 但文件是纯文本 → 解析失败
- `behavior: classical` 配纯域名列表 → 解析失败
- `behavior: domain` 配混合内容 → 部分规则失效

症状统一是「订阅更新成功、面板一切正常、但某类流量分流不生效」。这是本项目里最难自查的一类故障，只能靠人工核对 `rules/providers.yaml` 与上游规则集的实际格式。

### 为什么 npm 规则用 inline 而不是远程

npm 的源域名属于基础设施级别，不会像规则集那样频繁变动。而自建仓库（OwnRules）随时可能转私有或删除 —— 实测就是 404。内嵌后零外部依赖，也顺带解决了「密钥类内容要不要放远程」的取舍。

---

## 三、渲染层

`flclash-override-1001.js` 中标记之外保留的逻辑职责：

1. 节点分类（单趟遍历，判定地区 / 家宽 / 低倍率 / 通知）
2. 策略组构建
3. 规则拼装（`buildRule` / `parseRule` 处理 `no-resolve` 位置）
4. DNS / TUN / sniffer / 基础项输出
5. Tailscale 节点注入

### 策略组的键名用索引而非组名

服务组名含空格与 emoji（`📁 办公通讯`），不能直接做 JS 对象 key。因此：

```js
const STRATEGY_NAMES = Object.freeze({
    SERVICE_OFFICE: "📁 办公通讯",
    SERVICE_AI: "🤖 AI服务",
    // ...
});
```

代价是组名变动时 `STRATEGY_NAMES` 与 `groups.yaml`、`priorities.yaml` 需三处同步，
**没有自动校验**（见第一节）。

---

## 四、硬性约束

这几条都是实际踩过的坑，改动时不能破坏。

### 1. 可选中的组不能设 `hidden`

`hidden: true` 的组不显示在客户端分组列表里，但可以被其他组当作选项引用。

曾经的错误设计：把地区、节点来源收进一个 hidden 的「手动切换」组，顶层只留 4 项。用户在顶层选中「手动切换」后，**在分组列表里找不到这个组，无法进入配置** —— 死路。

结论：`hidden` 仅适用于「用户永不直接碰、仅被内部引用」的组。分组列表长一点是可接受的，功能坏掉不可接受。

### 2. 规则顺序不可随意调整

```
1-2   UnBan / DirectNoResolve    免拦截白名单，必须最先，否则白名单形同虚设
3-8   广告拦截
9-11  Tailscale                 必须在 GEOSITE,cn 与 GEOIP,CN 之前，
                                否则内网 IP 会被「国内直连」先抢走
12-19 私有网络 + 国内直连
...
52   GEOIP,CN
53   MATCH                      兜底，必须最后
```

`priorities.yaml` 里每一段都带 `comment` 说明位置理由。

### 3. IPv6 防护是三层一起

```js
ipv6: false                              // mihomo 不解析 AAAA、不走 IPv6 出站
dns.ipv6: false                           // 不返回 AAAA 记录
tun.inet6-route-address: ["2000::/3"]     // TUN 接管全球 IPv6 单播
```

**只设前两层是无效的。** 系统从宽带/手机卡拿到的 IPv6 地址，浏览器发现网站支持 IPv6 就直接走网卡出去 —— 流量根本没进 TUN，mihomo 看不见，`MATCH` 也管不到。AI 服务照样拿到真实位置。

第三层让 TUN 把 `2000::/3` 抓进来，因 `ipv6: false` 而丢弃，浏览器自动回退 IPv4 走代理。口子从「绕过去」变成「被掐断」。

`fe80::/10`（链路本地）与 `::1`（回环）不在 `2000::/3` 内，不受影响。

### 4. `no-resolve` 必须排在目标组之后

```
GEOIP,private,DIRECT,no-resolve     ✅
GEOIP,private,no-resolve,DIRECT     ❌ 报 proxy [no-resolve] not found
```

mihomo 的参数顺序要求附加参数在目标策略之后。`buildRule()` / `parseRule()` 统一处理，不要手写字符串拼接。

### 5. Tailscale 节点必须排除在节点分类之外

`classifyNodes` 中显式 `if (proxy.type === 'tailscale') return;`。

Tailscale 出站不是机场节点，若参与分类会：
- 混入「全部节点」和「全部节点」组成员
- 进入 url-test / fallback 组，导致测速请求打向一个未连接的节点
- 被地区正则误判。

---

## 五、三维取舍：安全 / 速度 / 耗电

这三者不是优先级关系，需要综合评估。实际决策记录：

| 决策 | 倾向 | 理由 |
|---|---|---|
| IPv6 全封 | 安全 | 代价是 IPv6-only 网站不可用。ChatGPT / HuggingFace 均双栈，实际无损 |
| 测速 `lazy: true` | 耗电 | 纯减少无谓工作，不改任何行为 |
| 测速间隔 600→1800s | 耗电 | 30 分钟足够感知节点质量变化 |
| `mtu` 1500→1400 | 速度 | 减少大包丢弃导致的卡顿与断流 |
| 国内域名直连 | 速度 | **不为了安全把流量路径搞复杂** —— 国内网站保持一层直连 |
| 故障转移保留全量节点 | 功能 | 兜底场景需要全量覆盖，不为省电牺牲可用性 |

曾评估但未采纳的激进方案：

- **关掉地区组测速** —— 会让「选地区」退回手动挑节点，违背设计意图
- **provider 改 behavior: domain** —— 绝大多数规则集混有 IP-CIDR / PROCESS-NAME，声明为 domain 会导致部分规则失效
- **`respect-rules: true`** —— 能减少 DNS 污染重试，但增加解析延迟，与速度目标冲突

---

## 六、命名规范

方案 A：单个 emoji + 简短中文，控制在 5 字以内。

| 分组 | 说明 |
|---|---|
| 🧭 代理模式 | 顶层唯一入口 |
| ⚡ 延迟优选 / 🚧 故障转移 | 自动策略 |
| 🌍 全部节点 | 手动挑节点 |
| 🇭🇰🇯🇵🇺🇸 地区 | url-test 自动择优 |
| 🏠 家宽 / 💰 低倍率 / 📢 订阅信息 | 特性组 |
| 📁 办公通讯 / 🤖 AI服务 / 🔍 谷歌服务 / 游戏平台 / 📺 大流量通道 | 服务组 |
| ⛔ 广告拦截 | 固定 [REJECT, DIRECT] |
| 🔗 Tailscale | 开关组 |
| 🛡️ 国内直连 / 🌍 兜底代理 | 默认路由 |

历史重命名（记录在 `groups.yaml` 末尾）：

- `国内流量` → `🛡️ 国内直连` —— 行为是直连，但原名与「国际流量」对称易误导
- `国际流量` → `🌍 兜底代理` —— 它就是 `MATCH` 兜底，原名暗示「国际」不准确
- `机场通知` → `📢 订阅信息` —— 部分机场节点名是「机场订阅」而非通知
- `虚幻引擎` → `游戏平台` —— 已含 Steam / EA / PS / Switch

---

## 七、已知问题

1. **`Telegram_ip`/`Telegram_no_ip` 与 `GoogleFCM_ip`/`GoogleFCM_no_ip` 各自共用同一 path** —— 两组 provider 的 url 与 `path` 完全相同，会竞争写同一个缓存文件，且对应的两条规则功能上完全重复（都不带 `no-resolve`）。运行时 `flclash-override-1001.js` 会打印 `多个 provider 共用同一路径` 警告。合并需改规则名，待办。

2. **家宽 / 低倍率节点不进入地区组** —— `classifyNodes` 中 `if (!isSpecial)` 把命中家宽或低倍率特征的节点排除在所有地区组外。真实订阅中大量节点命名为「香港 家宽」「新加坡 低倍率」，这类节点只出现在「🌍 全部节点」和特性组中。若某地区节点全是家宽/低倍率，该地区组不会被创建。这是继承自原单文件脚本的既有行为，非本次重构引入。

3. **策略组名与规则目标组之间没有自动校验** —— 组名同时出现在 `STRATEGY_NAMES`、`RULE_PRIORITIES`（`RULE_PRIORITIES` 里部分段直接写中文字符串）以及各 `build*Groups()` 中。改组名需人工确认三处同步，改漏会产出「规则指向不存在的组」的坏配置，表现为整份配置加载失败。

4. **Android 端 Tailscale 权限** —— mihomo v1.19.25 修复了 netlink 权限问题，但 Android 平台仍可能有未覆盖的场景。电脑端已验证，Android 需实测。

---

## 八、自托管规则集

`rulesets/` 下三个 YAML 文件由使用者手工编辑，通过 `rules/providers.yaml` 以远程 provider 形式加载：

| 文件 | provider 名 | 引用位置 |
|---|---|---|
| `OwnDIRECTRules.yaml` | `CustomDirectRules` | `custom-direct` 段 |
| `OwnPROXYRules.yaml` | `CustomProxyRules` | `office` 段 |
| `OwnREJECTRules.yaml` | `CustomRejectRules` | `adblock` 段 |

三点设计取舍：

1. **用 YAML + `payload:` 而不是 `text`**。`text` 格式下一行就是一条规则，加注释是否被内核接受并无可靠保证，写坏了整个 provider 静默空载。YAML 原生支持注释，模板可以带完整说明。

2. **`payload` 必须写成 `[]` 而不是留空**。只写 `payload:` 会解析成 `null` 而非空数组，内核可能拒绝加载。

3. **⚠️ 目前没有本地前置校验**。项目没有 `test/` 目录与校验脚本，`rulesets/*.yaml` 的 YAML 语法、`payload` 类型与每条规则格式**都没有自动检查**。远端 URL 要推送后才能取到，本地校验本可以把错误拦在 push 之前 —— 这是当前形态下最值得补回来的一块。

💡 `rulesets/` 随仓库一起公开。涉及不希望公开的信息时，可改用 Private 仓库，或把该条规则移到 `inline-rules.yaml` 这类不依赖外部地址的内嵌位置。

---

## 九、扩展到其它客户端

新增产物的步骤：

1. 以 `targets/flclash-override-1001.js` 为模板，复制出新的目标文件
2. 调整配置输出格式（可能是 YAML 而非 JS）
3. 沿用 `@generated:begin/end` 标记约定，同步规则层的数据段
4. 人工核对输出的策略组名与规则目标组是否一致（无自动校验）

`rules/` 目录**不需要任何改动** —— 这正是分层的意义。
