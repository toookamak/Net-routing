// ============================================================================
// net-routing · FlClash 覆写脚本 · lite 轻量版（自包含单文件）
// ----------------------------------------------------------------------------
// 用途：整份粘贴到 FlClash 的「覆写 / Override」中，对订阅配置做整体改写。
// 形态：mihomo 覆写脚本，标准入口为 `function main(params) { ...; return params }`。
// 依赖：不使用 mihomo 的 tailscale 出站，因此全量产物那条
//       「mihomo >= v1.19.25」的硬性要求在本产物中不适用。
//
// 与全量产物的关系：
//   骨架取自 targets/flclash-override-1001.js（内容版本 v1.1.0，2026-10-14），
//   裁剪白名单见 rules/profile-lite.yaml。两者互不影响，可同时存在：
//   全量产物管「什么都能调」，本产物管「少而稳」。
//
// 版本：v1.0.0（2026-10-14 立项）
//   · 相对全量：分流规则 54 → 23，规则集 46 → 13，策略组上界 23 → 12
//   · 地区收窄为 香港 / 日本 / 美国 / 新加坡，其余节点统一进「🌐 其他地区」
//   · 移除 Tailscale 出站与「🔗 Tailscale」组：tailscale 相关流量一律硬直连
//     （含 2 条进程规则），不再支持用本配置代替 Tailscale 客户端
//   · 移除家宽 / 低倍率判定与对应策略组（家宽节点因此回到所属地区组）
//   · 「🧭 代理模式」选项末尾内联全部具体节点，一步即可指定只用某一个节点
//   · 服务组只保留「🤖 AI服务」与「⛔ 广告拦截」
// 文件版本：lite-1014（2026-10-14）
//
// ── 版本约定（重要）──────────────────────────────────────────────────────
// 文件名末尾的数字是「立项日期」，lite 与全量各自独立编号：
//
//   flclash-override-lite-1014.js
//                       ^^^^  =  1014  →  2026-10-14 立项
//
//   · 日常的小修改 —— 加规则、调顺序、改注释、修 bug ——
//     **一律直接改这个文件，文件名保持不变。**
//   · 只有出现**重大结构调整**（模块拆分、入口签名改变、
//     策略组结构重做、规则链整体重排等）时，
//     才以当天的日期另存为新的大版本文件。
//
//   文件内的 vX.Y.Z 是**内容版本**（每次有实质改动就递增），
//   与文件名的大版本是两回事，不要混用。
//
// ── 生成方式 ──────────────────────────────────────────────────────────────
// 本文件是**产物**。规则层数据的唯一事实来源是 rules/*.yaml，
// 本文件按 rules/profile-lite.yaml 声明的白名单渲染而来。
//   改规则  → 改 rules/profile-lite.yaml（及它引用的 rules/*.yaml）→ 重新生成本文件
//   改逻辑  → 直接改本文件标记之外的代码
//
// 标记之间是**数据**（由 YAML 生成，不要手改）：
//     // @generated:begin <块名>   ...   // @generated:end <块名>
// 标记之外是**逻辑**（手写维护）。重新生成时只替换标记之间的内容。
//
// 当前规模：23 条分流规则 / 13 个规则集引用 / 最多 12 个策略组
//           （地区组按订阅中实际出现的节点动态增减，12 是满配值）
// ============================================================================

'use strict';

// ===================== 调试配置 =====================

/**
 * 调试日志开关。关闭时 log() 不输出任何内容。
 * 注意：logError 与模块失败汇总**不受**此开关影响，始终输出。
 */
const DEBUG_MODE = false;

/**
 * 严格模式：任一模块处理失败即抛出异常，阻断配置生成。
 * 默认关闭 —— 保持「尽力生成」的行为，但失败会被显式汇总打印，
 * 避免半成品配置被当成成功结果静默使用。
 */
const STRICT_MODE = false;

/**
 * 日志输出（仅 DEBUG_MODE 开启时有效）
 * @param {...any} args - 日志内容
 */
function log(...args) {
    if (DEBUG_MODE) {
        console.log(`[net-routing]`, ...args);
    }
}

/**
 * 错误日志输出（始终输出，不受 DEBUG_MODE 影响）
 * @param {string} context - 错误上下文
 * @param {Error} error - 错误对象
 */
function logError(context, error) {
    console.error(`[net-routing Error] ${context}:`, error.message);
    if (DEBUG_MODE && error.stack) {
        console.error(error.stack);
    }
}

// ===================== 常量定义 =====================

// @generated:begin STRATEGY_NAMES
const STRATEGY_NAMES = Object.freeze({
    // 核心策略组
    GLOBAL_ROUTING: "🧭 代理模式",
    ALL_NODES: "🌍 全部节点",
    AUTO_SELECT: "⚡ 延迟优选",
    FAILOVER: "🚧 故障转移",

    // 服务策略组（组名含空格与 emoji，不能直接做对象 key）
    SERVICE_AI: "🤖 AI服务",
    SERVICE_ADBLOCK: "⛔ 广告拦截",

    // 默认路由
    DOMESTIC_TRAFFIC: "🛡️ 国内直连",

    // 特殊标识
    REGION_OTHER: "🌐 其他地区",
    DIRECT: "DIRECT",
    REJECT: "REJECT",
});
// @generated:end STRATEGY_NAMES

/**
 * 节点特征关键词。改动请同步 rules/filters.yaml。
 *
 * ⚠️ 一律用简短文字，不要特殊符号（emoji / 冒号 / 连字符）。
 *    换订阅是常态，各家命名风格不同，但「家宽」「剩余」这种词是通用的。
 */
const FILTER_KEYWORDS = Object.freeze({
    // 通知节点关键词。
    // 宽版本含裸的「年」「月」等单字，会误杀正常线路节点（如「年付专线」）；
    // 收窄版本改用「年付/月付」等组合词，误杀更少。
    NOTIFICATION: "自动|故障|流量|官网|套餐|机场|订阅|年|月|失联|频道|Traffic|Expire|剩余|过期|激励|分享|到期|续费|充值",
    NOTIFICATION_STRICT: "自动|故障|流量|官网|套餐|机场|订阅|年付|月付|失联|频道|Traffic|Expire|剩余|过期|激励|分享|到期|续费|充值",
});

/**
 * 是否启用收窄后的通知节点关键词
 * false = 使用宽版本（更激进，误杀正常线路节点）；true = 使用 NOTIFICATION_STRICT
 */
