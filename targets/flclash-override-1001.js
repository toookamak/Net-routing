// ============================================================================
// net-routing · FlClash 覆写脚本（自包含单文件）
// ----------------------------------------------------------------------------
// 用途：整份粘贴到 FlClash 的「覆写 / Override」中，对订阅配置做整体改写。
// 形态：mihomo 覆写脚本，标准入口为 `function main(params) { ...; return params }`。
// 依赖：mihomo >= v1.19.25（FlClash >= 0.8.93 打包该内核）—— Tailscale 出站的硬性要求。
//
// 版本：v1.0.1
//   · 2026-10-01：新增 Twitter/X 规则并纳入办公通讯
//   · 2026-10-02：overwriteDns 默认源由国际 DoH 改为国内 DoH 单源
//     （国际 DoH 大陆直连必超时，而本内核无法把 DNS 查询送进代理，详见 overwriteDns 注释）
// 文件版本：1001（2026-10-01）
//
// ── 版本约定（重要）──────────────────────────────────────────────────────
// **文件名末尾的数字是「大版本」，取立项当天的日期。**
//
//   flclash-override-1001.js
//                ^^^^  =  1001  →  2026-10-01 立项
//
//   · 日常的小修改 —— 加规则、调顺序、改注释、修 bug ——
//     **一律直接改这个文件，文件名保持不变。**
//   · 只有出现**重大结构调整**（模块拆分、入口签名改变、
//     策略组结构重做、规则链整体重排等）时，
//     才以当天的日期另存为新的大版本文件：
//         flclash-override-1001.js  →  flclash-override-1108.js
//     旧文件保留在仓库里，便于回溯与对照。
//
//   文件内的 vX.Y.Z 是**内容版本**（每次有实质改动就递增），
//   与文件名的大版本是两回事，不要混用。
//
// ── 生成方式 ──────────────────────────────────────────────────────────────
// 本文件是**产物**。规则层的唯一事实来源是 rules/*.yaml，本文件由其渲染而来。
//   改规则  → 改 rules/*.yaml → 重新生成本文件
//   改逻辑  → 直接改本文件标记之外的代码
//
// 标记之间是**数据**（由 YAML 生成，不要手改）：
//     // @generated:begin <块名>   ...   // @generated:end <块名>
// 标记之外是**逻辑**（手写维护）。重新生成时只替换标记之间的内容。
//
// 当前规模：54 条分流规则 / 46 个规则集引用 / 最多 21 个策略组
//           （地区组与特性组按订阅中实际出现的节点动态增减，21 是满配值）
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

    // 线路特性组
    LINE_RESIDENTIAL: "🏠 家宽/原生线路",
    LINE_LOWRATE: "💰 低倍率节点",
    LINE_NOTIFICATION: "📢 订阅信息",

    // 服务策略组（组名含空格与 emoji，不能直接做对象 key）
    SERVICE_OFFICE: "📁 办公通讯",
    SERVICE_AI: "🤖 AI服务",
    SERVICE_GOOGLE: "🔍 谷歌服务",
    SERVICE_GAME: "游戏平台",
    SERVICE_TRAFFIC: "📺 大流量通道",
    SERVICE_ADBLOCK: "⛔ 广告拦截",

    // 网络与默认路由
    TAILSCALE: "🔗 Tailscale",
    DOMESTIC_TRAFFIC: "🛡️ 国内直连",
    GLOBAL_TRAFFIC: "🌍 兜底代理",

    // 特殊标识
    REGION_OTHER: "🌐 其他地区",
    DIRECT: "DIRECT",
    REJECT: "REJECT",
});
// @generated:end STRATEGY_NAMES

/**
 * 节点特征关键词。改动请同步 rules/filters.yaml。
 */
const FILTER_KEYWORDS = Object.freeze({
    // 通知节点关键词。
    // 宽版本含裸的「年」「月」等单字，会误杀正常线路节点（如「年付专线」）；
    // 收窄版本改用「年付/月付」等组合词，误杀更少。
    NOTIFICATION: "自动|故障|流量|官网|套餐|机场|订阅|年|月|失联|频道|Traffic|Expire|剩余|激励|分享|到期|续费|充值",
    NOTIFICATION_STRICT: "自动|故障|流量|官网|套餐|机场|订阅|年付|月付|失联|频道|Traffic|Expire|剩余|激励|分享|到期|续费|充值",

    RESIDENTIAL: "家宽|原生|residential|home",
    LOW_RATE: "低倍率|lowrate|低-rate|倍率"
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
    LINE_TYPE: "线路特性",
    SERVICE: "服务专用",
    TRAFFIC: "流量管理",
    CUSTOM: "自定义规则",
    DEFAULT_ROUTE: "默认路由"
});

