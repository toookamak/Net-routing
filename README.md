# net-routing

> 📌 **个人学习存档 · 不建议他人使用**
> 使用前请阅读 [项目说明与免责声明](#项目说明与免责声明)。

---

## 项目说明与免责声明

**请在查阅本项目之前完整阅读本节。**

### 一、项目性质与使用态度

本项目是作者**个人学习 AI 时整理的脚本存档**，用于记录代理配置工程化的一些做法，内容由 AI 辅助生成后自行审阅调整。

**不建议任何人学习、使用或转发本项目。** 若仍决定使用，相关风险自行确认并承担。

### 二、内容由 AI 辅助生成，未经完整人工审计

本项目的主体内容（含 `rules/*.yaml`、`rulesets/`、`targets/` 下的逻辑与注释）由 AI 辅助生成。

- 生成内容**未经过完整的人工逐行审计**，可能存在逻辑缺陷、边界情况遗漏、错误注释或不合理的默认值。
- 代码中的大量注释（如「与原实现一致」「踩过坑之后定下来的」）描述的是**设计意图**，而非经过验证的正确性证明。
- 本项目**没有任何自动化测试或构建校验**，产物 `targets/flclash-override-1001.js` 的正确性完全依赖人工审阅。
- **请自行审阅全部代码后再使用。** 任何因直接采信本项目内容而产生的后果，由使用者自行承担。

### 三、第三方内容的版权与许可

本项目**不拥有**其中规则集内容的版权。`rules/providers.yaml` 中引用的规则集均来自第三方开源项目，其著作权与许可协议**归原作者所有**：

| 来源 | 用途 |
|---|---|
| [ACL4SSR/ACL4SSR](https://github.com/ACL4SSR/ACL4SSR) | 规则集 |
| [blackmatrix7/ios_rule_script](https://github.com/blackmatrix7/ios_rule_script) | 规则集 |
| [RealSeek/Clash_Rule_DIY](https://github.com/RealSeek/Clash_Rule_DIY) | 规则集 |
| [Loyalsoldier/clash-rules](https://github.com/Loyalsoldier/clash-rules) | 规则集 |
| [SukkaW/ruleset](https://ruleset.skk.moe) | 规则集 |

- 上游项目可能随时**变更、删除或修改**其规则内容，本项目不对其可用性或正确性作任何担保。
- 第三方规则内容的分发与再使用，**须遵守各上游项目自身的许可协议**。**使用者应自行确认其使用行为符合这些协议。**

### 四、安全与凭据责任

- 本项目的配置会**接管系统网络栈**（TUN 模式）、**修改 DNS 解析**并**改写系统路由表**。配置错误可能导致系统网络不可用。
- 启用 Tailscale 出站功能时，请自行管理认证凭据。**切勿将 `auth-key` 等密钥提交到本仓库。**
- 请勿在提交、Issue 或日志中粘贴包含订阅链接、节点密码、认证密钥等敏感信息。
- 💡 `rulesets/` 是公开目录，填入的内容会随仓库一并公开。若涉及不希望公开的信息（例如内网域名、内部服务地址），可以改用 Private 仓库，或把敏感条目写在 `rules/inline-rules.yaml` 这类不随仓库分发的内嵌位置。
- 使用者有责任在使用前备份原始网络配置。

### 五、风险提示

- 使用代理类工具可能带来以下风险，请自行评估：流量特征可能被识别导致**服务封禁**；规则集或客户端存在缺陷时可能发生 **DNS / IP 泄漏**；第三方规则源的更新**不受本项目控制**，可能随时失效。
- **法律风险**：部分国家和地区对代理、跨境网络接入等行为有明确的限制或禁止性规定。是否合法取决于你所在的位置、接入服务的性质与具体使用方式，**请自行评估并承担全部责任**。

---

## 项目简介

### 目录结构

```
net-routing/
├── rules/                    ★ 规则定义（唯一事实来源）
│   ├── providers.yaml          45 个规则集：URL / format / behavior / interval
│   ├── priorities.yaml         规则顺序与目标组（顺序即优先级）
│   ├── groups.yaml             策略组定义 + 命名规范
│   ├── regions.yaml            地区匹配正则
│   ├── filters.yaml            节点特征关键词
│   ├── options.yaml            运行时开关（ipv6 / tun / 测速 / tailscale）
│   └── inline-rules.yaml       内嵌规则（不依赖外部 URL）
│
├── rulesets/                 ★ 日常改这里（客户端自动拉取，无需重新生成）
│   ├── OwnDIRECTRules.yaml     → CustomDirectRules → DIRECT
│   ├── OwnPROXYRules.yaml      → CustomProxyRules  → 📁 办公通讯
│   └── OwnREJECTRules.yaml     → CustomRejectRules → ⛔ 广告拦截
│
├── targets/
│   ├── flclash-override-1001.js  ★ 粘进 FlClash 的成品（自包含单文件）
│   └── flclash-override-1001.md  ★ 产物的功能与规则说明（改配置前先看这份）
│
└── docs/
    ├── ruleset-sources.md      规则集来源清单
    ├── design.md               设计说明
    └── changelog.md            版本历史
```

> 📖 想了解产物到底做了什么、53 条规则分别管什么、21 个策略组怎么用 —— 看
> [`targets/flclash-override-1001.md`](targets/flclash-override-1001.md)。
>
> 📌 **产物文件名带日期大版本**（`flclash-override-1001.js` = 2026-10-01 立项）。
> 日常小改动直接改这个文件、文件名不变；只有**重大结构调整**才以当天日期另存为新大版本。详见
> [`targets/flclash-override-1001.md`](targets/flclash-override-1001.md) 的「版本约定」。

---

## 填写个人规则

`rulesets/` 下三个文件已经带好了注释模板，**打开改就行**。

**前置条件：这些文件必须先推送到 GitHub，远程 provider 才能拉到。** 首次提交前它们会 404（mihomo 静默空载，不报错），推上去之后 24 小时内自动生效。

### 怎么填

1. 打开 `rulesets/` 下对应文件；
2. 把 `payload: []` 改成列表形式；
3. 删掉示例行的 `#` 并换成你指定的域名；
4. 保存 → 提交推送。**不需要重新生成 `targets/flclash-override-1001.js`。**

```yaml
# 改之前（空列表，什么都不匹配）
payload: []

# 改之后
payload:
  - DOMAIN-SUFFIX,yoursite.com
  - DOMAIN,api.yoursite.net
  - IP-CIDR,203.0.113.0/24,no-resolve
```

**注意**：`payload:` 后面只写一个减号、不带 `[]` 会被解析成 `null` 而不是空数组，内核会拒绝加载。模板里的 `[]` 一定要保留到你要开始填为止。

### 模板里有哪些例子

三个文件都注释掉了完整示例（全部用 RFC 2606 保留域名 `example.com`，默认不生效）：

| 类型 | 用途 |
|---|---|
| `DOMAIN` | 精确匹配单个主机名 |
| `DOMAIN-SUFFIX` | 匹配域名及其所有子域（最常用） |
| `DOMAIN-KEYWORD` | 域名含该关键字即命中，**杀伤力大，易误伤** |
| `IP-CIDR` | 匹配 IP 段，可加 `no-resolve` |
| `PROCESS-NAME` | 按进程匹配，**仅桌面端有效** |

### 三个文件分别在什么优先级

| 文件 | 生效位置 | 说明 |
|---|---|---|
| `OwnREJECTRules.yaml` | 靠前，仅次于免拦截白名单 | 优先级最高，填错会直接压过后面所有规则 |
| `OwnDIRECTRules.yaml` | 「广告拦截」之后、「国内直连」之前 | 锁死 DIRECT，不建策略组 |
| `OwnPROXYRules.yaml` | 「办公通讯」段内 | 走「📁 办公通讯」策略组 |

**填之前先确认一下**：mihomo 面板 →「连接」页能看到流量最终命中了哪条规则。已经被上游规则集正确分流的站点，不要重复添加。

---

## 依赖与兼容性

| 依赖 | 版本 | 说明 |
|---|---|---|
| mihomo 内核 | ≥ v1.19.25 | Tailscale 出站的硬性要求。FlClash ≥ 0.8.93 打包该内核 |
| Node.js | **不需要** | 项目没有构建脚本；`targets/flclash-override-1001.js` 在客户端内运行，无任何外部依赖 |

### 当前能力

**客户端**：FlClash（Win / macOS / Linux / Android / iOS）。产物是标准 mihomo 覆写脚本。

- 53 条分流规则，45 个规则集引用
- 最多 21 个策略组（**实际数量随订阅节点动态变化**：地区组与特性组按订阅中实际出现的节点生成）
- 地区组自动测速选最低延迟（选地区 ≠ 手动挑节点）
- Tailscale 出站（替代独立客户端），分组开关控制启停
- IPv6 泄露封堵
- 测速按需触发（`lazy`），降低移动端耗电

---

## 常用改动

| 想改什么 | 改哪个文件 | 需要重新生成产物？ |
|---|---|---|
| 加一条自己的分流规则 | `rulesets/*.yaml` | **不用** —— 提交推送后客户端自动拉取 |
| 换规则集源、改更新间隔 | `rules/providers.yaml` | ✅ 需要 |
| 调整规则顺序 / 改分流目标 | `rules/priorities.yaml` | ✅ 需要 |
| 增删策略组、改组名 | `rules/groups.yaml` | ✅ 需要 |
| 增删地区 | `rules/regions.yaml` | ✅ 需要 |
| 改通知/家宽/低倍率的关键词 | `rules/filters.yaml` | ✅ 需要 |
| 改测速间隔、IPv6、TUN、mtu、Tailscale | `rules/options.yaml` | ✅ 需要 |
| 改内嵌规则（npm 等） | `rules/inline-rules.yaml` | ✅ 需要 |

**两类改动的区别很重要**：

- 改 `rulesets/*.yaml` —— 只提交推送即可，客户端按 `interval: 86400`（24 小时）自动拉取，**不用碰 `targets/flclash-override-1001.js`**。这是日常最常用的入口。
- 改 `rules/*.yaml` —— 只是改了「事实来源」，**产物不会自动同步**。必须让 AI 依据 YAML 重新生成 `targets/flclash-override-1001.js`，再粘回 FlClash 才生效。

---

## 修改规则时的硬性约束

这几条是踩过坑之后定下来的，改动时不能破坏：

1. **凡是从「代理模式」可选中的组，都不能设 `hidden`**
   `hidden` 的组不出现在客户端分组列表里，用户选中后找不到入口配置，形成死路。

2. **规则顺序不可随意调整**
   - `UnBan` / `DirectNoResolve` 必须在所有 REJECT 之前
   - `Tailscale` 必须在 `GEOSITE,cn` 和 `GEOIP,CN` 之前
   - `GEOIP,CN` 和 `MATCH` 必须是最后两条

3. **IPv6 防护是三层一起，缺一层就失效**
   `ipv6: false` + `dns.ipv6: false` + `tun.inet6-route-address: ["2000::/3"]`
   只设前两层，系统自带的 IPv6 路由会绕过 TUN 直连，流量根本不进 mihomo。

4. **`no-resolve` 必须排在目标组之后**
   `GEOIP,private,DIRECT,no-resolve` ✅ / `GEOIP,private,no-resolve,DIRECT` ❌
   后者会被当成策略名，报 `proxy [no-resolve] not found`。

5. **Tailscale 节点必须排除在节点分类之外**
   它不是机场节点，不能进「全部节点」/ 测速组 / 地区组，否则污染测速。

6. **自定义规则集的地址只能出现在 `rules/providers.yaml` 一处**
   产物里曾存在一段 `CONFIG_MANAGER.CUSTOM_RULES` 硬编码，会在运行时把
   `RULE_PROVIDER_DEFINITIONS` 里从 YAML 生成的值整个覆盖掉 —— 地址指回已失效的
   `FL_ruleSet` 仓库，且 `format` 写死为 `text`（而 `rulesets/` 下是 YAML）。
   两处都取不到，且 mihomo 静默空载不报错。已移除。

   **重新生成产物时要确认没有再引入第二处定义。**

---

## 已知问题

以下问题在编写本 README 时经实际运行核对发现，**尚未修复**：

### 1. 两组 provider 共用同一 `path`

`Telegram_ip` / `Telegram_no_ip` 与 `GoogleFCM_ip` / `GoogleFCM_no_ip` 各自指向**完全相同**的 url 与 `path`。

运行时 `flclash-override-1001.js` 会输出警告：

```
[net-routing Warn] 多个 provider 共用同一路径: ./ruleset/toookamak/Telegram.list -> Telegram_ip, Telegram_no_ip
[net-routing Warn] 多个 provider 共用同一路径: ./ruleset/toookamak/GoogleFCM.list -> GoogleFCM_ip, GoogleFCM_no_ip
```

后果：两个 provider 竞争写入同一个缓存文件，更新时可能互相覆盖；同时这两对规则在功能上完全重复（两者都不带 `no-resolve`）。

### 2. 家宽 / 低倍率节点不会进入地区组

`classifyNodes` 中，命中「家宽」或「低倍率」特征的节点会被**排除在所有地区组之外**（`if (!isSpecial)`）。

实际影响：真实订阅中大量节点命名为「香港 家宽」「新加坡 低倍率」，这类节点**只出现在 `🌍 全部节点` 和特性组中，不会出现在对应的地区组**。若某地区的节点全部是家宽/低倍率，该地区组甚至不会被创建（选项列表中相应条目也会消失）。

这是继承自原单文件脚本的既有行为，而非本次重构引入。

### 3. 规则集命名容易误解

provider 名中的 `_ip` / `_no_ip` 后缀表示的是**该规则集的内容类型**（含 IP 规则 / 纯域名规则），**不是** mihomo 的 `no-resolve` 参数。当前 53 条规则中只有 3 条真正带 `no-resolve`，且均为内联的 `IP-CIDR` / `GEOIP` 规则。

---

## 来源与致谢

- 前身为单文件覆写脚本 [`TK_ClashRuleDIY`](https://raw.githubusercontent.com/toookamak/FL_ruleSet/refs/heads/main/TK_ClashRuleDIY_0211.js)
- 规则内容主要来自 [ACL4SSR](https://github.com/ACL4SSR/ACL4SSR)、[blackmatrix7](https://github.com/blackmatrix7/ios_rule_script)、[RealSeek](https://github.com/RealSeek/Clash_Rule_DIY)、[Loyalsoldier](https://github.com/Loyalsoldier/clash-rules)、[SukkaW](https://ruleset.skk.moe)

感谢上述项目的维护者。

---

**📌 本项目是作者个人学习 AI 时的脚本存档，不建议他人学习、使用或转发；若自行使用，风险自负。**
**⚠️ 跨境网络访问相关行为可能违反当地法律法规，使用前请自行评估并承担全部责任。**