const USE_STRICT_NOTIFICATION_FILTER = true;

/**
 * 策略组分类。仅作为客户端分组列表的归类标签，不影响匹配逻辑。
 */
const GROUP_CATEGORIES = Object.freeze({
    CORE: "核心路由",
    REGION: "具体地区",
    SERVICE: "服务专用",
    DEFAULT_ROUTE: "默认路由"
});

// @generated:begin REGION_CONFIG
const REGION_CONFIG = Object.freeze(new Map([
    ["HK", {
        code: "HK",
        name: "🇭🇰 香港",
        icon: "Hong_Kong.png",
        regex: new RegExp("香港|Hong Kong|HK", 'i')
    }],
    ["SG", {
        code: "SG",
        name: "🇸🇬 新加坡",
        icon: "Singapore.png",
        regex: new RegExp("新加坡|狮城|Singapore|SG", 'i')
    }],
    ["JP", {
        code: "JP",
        name: "🇯🇵 日本",
        icon: "Japan.png",
        regex: new RegExp("日本|Japan|JP", 'i')
    }],
    ["US", {
        code: "US",
        name: "🇺🇸 美国",
        icon: "United_States.png",
        // ⚠️ 不要裸 US：/i 子串匹配会把 Australia（A-us-tralia）错分进美国组。
        //    只认完整词。US 洛杉矶 01 这种纯缩写命名会落到「🌐 其他地区」，
        //    那是看得见的漏匹配，比看不见的错分好。
        regex: new RegExp("美国|United States|America", 'i')
    }]
]));
// @generated:end REGION_CONFIG
// lite 只保留以上 4 个地区（对应 rules/profile-lite.yaml 的 regions.keep）。
// 英国 / 台湾 以及 regions.yaml 里注释掉的 KR / DE 均未渲染 ——
// 未命中任何地区的节点统一进「🌐 其他地区」，因此不会掉节点。

// ===================== 配置管理中心 =====================

/**
 * 集中管理所有可配置参数。改动请同步 rules/options.yaml。
 */
const CONFIG_MANAGER = Object.freeze({
    // 测速用的探测 URL，须返回 204 且不被拦截
    TEST_URL: "http://www.gstatic.com/generate_204",

    /**
     * 规则集更新间隔（秒）—— 仅作为 RULE_PROVIDER_DEFINITIONS 中未声明
     * interval 时的兜底值。每个 provider 的实际间隔以自身定义为准。
     */
    UPDATE_INTERVALS: {
        DEFAULT: 172800   // 48 小时
    },

    // 策略组图标 CDN
    CDN_SOURCES: {
        PRIMARY: "https://fastly.jsdelivr.net/gh/Koolson/Qure/IconSet/Color/"
    },

    /**
     * 「🛡️ 国内直连」策略组的默认选中项。
     * 规则链中 `GEOIP,CN` 指向该组，选项列表第一项即默认选中项。
     * DIRECT = 国内 IP 默认直连；改为 STRATEGY_NAMES.GLOBAL_ROUTING
     * 即恢复「国内 IP 也走代理」。
     */
    DOMESTIC_TRAFFIC_DEFAULT: STRATEGY_NAMES.DIRECT,

    /**
     * 测速间隔（秒）。
     * 30 分钟足以感知节点质量变化，同时显著降低移动端耗电与发热。
     * 配合各 url-test / fallback 组的 lazy:true，未被选中的组完全不发起测速。
     */
    SPEED_TEST_INTERVAL: 1800
});

// ===================== 图标配置 =====================

/**
 * 图标显示开关。关闭时不向任何策略组写入 icon 字段。
 */
const ICONS_SETTINGS = Object.freeze({
    DISPLAY_ICONS: false
});

/**
 * 图标路径生成器。
 */
const IconManager = {
    /**
     * 获取完整图标 URL
     * @param {string} iconName - 图标文件名
     * @returns {string|undefined} 完整 URL；图标关闭或未指定时返回 undefined
     */
    get(iconName) {
        if (!ICONS_SETTINGS.DISPLAY_ICONS || !iconName) {
            return undefined;
        }
        return CONFIG_MANAGER.CDN_SOURCES.PRIMARY + iconName;
    },

    // 预定义图标映射（仅列出实际被引用的条目）
    ICONS: Object.freeze({
        GLOBAL_ROUTING: "Proxy.png",
        ALL_NODES: "World_Map.png",
        AUTO_SELECT: "Speedtest.png",
        FAILOVER: "Final.png",
        AI: "ChatGPT.png",
        AD_BLOCK: "Advertising.png",
        DOMESTIC: "StreamingCN.png"
    })
};

// ===================== 正则表达式缓存 =====================

/**
 * 正则表达式缓存管理器。
 * 节点数量多时重复编译同一批正则代价明显，这里按 pattern 缓存。
 */
const RegexCache = {
    _cache: new Map(),

    /**
     * 获取或创建正则表达式
     * @param {string} pattern - 正则模式
     * @param {string} flags - 标志
     * @returns {RegExp} 正则表达式
     */
    get(pattern, flags = 'i') {
        const key = `${pattern}|${flags}`;
        if (!this._cache.has(key)) {
            this._cache.set(key, new RegExp(pattern, flags));
            log(`Compiled regex: ${pattern}`);
        }
        return this._cache.get(key);
    },

    /**
     * 构建包含任一关键词的正则
     * @param {string} keywords - 关键词（| 分隔）
     * @returns {RegExp} 正则表达式
     */
    buildInclude(keywords) {
        return this.get(`(${keywords})`, 'i');
    },

    /**
     * 清空缓存
     */
    clear() {
        this._cache.clear();
    }
};

// 预编译节点分类所需正则
const REGEX_PATTERNS = Object.freeze({
    NOTIFICATION: RegexCache.buildInclude(
        USE_STRICT_NOTIFICATION_FILTER
            ? FILTER_KEYWORDS.NOTIFICATION_STRICT
            : FILTER_KEYWORDS.NOTIFICATION
    ),
});

// ===================== 缓存管理 =====================

/**
 * 全局缓存。FlClash 中脚本可能被重复调用，缓存保证同一份订阅只做一次重活。
 */
const CACHE = {
    proxyGroups: null,
    ruleProviders: null,

    /**
     * 清空所有缓存
     */
    clear() {
        this.proxyGroups = null;
        this.ruleProviders = null;
        log('Cache cleared');
    }
};