// @generated:begin REGION_CONFIG
const REGION_CONFIG = Object.freeze(new Map([
    ["HK", {
        code: "HK",
        name: "🇭🇰 香港",
        icon: "Hong_Kong.png",
        regex: new RegExp("香港|HK|Hong Kong|🇭🇰", 'i')
    }],
    ["SG", {
        code: "SG",
        name: "🇸🇬 新加坡",
        icon: "Singapore.png",
        regex: new RegExp("新加坡|狮城|SG|Singapore|🇸🇬", 'i')
    }],
    ["JP", {
        code: "JP",
        name: "🇯🇵 日本",
        icon: "Japan.png",
        regex: new RegExp("日本|JP|Japan|🇯🇵", 'i')
    }],
    ["US", {
        code: "US",
        name: "🇺🇸 美国",
        icon: "United_States.png",
        regex: new RegExp("美国|US|USA|United States|America|🇺🇸", 'i')
    }],
]));
// @generated:end REGION_CONFIG

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
        RESIDENTIAL: "VIP.png",
        LOW_RATE: "Speedtest.png",
        NOTIFICATION: "Apple_Mail.png",
        OFFICE: "Notion.png",
        AI: "ChatGPT.png",
        GOOGLE: "Google_Search.png",
        GAME: "Download.png",
        DOWNLOAD: "Download.png",
        AD_BLOCK: "Advertising.png",
        TAILSCALE: "Tailscale.png",
        DOMESTIC: "StreamingCN.png",
        GLOBAL: "Streaming!CN.png"
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
    RESIDENTIAL: RegexCache.buildInclude(FILTER_KEYWORDS.RESIDENTIAL),
    LOW_RATE: RegexCache.buildInclude(FILTER_KEYWORDS.LOW_RATE)
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

// ===================== Tailscale 出站 =====================

/**
 * Tailscale 出站节点配置
 *
 * 依赖 mihomo >= v1.19.25 内置的 tailscale 出站协议（基于官方 tsnet 库），
 * FlClash >= 0.8.93 才打包该内核。低于此版本整个功能不可用。
 *
 * 关于 auth-key：
 *   留空时 mihomo 会在日志中输出一个交互式登录 URL，点开授权即可。
 *   这里刻意不预填密钥 —— 覆写脚本会被 FlClash 备份文件带走，
 *   而可复用（Reusable）的 key 一旦泄露，别人可以反复注册进你的 tailnet。
 *   确认跑通后若要填，强烈建议用一次性 key（用完即废）。
 *
 * 关于 udp：
 *   NAS / SSH / web 界面等 TCP 流量不需要它，这里保持 false 以省资源。
 *   若日后要串流或玩远程游戏，把下面 udp 改成 true 即可。
 */
const TAILSCALE_CONFIG = Object.freeze({
    name: "TS-TAILSCALE",          // 内部节点名，避免与分组名混淆
    hostname: "flclash-device",    // tailnet 中显示的设备名，多设备必须改成不同名字
    stateDir: "./tailscale",       // tsnet 状态目录，登录态存于此
    acceptRoutes: true,            // 接受 tailnet 中发布的 subnet routes
    udp: false
});

/**
 * 注入 Tailscale 出站节点
 * @param {Object} params - 配置参数
 */
