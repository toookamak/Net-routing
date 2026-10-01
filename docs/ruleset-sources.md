# 规则集来源清单

> 本文件为手工整理，核对上游规则集是否变更时请手动更新。
>
> 最近检查：2026-10-01 08:47:45 UTC

## 概览

| 项 | 数量 |
|---|---|
| 远程规则集 | 44 |
| 存活 | 41 |
| **失效** | **3** |
| 内嵌规则集（无外部依赖） | 15 |
| 已定义但未被任何规则引用 | 0 |

## ⚠️ 失效的规则集（3）

> mihomo 遇到失效的 provider **不会报错，只会静默空载**。
> 症状是「订阅更新成功但该类流量分流不生效」，需要手工换源。

| 规则集 | 状态 | 引用位置 | 地址 |
|---|---|---|---|
| `CustomProxyRules` | 404 | office | https://raw.githubusercontent.com/toookamak/Net-routing/refs/heads/main/rulesets/OwnPROXYRules.yaml |
| `CustomDirectRules` | 404 | custom-direct | https://raw.githubusercontent.com/toookamak/Net-routing/refs/heads/main/rulesets/OwnDIRECTRules.yaml |
| `CustomRejectRules` | 404 | adblock | https://raw.githubusercontent.com/toookamak/Net-routing/refs/heads/main/rulesets/OwnREJECTRules.yaml |

## 全部规则集

| 规则集 | 格式 | behavior | 条数级 | 来源 | 引用位置 | 状态 |
|---|---|---|---|---|---|---|
| `Lan_ip` | yaml | classical | 125B | RealSeek/Clash_Rule_DIY | direct | ✅ 200 |
| `Domestic_no_ip` | yaml | classical | 4216B | RealSeek/Clash_Rule_DIY | direct | ✅ 200 |
| `UnBan` | text | classical | 482B | ACL4SSR/ACL4SSR | unban | ✅ 200 |
| `DirectNoResolve` | yaml | classical | 2144B | blackmatrix7/ios_rule_script | unban | ✅ 200 |
| `MicrosoftCNCDN_no_ip` | text | classical | ok | Sukka (ruleset.skk.moe) | direct | ✅ 200 |
| `AppleCNCDN_no_ip` | text | domain | ok | Sukka (ruleset.skk.moe) | direct | ✅ 200 |
| `Github` | yaml | classical | 438B | blackmatrix7/ios_rule_script | office | ✅ 200 |
| `Origin` | yaml | classical | 1274B | blackmatrix7/ios_rule_script | game | ✅ 200 |
| `CustomProxyRules` | yaml | classical | — | toookamak/Net-routing（自建·本仓库） | office | ❌ 404 |
| `CustomDirectRules` | yaml | classical | — | toookamak/Net-routing（自建·本仓库） | custom-direct | ❌ 404 |
| `Reject_ip` | yaml | classical | 1167B | RealSeek/Clash_Rule_DIY | adblock | ✅ 200 |
| `Reject_no_ip` | yaml | classical | 1068B | RealSeek/Clash_Rule_DIY | adblock | ✅ 200 |
| `Reject_domainset` | yaml | classical | 840525B | RealSeek/Clash_Rule_DIY | adblock | ✅ 200 |
| `Reject_no_ip_drop` | yaml | classical | 109B | RealSeek/Clash_Rule_DIY | adblock | ✅ 200 |
| `Reject_no_ip_no_drop` | yaml | classical | 427B | RealSeek/Clash_Rule_DIY | adblock | ✅ 200 |
| `CustomRejectRules` | yaml | classical | — | toookamak/Net-routing（自建·本仓库） | adblock | ❌ 404 |
| `MicrosoftCDN_no_ip` | yaml | classical | 240B | RealSeek/Clash_Rule_DIY | cdn | ✅ 200 |
| `Docker` | yaml | classical | 258B | blackmatrix7/ios_rule_script | office | ✅ 200 |
| `Telegram_ip` | text | classical | 236B | ACL4SSR/ACL4SSR | office | ✅ 200 |
| `Microsoft_no_ip` | text | classical | 553B | ACL4SSR/ACL4SSR | office | ✅ 200 |
| `Telegram_no_ip` | text | classical | 236B | ACL4SSR/ACL4SSR | office | ✅ 200 |
| `Figma_ip` | yaml | classical | 175B | blackmatrix7/ios_rule_script | office | ✅ 200 |
| `Notion_ip` | yaml | classical | 227B | blackmatrix7/ios_rule_script | office | ✅ 200 |
| `OneDrive` | text | classical | 268B | ACL4SSR/ACL4SSR | office | ✅ 200 |
| `Dropbox` | yaml | classical | 292B | blackmatrix7/ios_rule_script | office | ✅ 200 |
| `AI_no_ip` | yaml | classical | 433B | RealSeek/Clash_Rule_DIY | ai | ✅ 200 |
| `Gemini` | yaml | classical | 318B | blackmatrix7/ios_rule_script | ai | ✅ 200 |
| `OpenAI` | yaml | classical | 576B | blackmatrix7/ios_rule_script | ai | ✅ 200 |
| `GoogleFCM_ip` | text | classical | 335B | ACL4SSR/ACL4SSR | google | ✅ 200 |
| `GoogleFCM_no_ip` | text | classical | 335B | ACL4SSR/ACL4SSR | google | ✅ 200 |
| `YouTube` | text | classical | 197B | ACL4SSR/ACL4SSR | google | ✅ 200 |
| `Google` | text | classical | 282B | ACL4SSR/ACL4SSR | google | ✅ 200 |
| `SteamCN_ip` | text | classical | 259B | ACL4SSR/ACL4SSR | direct | ✅ 200 |
| `UnrealRules` | yaml | classical | 295B | blackmatrix7/ios_rule_script | game | ✅ 200 |
| `Steam` | yaml | classical | 599B | blackmatrix7/ios_rule_script | game | ✅ 200 |
| `Sony` | text | classical | 116B | ACL4SSR/ACL4SSR | game | ✅ 200 |
| `Nintendo` | text | classical | 146B | ACL4SSR/ACL4SSR | game | ✅ 200 |
| `Stream_ip` | yaml | classical | 234B | RealSeek/Clash_Rule_DIY | cdn | ✅ 200 |
| `CDN_domainset` | yaml | classical | 18532B | RealSeek/Clash_Rule_DIY | cdn | ✅ 200 |
| `CDN_no_ip` | yaml | classical | 510B | RealSeek/Clash_Rule_DIY | cdn | ✅ 200 |
| `Download_domainset` | yaml | classical | 3599B | RealSeek/Clash_Rule_DIY | cdn | ✅ 200 |
| `Download_no_ip` | yaml | classical | 125B | RealSeek/Clash_Rule_DIY | cdn | ✅ 200 |
| `GameDownload` | yaml | classical | 546B | blackmatrix7/ios_rule_script | cdn | ✅ 200 |
| `applications` | text | classical | 498B | Loyalsoldier/clash-rules | traffic | ✅ 200 |

## 说明

- **条数级** 是本次拉取的响应体大小，用于粗略判断规则集是否被清空
- **behavior** 决定 mihomo 匹配方式（domain 最省内存，classical 最通用）
- **format** 必须与文件实际格式一致，否则 provider 静默空载
- ⚠️ 标记的规则集已定义但没被 `priorities.yaml` 引用，属于冗余，可考虑清理