// ===================== 配置验证 =====================

/**
 * 配置验证器
 */
const ConfigValidator = {
    /**
     * 验证配置参数
     * @param {Object} params - 配置参数
     * @returns {Array<string>} 错误列表，空数组表示通过
     */
    validate(params) {
        const errors = [];

        if (!params || typeof params !== 'object') {
            errors.push('params must be a valid object');
            return errors;
        }

        if (!Array.isArray(params.proxies)) {
            errors.push('params.proxies must be an array');
        } else if (params.proxies.length === 0) {
            errors.push('params.proxies is empty');
        }

        return errors;
    },

    /**
     * 验证单个代理节点
     * @param {Object} proxy - 代理节点
     * @returns {boolean} 是否有效
     */
    isValidProxy(proxy) {
        return proxy &&
            typeof proxy === 'object' &&
            typeof proxy.name === 'string' &&
            proxy.name.length > 0;
    }
};

// ===================== 主入口函数 =====================

/**
 * 主入口 —— FlClash 覆写脚本的标准签名
 * @param {Object} params - 订阅配置
 * @param {Array} params.proxies - 代理节点列表
 * @returns {Object} 处理后的配置
 */
const main = (params) => {
    log('Starting configuration processing...');

    // 配置验证
    const validationErrors = ConfigValidator.validate(params);
    if (validationErrors.length > 0) {
        logError('Configuration validation failed', new Error(validationErrors.join('; ')));
        return params;
    }

    try {
        // 处理顺序有依赖，不可随意调整：
        //   代理组须在规则之前（规则的目标组必须已存在）
        //   lite 已移除 Tailscale 出站注入，故不再需要它排在节点分类之前
        const processors = [
            { name: 'Basic Options', fn: overwriteBasicOptions },
            { name: 'Sniffer', fn: overwriteSniffer },
            { name: 'Proxy Groups', fn: overwriteProxyGroups },
            { name: 'Rules', fn: overwriteRules },
            { name: 'DNS', fn: overwriteDns },
            { name: 'TUN', fn: overwriteTunnel }
        ];


        // 收集失败模块：单个模块失败不中断整体生成，但结束时必须显式汇总，
        // 避免「半成品配置」被当成成功结果静默使用
        const failures = [];

        processors.forEach(({ name, fn }) => {
            try {
                log(`Processing ${name}...`);
                fn(params);
                log(`${name} processed successfully`);
            } catch (error) {
                failures.push({ name, error });
                logError(`Failed to process ${name}`, error);
            }
        });

        if (failures.length > 0) {
            const summary = failures
                .map(f => `${f.name}: ${f.error.message}`)
                .join(' | ');
            console.error(
                `[net-routing] ⚠️ ${failures.length}/${processors.length} 个模块处理失败，生成的配置可能不完整: ${summary}`
            );
            if (STRICT_MODE) {
                throw new Error(`配置生成失败（${failures.length} 个模块）: ${summary}`);
            }
        }

        // 清理缓存
        CACHE.clear();
        RegexCache.clear();

        log('Configuration processing completed');
        return params;

    } catch (error) {
        logError('Unexpected error in main', error);
        return params;
    }
};

// ===================== 基础设置模块 =====================

/**
 * 覆盖基础配置选项
 * @param {Object} params - 配置参数
 */
function overwriteBasicOptions(params) {
    const basicConfig = {
        "mixed-port": 7890,
        "allow-lan": true,
        "unified-delay": true,
        "tcp-concurrent": true,
        "geodata-mode": true,
        "geox-url": {
            "geoip": "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat",
            "geosite": "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
        },
        "find-process-mode": "strict",
        // 关闭 IPv6 —— 防真实地址泄露。
        // 单靠这一项堵不住：系统自身的 IPv6 路由仍会绕过 TUN 直连，
        // 必须配合 tun.inet6-route-address 才能真正封死（见 overwriteTunnel）。
        // ChatGPT / HuggingFace 等均为双栈，走 IPv4 代理不影响使用。
        ipv6: false,
        "global-client-fingerprint": "chrome",
        profile: {
            "store-selected": true,
            "store-fake-ip": true
        },
        mode: "rule",
        "skip-auth-prefixes": ["127.0.0.1/32"],
        "lan-allowed-ips": ["0.0.0.0/0", "::/0"]
    };

    Object.assign(params, basicConfig);
    log('Basic options configured');
}

// ===================== 流量嗅探设置 =====================

/**
 * 覆盖流量嗅探配置
 * @param {Object} params - 配置参数
 */
function overwriteSniffer(params) {
    params.sniffer = {
        enable: true,
        // 将嗅探到的域名与真实 IP 绑定，供规则匹配与日志回溯
        "force-dns-mapping": true,
        // 纯 IP 流量也参与嗅探
        "parse-pure-ip": true,
        // 不改写目的地地址 —— 改写会破坏部分应用的连接复用
        "override-destination": false,
        sniff: {
            HTTP: {
                ports: ["80", "443"],
                "override-destination": false
            },
            TLS: {
                ports: ["443"]
            }
        },
        // APNs 推送需保持原目的 IP，否则收不到推送
        "skip-domain": ["+.push.apple.com"],
        // Telegram 机房段，嗅探反而会拿到错误的目的地
        "skip-dst-address": [
            "91.105.192.0/23", "91.108.4.0/22", "91.108.8.0/21",
            "91.108.16.0/21", "91.108.56.0/22", "95.161.64.0/20",
            "149.154.160.0/20", "185.76.151.0/24", "2001:67c:4e8::/48",
            "2001:b28:f23c::/47", "2001:b28:f23f::/48", "2a0a:f280:203::/48"
        ]
    };
    log('Sniffer configured');
}

// ===================== 代理组构建器 =====================

/**
 * 代理组构建器 —— 统一创建策略组的入口。
 */
class ProxyGroupBuilder {
    constructor() {
        this.groups = [];
    }

    /**
     * 添加策略组
     * @param {string} name - 策略组名称
     * @param {string} type - 策略类型（select / url-test / fallback）
     * @param {Object} options - 额外选项
     * @returns {ProxyGroupBuilder} 链式调用
     */
    add(name, type, options = {}) {
        // 只有自动测速类组需要 url / interval，手动 select 组不需要
        const isAuto = type !== "select";
        const finalConfig = {
            name,
            type,
            category: options.category || GROUP_CATEGORIES.CORE,
            url: isAuto ? CONFIG_MANAGER.TEST_URL : undefined,
            interval: isAuto ? CONFIG_MANAGER.SPEED_TEST_INTERVAL : undefined,
            ...options
        };

        // 图标关闭时移除 icon 字段，避免向 mihomo 传入 undefined
        if (!ICONS_SETTINGS.DISPLAY_ICONS) {
            delete finalConfig.icon;
        }

        this.groups.push(finalConfig);
        return this;
    }