function injectTailscaleNode(params) {
    // 订阅异常（proxies 缺失或类型不对）时不注入，避免把异常状态变成崩溃
    if (!Array.isArray(params.proxies)) {
        log('proxies is not an array, skip Tailscale injection');
        return;
    }

    // 幂等：脚本重复执行时不重复注入
    if (params.proxies.some(p => p && p.name === TAILSCALE_CONFIG.name)) {
        log('Tailscale node already present, skip');
        return;
    }

    params.proxies.push({
        name: TAILSCALE_CONFIG.name,
        type: "tailscale",
        hostname: TAILSCALE_CONFIG.hostname,
        "state-dir": TAILSCALE_CONFIG.stateDir,
        "accept-routes": TAILSCALE_CONFIG.acceptRoutes,
        udp: TAILSCALE_CONFIG.udp,
        // 首次启动未提供 auth-key 时，mihomo 会在日志中输出交互式登录 URL，
        // 点开授权即可完成登录 —— 这样覆写脚本里不留任何密钥。
        // 如需改为免交互登录，在此追加 "auth-key": "tskey-auth-xxxx"
        // （建议用一次性 key，用完即废；切勿使用可复用 key）
        "control-url": "https://controlplane.tailscale.com"
    });

    log(`Tailscale node injected: ${TAILSCALE_CONFIG.name}`);
}

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
        //   Tailscale 注入须在节点分类之前（否则分类会把它当机场节点）
        //   代理组须在规则之前（规则的目标组必须已存在）
        const processors = [
            { name: 'Basic Options', fn: overwriteBasicOptions },
            { name: 'Sniffer', fn: overwriteSniffer },
            { name: 'Tailscale', fn: injectTailscaleNode },
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
    buildLineTypeGroups(builder, nodeClassification);
    buildNotificationGroups(builder, nodeClassification);
    buildServiceGroups(builder, nodeClassification);
    buildTrafficGroups(builder, nodeClassification);
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
 * @property {Map<string, Array<string>>} regionProxies - 地区名称 -> 该地区节点名列表（已剔除特性/通知节点）
 * @property {Array<string>} residentialProxies - 家宽节点
 * @property {Array<string>} lowRateProxies - 低倍率节点
 * @property {Array<string>} notificationProxies - 通知节点
 * @property {Array<string>} otherProxies - 未命中任何地区的普通节点
 * @property {boolean} hasResidential - 是否有家宽节点
 * @property {boolean} hasLowRate - 是否有低倍率节点
 * @property {boolean} hasNotifications - 是否有通知节点
 * @property {boolean} hasOtherProxies - 是否有其他地区节点
 */

/**
 * 处理并分类代理节点
 * 单趟遍历完成全部判定，避免同一节点被反复扫描
 * @param {Object} params - 配置参数
 * @returns {NodeClassification} 节点分类结果
 */
function classifyNodes(params) {
    log('Classifying proxy nodes...');

    const allProxies = [];
    const residentialProxies = [];
    const lowRateProxies = [];
    const notificationProxies = [];
    const otherProxies = [];
    const availableRegions = new Set();
    const regionProxies = new Map();

    (Array.isArray(params.proxies) ? params.proxies : []).forEach(proxy => {
        if (!ConfigValidator.isValidProxy(proxy)) return;

        const name = proxy.name;

        // Tailscale 出站节点不是机场节点，
        // 不得参与地区分类 / 特性判定 / 测速组，否则会污染节点列表
        if (proxy.type === 'tailscale') return;

        // 1) 特性判定（一次算完，后续复用）
        const isNotification = REGEX_PATTERNS.NOTIFICATION.test(name);
        const isResidential = REGEX_PATTERNS.RESIDENTIAL.test(name);
        const isLowRate = REGEX_PATTERNS.LOW_RATE.test(name);
        const isSpecial = isResidential || isLowRate || isNotification;

        // 2) 全部节点 = 非通知节点（家宽 / 低倍率节点保留在其中）
        if (!isNotification) {
            allProxies.push(name);
        }

        // 3) 特性分类
        if (isResidential) residentialProxies.push(name);
        if (isLowRate) lowRateProxies.push(name);
        if (isNotification) notificationProxies.push(name);

        // 4) 地区归属
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

        if (!isSpecial) {
            for (const [, region] of REGION_CONFIG) {
                if (!region.regex.test(name)) continue;
                if (!regionProxies.has(region.name)) {
                    regionProxies.set(region.name, []);
                }
                regionProxies.get(region.name).push(name);
            }
        }

        // 5) 其他地区节点：不属于任何地区、且不是特性节点
        if (!firstMatchedRegion && !isSpecial) {
            otherProxies.push(name);
        }
    });

    // availableRegions 是「选项列表」的判定依据，regionProxies 是「地区组成员」的判定依据，
    // 两者可能不一致：当某地区的节点全部是家宽/低倍率/通知节点时，该地区不会生成组，
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
        residentialProxies,
        lowRateProxies,
        notificationProxies,
        otherProxies,
        hasResidential: residentialProxies.length > 0,
        hasLowRate: lowRateProxies.length > 0,
        hasNotifications: notificationProxies.length > 0,
        hasOtherProxies: otherProxies.length > 0
    };
}