    /**
     * 获取构建结果
     * @returns {Array} 策略组数组
     */
    build() {
        return this.groups;
    }
}

// ===================== 代理组配置模块 =====================

/**
 * 覆盖代理组配置
 * @param {Object} params - 配置参数
 */
function overwriteProxyGroups(params) {
    if (CACHE.proxyGroups) {
        log('Using cached proxy groups');
        params["proxy-groups"] = CACHE.proxyGroups;
        return;
    }

    log('Building proxy groups...');

    const nodeClassification = classifyNodes(params);

    const builder = new ProxyGroupBuilder();

    buildCoreGroups(builder, nodeClassification);
    buildRegionalGroups(builder, nodeClassification);
    buildServiceGroups(builder, nodeClassification);
    buildDefaultRouteGroups(builder, nodeClassification);

    const allGroups = builder.build();

    CACHE.proxyGroups = allGroups;
    params["proxy-groups"] = allGroups;

    log(`Built ${allGroups.length} proxy groups`);
}

/**
 * 节点分类结果
 * @typedef {Object} NodeClassification
 * @property {Array<string>} allProxies - 所有可用节点（已剔除通知节点；为空时回落为 [DIRECT]）
 * @property {Set<string>} availableRegions - 真正生成了策略组的地区名称集合
 * @property {Map<string, Array<string>>} regionProxies - 地区名称 -> 该地区节点名列表（已剔除通知节点）
 * @property {Array<string>} notificationProxies - 通知节点
 * @property {Array<string>} otherProxies - 未命中任何地区的普通节点
 * @property {boolean} hasOtherProxies - 是否有其他地区节点
 */

/**
 * 处理并分类代理节点
 * 单趟遍历完成全部判定，避免同一节点被反复扫描
 *
 * 与全量产物的差异（lite）：不再把「家宽 / 原生 / 低倍率」节点视为特殊节点，
 * 它们与普通节点同等参与地区归属 —— 既留在「🌍 全部节点」里，也回到所属地区组，
 * 因此全量产物「家宽节点被排除出地区组」这个已知问题在本产物中不存在。
 *
 * @param {Object} params - 配置参数
 * @returns {NodeClassification} 节点分类结果
 */
function classifyNodes(params) {
    log('Classifying proxy nodes...');

    const allProxies = [];
    const notificationProxies = [];
    const otherProxies = [];
    const availableRegions = new Set();
    const regionProxies = new Map();

    (Array.isArray(params.proxies) ? params.proxies : []).forEach(proxy => {
        if (!ConfigValidator.isValidProxy(proxy)) return;

        const name = proxy.name;

        // Tailscale 出站节点不是机场节点（本产物不再注入，但订阅里若已有），
        // 不得参与地区分类 / 测速组，否则会污染节点列表
        if (proxy.type === 'tailscale') return;

        // 1) 通知节点判定（机场的流量 / 到期提示节点，正常不该被选中）
        const isNotification = REGEX_PATTERNS.NOTIFICATION.test(name);

        // 2) 通知节点退出「全部节点」，其余节点全部保留
        if (isNotification) {
            notificationProxies.push(name);
        } else {
            allProxies.push(name);
        }

        // 3) 地区归属
        // 这里有两套判定标准，语义不同，不可合并：
        //   · availableRegions = 首个命中即停 → 决定该地区组是否被创建
        //   · 地区组成员        = 逐地区独立判定 → 决定组内包含哪些节点
        // 因此跨地区命名的节点（如「香港 Japan 专线」）只归属第一个命中的地区，
        // 但会同时出现在两个地区组的成员里。
        let firstMatchedRegion = null;
        for (const [, region] of REGION_CONFIG) {
            if (region.regex.test(name)) {
                firstMatchedRegion = region;
                break;
            }
        }
        if (firstMatchedRegion) {
            availableRegions.add(firstMatchedRegion.name);
        }

        if (!isNotification) {
            for (const [, region] of REGION_CONFIG) {
                if (!region.regex.test(name)) continue;
                if (!regionProxies.has(region.name)) {
                    regionProxies.set(region.name, []);
                }
                regionProxies.get(region.name).push(name);
            }
        }

        // 4) 其他地区节点：不属于任何地区、且不是通知节点
        if (!firstMatchedRegion && !isNotification) {
            otherProxies.push(name);
        }
    });

    // availableRegions 是「选项列表」的判定依据，regionProxies 是「地区组成员」的判定依据，
    // 两者可能不一致：当某地区的节点全部是通知节点时，该地区不会生成组，
    // 但仍可能进了 availableRegions。必须剔除，否则选项里会出现不存在的组名（mihomo 报 loop）。
    for (const regionName of Array.from(availableRegions)) {
        const members = regionProxies.get(regionName);
        if (!members || members.length === 0) {
            availableRegions.delete(regionName);
        }
    }

    // 被判定为通知节点的节点会退出「全部节点」，这里显式记录，避免静默掉节点
    if (notificationProxies.length > 0) {
        log(`Filtered out ${notificationProxies.length} notification node(s):`,
            notificationProxies.join(', '));
    }

    log(`Classification complete: ${allProxies.length} nodes, ${availableRegions.size} regions`);

    return {
        // 全部节点被剔光时回落为 DIRECT，保证下游组不会拿到空列表
        allProxies: allProxies.length ? allProxies : [STRATEGY_NAMES.DIRECT],
        availableRegions,
        regionProxies,
        notificationProxies,
        otherProxies,
        hasOtherProxies: otherProxies.length > 0
    };
}

/**
 * 收集全部「节点来源类」选项：地区 / 其他地区 / 全部节点
 * @param {NodeClassification} classification - 节点分类结果
 * @returns {Array<string>} 节点来源选项列表
 */
function buildNodeSourceOptions(classification) {
    const opts = [];

    for (const [, region] of REGION_CONFIG) {
        // 判定依据必须用 availableRegions（地区组真正被创建的条件），
        // 而不是 regionProxies —— 后者可能为空（如该地区节点全是通知节点），
        // 直接用会导致选项里出现不存在的组名，mihomo 报 ProxyGroup loop
        if (classification.availableRegions.has(region.name)) {
            opts.push(region.name);
        }
    }

    if (classification.hasOtherProxies) {
        opts.push(STRATEGY_NAMES.REGION_OTHER);
    }

    // 「全部节点」始终可达，是手动挑节点的入口之一
    opts.push(STRATEGY_NAMES.ALL_NODES);

    return opts;
}
/**
 * 构建代理选项列表（服务组 / 默认路由组使用）
 * 结构 = 核心策略 + 自动策略 + 节点来源 + DIRECT (+ REJECT)
 * @param {NodeClassification} classification - 节点分类结果
 * @param {Object} options - 选项配置
 * @param {boolean} options.includeDefaults - 是否包含延迟优选 / 故障转移
 * @param {boolean} options.includeReject - 是否包含 REJECT
 * @returns {Array<string>} 选项列表
 */
function buildProxyOptions(classification, options = {}) {
    const {
        includeDefaults = true,
        includeReject = false
    } = options;

    const opts = [STRATEGY_NAMES.GLOBAL_ROUTING];

    if (includeDefaults) {
        opts.push(STRATEGY_NAMES.AUTO_SELECT, STRATEGY_NAMES.FAILOVER);
    }

    opts.push(...buildNodeSourceOptions(classification));
    opts.push(STRATEGY_NAMES.DIRECT);

    if (includeReject) {
        opts.push(STRATEGY_NAMES.REJECT);
    }

    return opts;
}

/**
 * 构建核心策略组
 * @param {ProxyGroupBuilder} builder - 构建器
 * @param {NodeClassification} classification - 节点分类
 */
function buildCoreGroups(builder, classification) {
    // 顶层「代理模式」是扁平化的：所有可选来源直接列出，不设中间隐藏组。
    //
    // 曾经把这些收进一个 hidden 的「手动切换」中间组，但 hidden 组不会出现在
    // FlClash 的分组列表里 —— 用户在「代理模式」里选中它之后，找不到任何入口
    // 去配置它，形成死路。
    //
    // 结论（硬性约束）：凡是用户可能选中的项，都必须 visible。
    // hidden 只适用于「用户永远不直接碰、仅被其他组引用」的内部组。
    //
    // lite 追加：在组选项之后**内联全部具体节点名**，可以直接把「代理模式」
    // 指定为某一个节点，不必先进「🌍 全部节点」再挑。mihomo 允许 select 的
    // proxies 列表里混放策略组与具体节点；节点名放在组选项之后，
    // 保证默认选中项仍是第一项「⚡ 延迟优选」。
    const nodeSources = buildNodeSourceOptions(classification);

    // 订阅里一个可用节点都没有时 allProxies 会回落成 [DIRECT]，
    // 此时不再内联，避免组内出现重复的 DIRECT
    const isDirectFallback = classification.allProxies.length === 1
        && classification.allProxies[0] === STRATEGY_NAMES.DIRECT;
    const inlineNodes = isDirectFallback ? [] : classification.allProxies;

    const topOptions = [
        STRATEGY_NAMES.AUTO_SELECT,
        ...nodeSources,
        STRATEGY_NAMES.FAILOVER,
        STRATEGY_NAMES.DIRECT,
        ...inlineNodes
    ];

    builder
        .add(STRATEGY_NAMES.GLOBAL_ROUTING, "select", {
            category: GROUP_CATEGORIES.CORE,
            proxies: topOptions,
            icon: IconManager.get(IconManager.ICONS.GLOBAL_ROUTING)
        })
        // lazy：仅在有流量实际经过该组时才做健康检查，
        // 未被选中的 url-test / fallback 组不空转，大幅降低后台耗电。
        .add(STRATEGY_NAMES.AUTO_SELECT, "url-test", {
            category: GROUP_CATEGORIES.CORE,
            proxies: classification.allProxies,
            icon: IconManager.get(IconManager.ICONS.AUTO_SELECT),
            hidden: false,
            lazy: true
        })
        .add(STRATEGY_NAMES.FAILOVER, "fallback", {
            category: GROUP_CATEGORIES.CORE,
            proxies: classification.allProxies,
            icon: IconManager.get(IconManager.ICONS.FAILOVER),
            hidden: false,
            lazy: true
        })
        .add(STRATEGY_NAMES.ALL_NODES, "select", {
            category: GROUP_CATEGORIES.CORE,
            proxies: classification.allProxies,
            icon: IconManager.get(IconManager.ICONS.ALL_NODES),
            hidden: false
        });
}

/**
 * 构建地区策略组
 * 节点归属直接复用 classifyNodes 的单趟分类结果，不再重复过滤
 * @param {ProxyGroupBuilder} builder - 构建器
 * @param {NodeClassification} classification - 节点分类
 */
function buildRegionalGroups(builder, classification) {
    for (const [, region] of REGION_CONFIG) {
        // 仅当该地区被判定为「可用地区」时才生成组
        if (!classification.availableRegions.has(region.name)) continue;

        const regionProxies = classification.regionProxies.get(region.name);
        if (!regionProxies || regionProxies.length === 0) continue;

        // 地区组用 url-test：选「🇭🇰 香港」即表示「香港地区内自动选延迟最低的节点」，
        // 不需要用户再手动挑一个具体节点。lazy 保证未被选中时不测速。
        builder.add(region.name, "url-test", {
            category: GROUP_CATEGORIES.REGION,
            proxies: regionProxies,
            icon: IconManager.get(region.icon),
            hidden: false,
            lazy: true
        });
    }

    if (classification.hasOtherProxies) {
        builder.add(STRATEGY_NAMES.REGION_OTHER, "url-test", {
            category: GROUP_CATEGORIES.REGION,
            proxies: classification.otherProxies,
            icon: IconManager.get(IconManager.ICONS.ALL_NODES),
            hidden: false,
            lazy: true
        });
    }
}

/**
 * 构建服务策略组
 * lite 只保留「🤖 AI服务」与「⛔ 广告拦截」两个
 * @param {ProxyGroupBuilder} builder - 构建器
 * @param {NodeClassification} classification - 节点分类
 */