/**
 * 收集全部「节点来源类」选项：地区 / 特性 / 通知 / 全部节点
 * @param {NodeClassification} classification - 节点分类结果
 * @returns {Array<string>} 节点来源选项列表
 */
function buildNodeSourceOptions(classification) {
    const opts = [];

    for (const [, region] of REGION_CONFIG) {
        // 判定依据必须用 availableRegions（地区组真正被创建的条件），
        // 而不是 regionProxies —— 后者可能为空（如该地区节点全是特性/通知节点），
        // 直接用会导致选项里出现不存在的组名，mihomo 报 ProxyGroup loop
        if (classification.availableRegions.has(region.name)) {
            opts.push(region.name);
        }
    }

    if (classification.hasResidential) {
        opts.push(STRATEGY_NAMES.LINE_RESIDENTIAL);
    }
    if (classification.hasLowRate) {
        opts.push(STRATEGY_NAMES.LINE_LOWRATE);
    }
    if (classification.hasOtherProxies) {
        opts.push(STRATEGY_NAMES.REGION_OTHER);
    }
    if (classification.hasNotifications) {
        opts.push(STRATEGY_NAMES.LINE_NOTIFICATION);
    }

    // 「全部节点」始终可达，是手动挑节点的最后入口
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
    // 扁平化后顶层选项变多，但少一次点击，且任何一项都可达。
    const nodeSources = buildNodeSourceOptions(classification);

    const topOptions = [
        STRATEGY_NAMES.AUTO_SELECT,
        ...nodeSources,
        STRATEGY_NAMES.FAILOVER,
        STRATEGY_NAMES.DIRECT,
        STRATEGY_NAMES.REJECT
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
 * 构建线路特性策略组（家宽 / 低倍率）
 * @param {ProxyGroupBuilder} builder - 构建器
 * @param {NodeClassification} classification - 节点分类
 */
function buildLineTypeGroups(builder, classification) {
    if (classification.hasResidential) {
        builder.add(STRATEGY_NAMES.LINE_RESIDENTIAL, "select", {
            category: GROUP_CATEGORIES.LINE_TYPE,
            icon: IconManager.get(IconManager.ICONS.RESIDENTIAL),
            proxies: classification.residentialProxies,
            hidden: false
        });
    }

    if (classification.hasLowRate) {
        builder.add(STRATEGY_NAMES.LINE_LOWRATE, "select", {
            category: GROUP_CATEGORIES.LINE_TYPE,
            icon: IconManager.get(IconManager.ICONS.LOW_RATE),
            proxies: classification.lowRateProxies,
            hidden: false
        });
    }
}

/**
 * 构建通知策略组（机场的流量/到期提示节点，正常不该选）
 * @param {ProxyGroupBuilder} builder - 构建器
 * @param {NodeClassification} classification - 节点分类
 */
function buildNotificationGroups(builder, classification) {
    if (classification.hasNotifications) {
        builder.add(STRATEGY_NAMES.LINE_NOTIFICATION, "select", {
            category: GROUP_CATEGORIES.CUSTOM,
            icon: IconManager.get(IconManager.ICONS.NOTIFICATION),
            proxies: classification.notificationProxies,
            hidden: false
        });
    }
}

/**
 * 构建服务策略组
 * @param {ProxyGroupBuilder} builder - 构建器
 * @param {NodeClassification} classification - 节点分类
 */
function buildServiceGroups(builder, classification) {
    const serviceOptions = buildProxyOptions(classification, { includeReject: true });

    // 微软相关规则已并入「办公通讯」，不单独建组
    const services = [
        { name: STRATEGY_NAMES.SERVICE_OFFICE, icon: IconManager.ICONS.OFFICE },
        { name: STRATEGY_NAMES.SERVICE_AI, icon: IconManager.ICONS.AI },
        { name: STRATEGY_NAMES.SERVICE_GOOGLE, icon: IconManager.ICONS.GOOGLE },
        { name: STRATEGY_NAMES.SERVICE_GAME, icon: IconManager.ICONS.GAME }
    ];

    services.forEach(service => {
        builder.add(service.name, "select", {
            category: GROUP_CATEGORIES.SERVICE,
            proxies: serviceOptions,
            icon: IconManager.get(service.icon)
        });
    });

    // 广告拦截组固定两项，不可选其他出口
    builder.add(STRATEGY_NAMES.SERVICE_ADBLOCK, "select", {
        category: GROUP_CATEGORIES.SERVICE,
        proxies: [STRATEGY_NAMES.REJECT, STRATEGY_NAMES.DIRECT],
        icon: IconManager.get(IconManager.ICONS.AD_BLOCK)
    });
}

/**
 * 构建流量管理策略组
 * @param {ProxyGroupBuilder} builder - 构建器
 * @param {NodeClassification} classification - 节点分类
 */
function buildTrafficGroups(builder, classification) {
    const trafficOptions = buildProxyOptions(classification);

    builder.add(STRATEGY_NAMES.SERVICE_TRAFFIC, "select", {
        category: GROUP_CATEGORIES.TRAFFIC,
        proxies: trafficOptions,
        icon: IconManager.get(IconManager.ICONS.DOWNLOAD)
    });
}

/**
 * 构建默认路由策略组
 * @param {ProxyGroupBuilder} builder - 构建器
 * @param {NodeClassification} classification - 节点分类
 */
function buildDefaultRouteGroups(builder, classification) {
    const defaultOptions = buildProxyOptions(classification);
    const domesticOptions = applyDefaultOption(
        defaultOptions,
        CONFIG_MANAGER.DOMESTIC_TRAFFIC_DEFAULT
    );

    builder
        // Tailscale 开关组。「关闭」映射到 DIRECT —— mihomo 的 tailscale 出站
        // 是按需连接的，选中「关闭」时不会建立任何 tailnet 连接，零开销。
        // 一旦切到 TS-TAILSCALE 且有流量命中规则，才会真正登录 tailnet。
        // 选项顺序即默认选中项：DIRECT 在前 = 默认关闭。
        .add(STRATEGY_NAMES.TAILSCALE, "select", {
            category: GROUP_CATEGORIES.CORE,
            proxies: [STRATEGY_NAMES.DIRECT, TAILSCALE_CONFIG.name],
            icon: IconManager.get(IconManager.ICONS.TAILSCALE)
        })
        .add(STRATEGY_NAMES.DOMESTIC_TRAFFIC, "select", {
            category: GROUP_CATEGORIES.DEFAULT_ROUTE,
            proxies: domesticOptions,
            icon: IconManager.get(IconManager.ICONS.DOMESTIC)
        })
        .add(STRATEGY_NAMES.GLOBAL_TRAFFIC, "select", {
            category: GROUP_CATEGORIES.DEFAULT_ROUTE,
            proxies: defaultOptions,
            icon: IconManager.get(IconManager.ICONS.GLOBAL)
        });
}

// ===================== 规则配置模块 =====================

/**
 * 规则顺序与目标组 —— **顺序即优先级，命中即停**。
 *
 * 硬性约束：
 *   1. UnBan / DirectNoResolve 必须在所有 REJECT 之前，否则白名单形同虚设
 *   2. Tailscale 必须在 GEOSITE,cn 与 GEOIP,CN 之前，
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
        rules: [
            "Reject_no_ip",
            "Reject_domainset",
            "Reject_no_ip_drop",
            "Reject_no_ip_no_drop",
            "Reject_ip",
            "CustomRejectRules"
        ]
    },
    {
        type: "tailscale",
        group: "🔗 Tailscale",
        // Tailscale 内网。必须早于 GEOSITE,cn 与 GEOIP,CN。
        rules: [
            "IP-CIDR,100.64.0.0/10,no-resolve",
            "IP-CIDR,100.100.100.100/32,no-resolve",
            "DOMAIN-SUFFIX,ts.net"
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
            "SteamCN_ip",
            "Domestic_no_ip"
        ]
    },
    {
        type: "traffic",
        group: "📺 大流量通道",
        // 应用级规则（按进程名匹配）
        rules: [
            "applications"
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
        type: "office",
        group: "📁 办公通讯",
        // 办公通讯 + 微软 + 开发工具链（Docker / npm）+ 自定义代理
        rules: [
            "Figma_ip",
            "Notion_ip",
            "Twitter",
            "Github",
            "OneDrive",
            "Dropbox",
            "Telegram_ip",
            "Telegram_no_ip",
            "Microsoft_no_ip",
            "Docker",
            "Npm",
            { name: "CustomProxyRules", group: "📁 办公通讯" }
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
        type: "google",
        group: "🔍 谷歌服务",
        rules: [
            "YouTube",
            "GoogleFCM_ip",
            "Google",
            "GoogleFCM_no_ip"
        ]
    },
    {
        type: "cdn",
        group: "📺 大流量通道",
        // 下载 / CDN / 流媒体大流量
        rules: [
            "MicrosoftCDN_no_ip",
            "CDN_domainset",
            "CDN_no_ip",
            "Download_domainset",
            "Download_no_ip",
            "GameDownload",
            "Stream_ip"
        ]
    },
    {
        type: "game",
        group: "游戏平台",
        rules: [
            "UnrealRules",
            "Steam",
            "Origin",
            "Sony",
            "Nintendo"
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
        group: "🌍 兜底代理",
        // 兜底
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
    Github: {
        url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/refs/heads/master/rule/Clash/GitHub/GitHub.yaml",
        path: "./ruleset/toookamak/Github.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    Origin: {
        url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/EA/EA.yaml",
        path: "./ruleset/toookamak/EA.yaml",
        format: "yaml",
        behavior: "classical",
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
    Reject_ip: {
        url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/REJECT/ip/Reject_ip.yaml",
        path: "./ruleset/toookamak/Reject_ip.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    Reject_no_ip: {
        url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/REJECT/no_ip/Reject_no_ip.yaml",
        path: "./ruleset/toookamak/Reject_no_ip.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    Reject_domainset: {
        url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/REJECT/no_ip/Reject_domainset.yaml",
        path: "./ruleset/toookamak/Reject_domainset.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    Reject_no_ip_drop: {
        url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/REJECT/no_ip/Reject_no_ip_drop.yaml",
        path: "./ruleset/toookamak/Reject_no_ip_drop.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    Reject_no_ip_no_drop: {
        url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/REJECT/no_ip/Reject_no_ip_no_drop.yaml",
        path: "./ruleset/toookamak/Reject_no_ip_no_drop.yaml",
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
    MicrosoftCDN_no_ip: {
        url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/DIRECT/no_ip/MicrosoftCDN_no_ip.yaml",
        path: "./ruleset/toookamak/MicrosoftCDN_no_ip.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    Docker: {
        url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Docker/Docker.yaml",
        path: "./ruleset/toookamak/Docker.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    Telegram_ip: {
        url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/Telegram.list",
        path: "./ruleset/toookamak/Telegram.list",
        format: "text",
        behavior: "classical",
        interval: 172800
    },
    Microsoft_no_ip: {
        url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/Microsoft.list",
        path: "./ruleset/toookamak/Microsoft.list",
        format: "text",
        behavior: "classical",
        interval: 172800
    },
    Telegram_no_ip: {
        url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/Telegram.list",
        path: "./ruleset/toookamak/Telegram.list",
        format: "text",
        behavior: "classical",
        interval: 172800
    },
    Figma_ip: {
        url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/refs/heads/master/rule/Clash/Figma/Figma.yaml",
        path: "./ruleset/toookamak/Figma_ip.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    Notion_ip: {
        url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/refs/heads/master/rule/Clash/Notion/Notion.yaml",
        path: "./ruleset/toookamak/Notion_ip.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    Twitter: {
        url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Twitter/Twitter.yaml",
        path: "./ruleset/toookamak/Twitter.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    OneDrive: {
        url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/OneDrive.list",
        path: "./ruleset/toookamak/OneDrive.list",
        format: "text",
        behavior: "classical",
        interval: 172800
    },
    Dropbox: {
        url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Dropbox/Dropbox.yaml",
        path: "./ruleset/toookamak/Dropbox.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
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
    GoogleFCM_ip: {
        url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/GoogleFCM.list",
        path: "./ruleset/toookamak/GoogleFCM.list",
        format: "text",
        behavior: "classical",
        interval: 172800
    },
    GoogleFCM_no_ip: {
        url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/GoogleFCM.list",
        path: "./ruleset/toookamak/GoogleFCM.list",
        format: "text",
        behavior: "classical",
        interval: 172800
    },
    YouTube: {
        url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/YouTube.list",
        path: "./ruleset/toookamak/YouTube.list",
        format: "text",
        behavior: "classical",
        interval: 172800
    },
    Google: {
        url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/Google.list",
        path: "./ruleset/toookamak/Google.list",
        format: "text",
        behavior: "classical",
        interval: 172800
    },
    SteamCN_ip: {
        url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/SteamCN.list",
        path: "./ruleset/toookamak/SteamCN.list",
        format: "text",
        behavior: "classical",
        interval: 172800
    },
    UnrealRules: {
        url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/refs/heads/master/rule/Clash/Epic/Epic.yaml",
        path: "./ruleset/toookamak/UnrealRules.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    Steam: {
        url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Steam/Steam.yaml",
        path: "./ruleset/toookamak/Steam.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    Sony: {
        url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/Sony.list",
        path: "./ruleset/toookamak/Sony.list",
        format: "text",
        behavior: "classical",
        interval: 172800
    },
    Nintendo: {
        url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset/Nintendo.list",
        path: "./ruleset/toookamak/Nintendo.list",
        format: "text",
        behavior: "classical",
        interval: 172800
    },
    Stream_ip: {
        url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/PROXY/ip/Stream_ip.yaml",
        path: "./ruleset/toookamak/Stream_ip.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    CDN_domainset: {
        url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/PROXY/no_ip/CDN_domainset.yaml",
        path: "./ruleset/toookamak/CDN_domainset.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    CDN_no_ip: {
        url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/PROXY/no_ip/CDN_no_ip.yaml",
        path: "./ruleset/toookamak/CDN_no_ip.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    Download_domainset: {
        url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/PROXY/no_ip/Download_domainset.yaml",
        path: "./ruleset/toookamak/Download_domainset.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    Download_no_ip: {
        url: "https://raw.githubusercontent.com/RealSeek/Clash_Rule_DIY/refs/heads/mihomo/PROXY/no_ip/Download_no_ip.yaml",
        path: "./ruleset/toookamak/Download_no_ip.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    GameDownload: {
        url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/refs/heads/master/rule/Clash/Game/GameDownload/GameDownload.yaml",
        path: "./ruleset/toookamak/GameDownload.yaml",
        format: "yaml",
        behavior: "classical",
        interval: 172800
    },
    applications: {
        url: "https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/applications.txt",
        path: "./ruleset/toookamak/applications.list",
        format: "text",
        behavior: "classical",
        interval: 86400
    },
};
// @generated:end RULE_PROVIDER_DEFINITIONS

// @generated:begin INLINE_RULES
const NPM_REGISTRY_RULES = Object.freeze([
    "DOMAIN,registry.npmjs.org",
    "DOMAIN,auth.docker.io",
    "DOMAIN,registry.npmmirror.com",
    "DOMAIN,registry.npm.taobao.org",
    "DOMAIN-SUFFIX,npmmirror.com",
    "DOMAIN-SUFFIX,cnpmjs.org",
    "DOMAIN-SUFFIX,npm.taobao.org",
    "DOMAIN,registry.yarnpkg.com",
    "DOMAIN-SUFFIX,yarnpkg.com",
    "DOMAIN,registry.bower.io",
    "DOMAIN-SUFFIX,nodejs.org",
    "DOMAIN-SUFFIX,nodejs.com",
    "DOMAIN-SUFFIX,nodejs.dev",
    "DOMAIN-SUFFIX,nodejs.cn",
    "DOMAIN-KEYWORD,nodejs"
]);
// @generated:end INLINE_RULES

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

    // 内嵌规则（type: inline）：直接写进配置，不依赖任何外部 URL。
    // 用于「域名稳定、但外部源不可靠」的规则集 —— 自建仓库随时可能转私有或删除。
    providers.Npm = {
        type: "inline",
        behavior: "classical",
        payload: NPM_REGISTRY_RULES
    };

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