function buildServiceGroups(builder, classification) {
    const serviceOptions = buildProxyOptions(classification, { includeReject: true });

    builder
        // AI 服务单独成组：需要把 AI 流量固定到某个地区 / 某个节点时，
        // 改这一组的选项即可，不影响其它流量
        .add(STRATEGY_NAMES.SERVICE_AI, "select", {
            category: GROUP_CATEGORIES.SERVICE,
            proxies: serviceOptions,
            icon: IconManager.get(IconManager.ICONS.AI)
        })
        // 广告拦截组固定两项，不可选其他出口
        .add(STRATEGY_NAMES.SERVICE_ADBLOCK, "select", {
            category: GROUP_CATEGORIES.SERVICE,
            proxies: [STRATEGY_NAMES.REJECT, STRATEGY_NAMES.DIRECT],
            icon: IconManager.get(IconManager.ICONS.AD_BLOCK)
        });
}

/**
 * 构建默认路由策略组
 * lite 只保留「🛡️ 国内直连」—— 兜底那条 MATCH 直接指向「🧭 代理模式」，
 * 不再经过中间组，所以没有「🌍 兜底代理」
 * @param {ProxyGroupBuilder} builder - 构建器
 * @param {NodeClassification} classification - 节点分类
 */
function buildDefaultRouteGroups(builder, classification) {
    const domesticOptions = applyDefaultOption(
        buildProxyOptions(classification),
        CONFIG_MANAGER.DOMESTIC_TRAFFIC_DEFAULT
    );

    builder.add(STRATEGY_NAMES.DOMESTIC_TRAFFIC, "select", {
        category: GROUP_CATEGORIES.DEFAULT_ROUTE,
        proxies: domesticOptions,
        icon: IconManager.get(IconManager.ICONS.DOMESTIC)
    });
}

// ===================== 规则配置模块 =====================

/**
 * 规则顺序与目标组 —— **顺序即优先级，命中即停**。
 *
 * 硬性约束：
 *   1. UnBan / DirectNoResolve 必须在所有 REJECT 之前，否则白名单形同虚设
 *   2. Tailscale 硬直连段必须在 GEOSITE,cn 与 GEOIP,CN 之前，
 *      否则内网 IP 会被「国内直连」先抢走
 *   3. GEOIP,CN 与 MATCH 必须是最后两条
 *
 * 段内可自由增删规则，段与段之间的先后不可调换。
 */
// @generated:begin RULE_PRIORITIES
const RULE_PRIORITIES = [
    {
        type: "unban",
        group: "DIRECT",
        // 免拦截白名单 + 全球直连修正。必须最先。
        rules: [
            "UnBan",
            "DirectNoResolve"
        ]
    },
    {
        type: "adblock",
        group: "⛔ 广告拦截",
        // 广告拦截。放在直连修正之后。
        // lite 只保留两本（主集 + 自托管），不挂 3 个 domainset 大集
        rules: [
            "Reject_no_ip",
            "CustomRejectRules"
        ]
    },
    {
        type: "tailscale",
        group: "DIRECT",
        // Tailscale 相关流量一律硬直连。
        //
        // 本产物不接管 Tailscale、也不注入 mihomo 内置 tailscale 出站 ——
        // 系统客户端负责建连，clash 只保证这些流量不被绕进代理。
        //   前两条 IP-CIDR：接住 tailnet 网段。*.ts.net 在 fake-ip-filter 里，
        //     拿到的是真实 100.x 地址，因此这两条能命中
        //   DOMAIN-SUFFIX,ts.net：接住 MagicDNS 域名的其它形态
        //   两条 PROCESS-NAME：接住 tailscaled 只带公网 IP 的连接
        //     （DERP / STUN 打洞没有域名，只有进程名兜得住）
        // ⚠️ PROCESS-NAME 需要 find-process-mode 非 off（本配置为 strict）；
        //    Android 上 FlClash 拿不到其它应用的进程名，这两条在手机上不生效，
        //    但不生效也无副作用 —— 只是退回加它们之前的行为。
        rules: [
            "IP-CIDR,100.64.0.0/10,no-resolve",
            "IP-CIDR,100.100.100.100/32,no-resolve",
            "DOMAIN-SUFFIX,ts.net",
            "PROCESS-NAME,tailscaled",
            "PROCESS-NAME,tailscaled.exe"
        ]
    },
    {
        type: "direct",
        group: "DIRECT",
        // 私有网络 + 国内备案 CDN + 国内直连
        rules: [
            "GEOSITE,private",
            "GEOIP,private,no-resolve",
            "MicrosoftCNCDN_no_ip",
            "AppleCNCDN_no_ip",
            "GEOSITE,cn",
            "Lan_ip",
            "Domestic_no_ip"
        ]
    },
    {
        type: "custom-direct",
        // 用户自定义直连，锁死 DIRECT，不建组
        rules: [
            { name: "CustomDirectRules", group: "DIRECT" }
        ]
    },
    {
        type: "custom-proxy",
        // 用户自定义代理，直接投到顶层「🧭 代理模式」
        // （全量产物这里投的是「📁 办公通讯」，lite 没有该组）
        rules: [
            { name: "CustomProxyRules", group: "🧭 代理模式" }
        ]
    },
    {
        type: "ai",
        group: "🤖 AI服务",
        rules: [
            "OpenAI",
            "AI_no_ip",
            "Gemini"
        ]
    },
    {
        type: "geoip",
        group: "🛡️ 国内直连",
        // 国内 IP 兜底
        rules: [
            "GEOIP,CN"
        ]
    },
    {
        type: "final",
        group: "🧭 代理模式",
        // 兜底：直接指向顶层「🧭 代理模式」——
        // 该组默认选中「⚡ 延迟优选」，即「其余一切走代理」
        rules: [
            "MATCH"
        ]
    }
];
// @generated:end RULE_PRIORITIES

/**
 * 拼接一条规则：<主体>,<目标组>[,<附加参数>]
 *
 * mihomo 要求附加参数（no-resolve）位于目标策略「之后」，
 * 否则会被当成策略名解析，报 proxy [no-resolve] not found。
 * 例如 GEOIP,private 配 DIRECT,no-resolve，结果须为 GEOIP,private,DIRECT,no-resolve。
 *
 * @param {string} body - 规则主体，如 GEOIP,private 或 RULE-SET,Xxx
 * @param {string} group - 目标策略组 / DIRECT / REJECT
 * @param {Array<string>} [ruleParams] - 附加参数，如 ['no-resolve']
 * @returns {string} 完整规则字符串
 */
function buildRule(body, group, ruleParams) {
    return [body, group, ...(ruleParams || [])].join(',');
}

const KNOWN_RULE_PARAMS = Object.freeze(['no-resolve']);

/**
 * 解析规则字符串，把末尾的附加参数（如 no-resolve）与主体分离。
 * 用于把 YAML 里的书写形式拆成 body + params，再交给 buildRule 重排。
 * @param {string} rule - 规则字符串
 * @returns {{ body: string, params: Array<string> }} 规则主体与附加参数
 */
function parseRule(rule) {
    const parts = rule.split(',');
    const params = [];

    // 至少要剩下 2 段（主体 + 目标组）才能继续剥离末尾参数
    while (parts.length > 2 && KNOWN_RULE_PARAMS.includes(parts[parts.length - 1].toLowerCase())) {
        params.unshift(parts.pop());
    }

    return { body: parts.join(','), params };
}

/**
 * 覆盖规则配置
 * @param {Object} params - 配置参数
 */
function overwriteRules(params) {
    log('Building rules...');

    const rules = [];

    RULE_PRIORITIES.forEach(priority => {
        if (!priority.rules) return;

        priority.rules.forEach(rule => {
            if (typeof rule === 'string') {
                if (rule === 'MATCH') {
                    rules.push(`MATCH,${priority.group}`);
                } else {
                    // 统一走 buildRule：附加参数（no-resolve）必须排在目标组之后
                    const { body, params } = parseRule(rule);
                    // 不含逗号的是 RULE-SET 名称，需要补上前缀
                    const fullBody = body.includes(',') ? body : `RULE-SET,${body}`;
                    rules.push(buildRule(fullBody, priority.group, params));
                }
            } else if (rule.name && rule.group) {
                // 自定义规则：provider 名与目标组都由规则本身指定（不继承所属段）
                rules.push(buildRule(`RULE-SET,${rule.name}`, rule.group, rule.params));
            }
        });
    });

    params.rules = rules;
    params["rule-providers"] = createRuleProviders();

    log(`Built ${rules.length} rules`);
}

// ===================== 规则提供器配置 =====================

/**
 * 规则集定义 —— **由 rules/providers.yaml 生成，不要手改**。
 *
 * 字段说明：
 *   url      远程地址
 *   path     本地落盘路径（相对 mihomo 工作目录）
 *   format   解析方式：yaml / text
 *   behavior 匹配方式：classical（混合格式）/ domain（纯域名，更快）
 *   interval 更新间隔（秒）
 *
 * ⚠️ format 与 behavior 声明错，mihomo 不会报错，只会**静默空载**。
 *    症状是「订阅更新成功、面板正常、但某类流量不分流」，极难自查。
 * ⚠️ 多个 provider 名指向同一 path 会竞争写同一个缓存文件。
 *    运行时自检会对此告警（见 createRuleProviders 末尾）。
 */
// @generated:begin RULE_PROVIDER_DEFINITIONS
const RULE_PROVIDER_DEFINITIONS = {
    Lan_ip: {
        url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/DIRECT/ip/Lan_ip.yaml",
        path: "./ruleset/toookamak/Lan_ip.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    Domestic_no_ip: {
        url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/DIRECT/no_ip/Domestic_no_ip.yaml",
        path: "./ruleset/toookamak/Domestic_no_ip.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    UnBan: {
        url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/UnBan.list",
        path: "./ruleset/toookamak/UnBan.list",
        format: "text",
        behavior: "classical",
        interval: 172800
    },
    DirectNoResolve: {
        url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Direct/Direct.yaml",
        path: "./ruleset/toookamak/Direct.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    MicrosoftCNCDN_no_ip: {
        url: "https://ruleset.skk.moe/Clash/non_ip/microsoft_cdn.txt",
        path: "./ruleset/toookamak/MicrosoftCNCDN.txt",
        format: "text",
        behavior: "classical",
        interval: 172800
    },
    AppleCNCDN_no_ip: {
        url: "https://ruleset.skk.moe/Clash/domainset/apple_cdn.txt",
        path: "./ruleset/toookamak/AppleCNCDN.txt",
        format: "text",
        behavior: "domain",
        interval: 172800
    },
    CustomProxyRules: {
        url: "https://raw.githubusercontent.com/toookamak/Net-routing/refs/heads/main/rulesets/OwnPROXYRules.yaml",
        path: "./ruleset/toookamak/CustomProxyRules.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 86400
    },
    CustomDirectRules: {
        url: "https://raw.githubusercontent.com/toookamak/Net-routing/refs/heads/main/rulesets/OwnDIRECTRules.yaml",
        path: "./ruleset/toookamak/CustomDirectRules.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 86400
    },
    Reject_no_ip: {
        url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/REJECT/no_ip/Reject_no_ip.yaml",
        path: "./ruleset/toookamak/Reject_no_ip.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    CustomRejectRules: {
        url: "https://raw.githubusercontent.com/toookamak/Net-routing/refs/heads/main/rulesets/OwnREJECTRules.yaml",
        path: "./ruleset/toookamak/CustomRejectRules.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 86400
    },
    AI_no_ip: {
        url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/PROXY/no_ip/AI_no_ip.yaml",
        path: "./ruleset/toookamak/AI_no_ip.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    Gemini: {
        url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/refs/heads/master/rule/Clash/Gemini/Gemini.yaml",
        path: "./ruleset/toookamak/Gemini.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    OpenAI: {
        url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/OpenAI/OpenAI.yaml",
        path: "./ruleset/toookamak/OpenAI.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
};
// @generated:end RULE_PROVIDER_DEFINITIONS

/**
 * 创建规则提供器配置
 * @returns {Object} 规则提供器配置对象
 */
function createRuleProviders() {
    if (CACHE.ruleProviders) {
        return CACHE.ruleProviders;
    }

    log('Creating rule providers...');

    const providers = {};

    Object.entries(RULE_PROVIDER_DEFINITIONS).forEach(([name, config]) => {
        providers[name] = {
            type: "http",
            // behavior 须与规则集内容匹配：纯域名列表用 domain 更快，
            // 混合格式用 classical（默认值）
            behavior: config.behavior || "classical",
            // 必须回落到定义里的 format：ACL4SSR / Sukka 的 .list 是纯文本，
            // 若按 yaml 解析会导致 provider 空载 / 解析失败
            format: config.format || "yaml",
            // 以 rules/providers.yaml 声明的间隔为准，缺失时才用兜底值
            interval: config.interval || CONFIG_MANAGER.UPDATE_INTERVALS.DEFAULT,
            url: config.url,
            path: config.path
        };
    });

    CACHE.ruleProviders = providers;
    log(`Created ${Object.keys(providers).length} rule providers`);

    // 自检：多个 provider 名指向同一个 path，会重复下载并竞争写同一个缓存文件
    const pathOwners = new Map();
    Object.entries(providers).forEach(([name, cfg]) => {
        if (!cfg.path) return;   // inline 类型没有 path
        if (!pathOwners.has(cfg.path)) pathOwners.set(cfg.path, []);
        pathOwners.get(cfg.path).push(name);
    });
    pathOwners.forEach((names, path) => {
        if (names.length > 1) {
            console.warn(`[net-routing Warn] 多个 provider 共用同一路径: ${path} -> ${names.join(', ')}`);
        }
    });

    return providers;
}

// ===================== 辅助函数 =====================

/**
 * 把指定选项提到选项列表首位（即策略组的默认选中项）
 * 若该选项已在首位或不存在，则原样返回
 * @param {Array<string>} options - 选项列表
 * @param {string} preferred - 期望的默认项
 * @returns {Array<string>} 调整后的选项列表
 */
function applyDefaultOption(options, preferred) {
    const index = options.indexOf(preferred);
    if (index <= 0) {
        return options;
    }
    return [preferred, ...options.filter(o => o !== preferred)];
}

// ===================== DNS配置模块 =====================

/**
 * 覆盖DNS配置
 * @param {Object} params - 配置参数
 */
function overwriteDns(params) {
    params.dns = {
        enable: true,
        listen: "0.0.0.0:1053",
        "enhanced-mode": "fake-ip",
        "fake-ip-range": "198.18.0.1/16",
        "use-hosts": true,
        "use-system-hosts": true,
        // 与全局 ipv6:false 保持一致，不解析 AAAA 记录
        ipv6: false,
        // 以下域名排除在 fake-ip 之外：这些服务拿到假 IP 就无法工作
        // （无法回连、心跳、局域网发现或真实 IP 校验）
        "fake-ip-filter": [
            "*.lan", "*.local",
            "time.*.com", "ntp.*.com",

            "*.xiaomi.com",
            "*.apple.com",
            "localhost.ptlogin2.qq.com",
            "localhost.sec.qq.com",
            "*.qq.com", "*.tencent.com",
            "*.msftconnecttest.com",
            "*.msftncsi.com",
            // 组播 / P2P 与局域网发现
            "+.local", "+.home", "+.lan", "+.internal",
            // 系统连通性检测（须走直连，否则会被判为异常网络）
            "connectivitycheck.gstatic.com",
            "*.gvt1.com", "*.gvt2.com",
            // 常见银行 / 支付类，部分依赖真实 IP 校验
            "*.icbc.com.cn", "*.ccb.com", "*.abchina.com",
            "*.alipay.com", "*.unionpay.com",
            // IoT / 局域网设备
            "*.esphome.io", "*.homeassistant.io",
            "+.ts.net"
        ],
        // 用于解析其余 nameserver 域名的引导 DNS（明文 UDP，必须能直连）
        "default-nameserver": [
            "223.5.5.5",
            "119.29.29.29"
        ],
        // 默认 DNS：只用国内 DoH。
        //
        // ⚠️ 不要再改回 Cloudflare / Google 等国外 DoH —— 那是踩过坑的设计。
        //
        //    原因：FlClash 内置的 mihomo 内核**无法把 DNS 查询送进代理**。
        //    实测（2026-10-02）两条常见修法都无效：
        //      · respect-rules: true —— 不会代理 DoH。debug 日志里普通流量都有
        //        `match ... using <出口>`，而 DoH 上游没有任何规则匹配行。
        //      · nameserver 加 `#代理名` 后缀 —— 需 mihomo ≥ v1.15，低版本静默忽略。
        //    而国外 DoH 从大陆直连必然超时：同一请求 cloudflare DoH 直连 5652ms、
        //    走代理只要 215ms，稳定超过 mihomo 的 5 秒 DNS 超时，
        //    于是 `dns resolve failed: context deadline exceeded`。
        //
        //    为什么国内 DoH 够用：
        //      · 走代理出口的流量**不需要本地解析**，域名直接交给远端节点，
        //        所以这部分完全不受 DNS 影响；
        //      · 命中 DIRECT 的境外 CDN 域名，国内 DoH 也能返回正确 IP
        //        （实测 alidns 正确返回 cdn.ldstatic.com 的 Cloudflare 地址）。
        //    代价是失去「防 DNS 污染」能力，这是当前内核版本下的取舍。
        nameserver: [
            'https://doh.pub/dns-query',
            'https://dns.alidns.com/dns-query'
        ],
        // 代理节点自身域名的解析源。国际 DoH 不可达，只能用国内 DoH；
        // 若机场节点域名遭污染，需改用机场自带的解析入口。
        "proxy-server-nameserver": [
            'https://doh.pub/dns-query',
            'https://dns.alidns.com/dns-query'
        ],
        // 本地 / 苹果域名显式指定国内 DoH。
        // 保持 policy 是为了将来若升级内核、改回国际 DoH 时，
        // 这两类域名仍稳定走国内源，不受默认值变动影响。
        "nameserver-policy": {
            'geosite:private,apple': [
                'https://dns.alidns.com/dns-query',
                'https://doh.pub/dns-query'
            ]
        }
    };
    log('DNS configured');
}

// ===================== TUN配置模块 =====================

/**
 * 覆盖TUN配置
 * @param {Object} params - 配置参数
 */
function overwriteTunnel(params) {
    params.tun = {
        enable: true,
        "stack": "mixed",
        "dns-hijack": ["any:53"],
        "auto-route": true,
        "auto-redirect": false,
        "auto-detect-interface": true,
        "strict-route": false,
        // 接管全球 IPv6 单播段（2000::/3）—— 防 IPv6 泄露的关键项，勿删。
        // 系统自身的 IPv6 路由会绕过 TUN 直连，只设 ipv6:false 无效；
        // 必须由 TUN 抓进来丢弃，浏览器才会回退到 IPv4 走代理。
        // fe80::/10（链路本地）与 ::1（回环）不在此段内，不受影响。
        "inet6-route-address": ["2000::/3"],
        // 1400 而非 1500：降低大包被丢弃的概率，减少网页卡顿与下载断流
        "mtu": 1400
    };
    log('TUN configured');
}
