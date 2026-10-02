#!/usr/bin/env node
// 换订阅/换机场前的节点名匹配体检
//
// 用法：
//   node tools/check-node-match.mjs nodes.txt
//   Get-Content nodes.txt -Encoding UTF8 | node tools/check-node-match.mjs
//   （节点名一行一个，从 FlClash 的「🌍 全部节点」组里复制即可）
//
// ⚠️ PowerShell 必须显式 -Encoding UTF8。PS 5.1 的 Get-Content 默认按 ANSI(GBK) 读，
//    UTF-8 中文被读成乱码后会静默丢行（实测 31 行只剩 30），判定结果直接失真。
//
// 判定三套互相独立的节点名匹配口径，任何一套命中数变化都会影响分组结果：
//   [源]   rules/regions.yaml + rules/filters.yaml  —— 唯一事实来源，6 地区
//   [conf] targets/openclash-override-1002.conf    —— 路由器端，OpenClash eval 限制导致单正则
//   [js]   targets/flclash-override-1001.js        —— FlClash 端，JS 覆写脚本，alternation + /i
//
// 换机场只影响这一层：节点名。规则集、规则内容与代理商无关，不会因换所失效。
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');

// ---------- 从三处抽取正则，保证检查器与产物同步 ----------
function extractRegionsFromRegionsYaml() {
  const txt = read('rules/regions.yaml');
  const out = [];
  const re = /-\s*code:\s*(\w+)\s*\n\s*name:\s*"([^"]+)"[\s\S]*?filter:\s*"([^"]+)"/g;
  let m;
  while ((m = re.exec(txt))) out.push({ code: m[1], name: m[2], filter: m[3] });
  return out;
}
function extractFiltersFromYaml() {
  const lines = read('rules/filters.yaml').split(/\r?\n/);
  // 按顶层键（行首非空白且以冒号结尾）切块，再在块内找 filter: / strict:
  const blocks = new Map();
  let cur = null;
  for (const ln of lines) {
    const top = ln.match(/^([A-Za-z_][\w]*):\s*$/);
    if (top) { cur = top[1]; blocks.set(cur, []); continue; }
    if (cur) blocks.get(cur).push(ln);
  }
  const inBlock = (key) => (blocks.get(key) || []).join('\n');
  // ⚠️ 这里是 YAML 双引号标量，\\ 是「一个反斜杠」的转义。规则集正则在 YAML 里写成
  //    "0\\.\\d+x"，取到的原始文本是 0\\.\\d+x，直接喂给 RegExp 会变成「匹配字面反斜杠」，
  //    结果永远命中 0 个。必须先做 YAML 反转义还原。
  const unesc = (s) => (s === undefined ? undefined : s.replace(/\\(["\\/nrt])/g, '$1'));
  return {
    notification: unesc((inBlock('notification').match(/^\s*strict:\s*"([^"]+)"/m) || [])[1]),
    residential: unesc((inBlock('residential').match(/^\s*filter:\s*"([^"]+)"/m) || [])[1]),
    lowrate: unesc((inBlock('lowrate').match(/^\s*filter:\s*"([^"]+)"/m) || [])[1]),
    lowrateNumeric: unesc((inBlock('lowrate_numeric').match(/^\s*filter:\s*"([^"]+)"/m) || [])[1]),
    streaming: unesc((inBlock('streaming').match(/^\s*filter:\s*"([^"]+)"/m) || [])[1]),
  };
}
function extractFromConf() {
  const txt = read('targets/openclash-override-1002.conf');
  const out = { regions: [], features: {}, exclude: [] };
  const re = /- name:\s*"([^"]+)"\s*\n\s*type:\s*\S+[\s\S]*?(?=\n\s*-\ name:|\nproxy-providers:|\nrules!)/g;
  let m;
  while ((m = re.exec(txt))) {
    const body = m[0];
    const name = m[1];
    const f = (body.match(/^\s*filter:\s*'([^']+)'/m) || [])[1];
    const x = (body.match(/^\s*exclude-filter:\s*'([^']+)'/m) || [])[1];
    if (f) out.regions.push({ name, filter: f, isRegion: /[\u{1F1E6}-\u{1F1FF}]{2}/u.test(name) });
    if (x) out.exclude.push({ name, filter: x });
  }
  // conf 里带 filter 的组不止地区组（家宽/低倍率/流媒体/订阅信息也有），
  // 用「含旗帜 emoji」把地区组挑出来，特性组另走 features。
  const all = out.regions;
  out.regions = all.filter((r) => r.isRegion);
  // 特性组按名字识别
  for (const [key, name] of [['residential', '家宽'], ['lowrate', '低倍率'], ['streaming', '流媒体']]) {
    const re2 = new RegExp(`- name:\\s*"[^"]*${name}[^"]*"[\\s\\S]*?^\\s*filter:\\s*'([^']+)'`, 'm');
    out.features[key] = (txt.match(re2) || [])[1];
  }
  return out;
}
function extractFromJs() {
  const txt = read('targets/flclash-override-1001.js');
  const out = { regions: [], keywords: {} };
  const re = /\["(\w+)",\s*\{[\s\S]*?name:\s*"([^"]+)",[\s\S]*?regex:\s*new RegExp\("([^"]+)",\s*'i'\)/g;
  let m;
  while ((m = re.exec(txt))) out.regions.push({ code: m[1], name: m[2], filter: m[3] });
  const kw = (k) => (txt.match(new RegExp(`^\\s*${k}:\\s*"([^"]+)"`, 'm')) || [])[1];
  out.keywords = { notification: kw('NOTIFICATION_STRICT'), residential: kw('RESIDENTIAL'), lowrate: kw('LOW_RATE') };
  return out;
}

// ---------- 读入节点名 ----------
const arg = process.argv[2];
let raw;
if (arg) raw = readFileSync(resolve(process.cwd(), arg), 'utf8');
else raw = readFileSync(0, 'utf8');
const nodes = raw.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
if (!nodes.length) {
  console.error('没有读到节点名。用法：node tools/check-node-match.mjs nodes.txt  或从管道喂入。');
  process.exit(1);
}

// ---------- 判定 ----------
const src = { regions: extractRegionsFromRegionsYaml(), filters: extractFiltersFromYaml() };
const conf = extractFromConf();
const js = extractFromJs();

const hit = (name, pat) => (pat ? new RegExp(pat, 'i').test(name) : false);
const hitSet = (name, pats) => pats.filter((p) => new RegExp(p, 'i').test(name));

const table = [];
for (const n of nodes) {
  const row = { name: n };
  row.srcRegions = src.regions.filter((r) => hit(n, r.filter)).map((r) => r.code);
  row.confRegions = conf.regions.filter((r) => hit(n, r.filter)).map((r) => r.name);
  row.jsRegions = js.regions.filter((r) => hit(n, r.filter)).map((r) => r.code);
  row.notif = hit(n, src.filters.notification);
  row.resi = hit(n, src.filters.residential);
  row.lowCjk = hit(n, src.filters.lowrate);
  row.lowNum = hit(n, src.filters.lowrateNumeric);
  row.stream = hit(n, src.filters.streaming);
  table.push(row);
}

// 通知节点漏网嫌疑：带这些词但通知正则没抓到
const NOTIF_HINT = /剩余|流量|到期|过期|官网|订阅|套餐|公告|续费|充值|失效|重置|Exp|Traffic/i;
const suspects = table.filter((r) => !r.notif && NOTIF_HINT.test(r.name));

// 地区误判嫌疑：只靠 2 位拉丁缩写命中（Australia -> US、London? 等）
const SHORT = new Set(['US', 'USA', 'SG', 'UK', 'JP', 'HK']);
const misjudge = [];
for (const r of table) {
  const hits = hitSet(r.name, r.srcRegions.length ? (src.regions.find((x) => x.code === r.srcRegions[0])?.filter || '').split('|') : []);
  const onlyShort = hits.length > 0 && hits.every((h) => SHORT.has(h.trim()));
  if (onlyShort && !/香港|Hong Kong|🇭🇰|美国|China|US-|United|America|🇺🇸|新加坡|Singapore|狮城|🇸🇬|英国|United Kingdom|伦敦|🇬🇧|日本|Japan|🇯🇵/.test(r.name)) {
    misjudge.push({ name: r.name, via: hits.join('|'), into: r.srcRegions.join(',') });
  }
}

const pad = (s, n) => String(s).padEnd(n, ' ');
const line = (a, b, c, d) => console.log(`  ${pad(a, 20)} ${pad(b, 22)} ${pad(c, 22)} ${d}`);

console.log(`节点总数：${nodes.length}\n`);
console.log('=== 地区组命中数（[源]/[js] 为空 = 面板上不生成该组；[conf] 为空 = 路由器端整组回落 DIRECT）===');
console.log(`  ${pad('地区', 20)} ${pad('[源] regions.yaml', 22)} ${pad('[conf] 单正则', 22)} [js] REGION_CONFIG`);
// 三套口径按「旗帜 emoji」对齐同一地区；conf 用组名、另两套用 code
const flagOf = (name) => (name.match(/[\u{1F1E6}-\u{1F1FF}]{2}/u) || [])[0] || name;
for (const r of src.regions) {
  const flag = flagOf(r.name);
  const s = table.filter((x) => x.srcRegions.includes(r.code)).length;
  const cf = table.filter((x) => x.confRegions.some((n) => flagOf(n) === flag)).length;
  const j = table.filter((x) => x.jsRegions.includes(r.code)).length;
  const notes = [];
  if (s === 0) notes.push('[源] 为空');
  if (j === 0 && s > 0) notes.push('[js] 无此地区配置');
  if (cf !== s) notes.push(`[conf] 与源差 ${cf - s}`);
  line(`${r.name}`, String(s), String(cf), String(j) + (notes.length ? '  ' + notes.join(' / ') : ''));
}
// 只在 conf 或只在 js 出现的地区
for (const c of conf.regions) {
  const flag = flagOf(c.name);
  if (!src.regions.some((r) => flagOf(r.name) === flag)) line(c.name, '-', String(table.filter((x) => x.confRegions.includes(c.name)).length), '[源] 无此地区');
}
for (const r of js.regions) {
  if (!src.regions.some((s2) => s2.code === r.code)) line(r.name, '-', '-', `[js] 独有：${table.filter((x) => x.jsRegions.includes(r.code)).length}`);
}

console.log('\n=== 特性组命中数 ===');
console.log(`  ${pad('特性', 20)} ${pad('[源] filters.yaml', 22)} ${pad('[conf] 单正则', 22)} [js] FILTER_KEYWORDS`);
const featRows = [
  ['家宽/原生', 'resi', conf.features.residential, js.keywords.residential],
  ['低倍率(中文词)', 'lowCjk', null, js.keywords.lowrate],
  ['低倍率(数字写法)', 'lowNum', conf.features.lowrate, null],
  ['流媒体/解锁', 'stream', conf.features.streaming, null],
];
for (const [label, key, confPat, jsPat] of featRows) {
  const s = table.filter((r) => r[key]).length;
  const c = confPat ? table.filter((r) => hit(r.name, confPat)).length : -1;
  const j = jsPat ? table.filter((r) => hit(r.name, jsPat)).length : -1;
  const notes = [];
  if (j === 0 && s > 0) notes.push('[js] 无此 matcher/组');
  if (c < 0) notes.push('[conf] 无此组');
  line(label, String(s), c < 0 ? '—' : String(c), (j < 0 ? '—' : String(j)) + (notes.length ? '  ' + notes.join(' / ') : ''));
}

console.log('\n=== 通知节点（应被排除出全部节点/测速组）===');
const notifSrc = table.filter((r) => r.notif).length;
const notifConf = table.filter((r) => hit(r.name, conf.exclude[0]?.filter)).length;
const notifJs = table.filter((r) => hit(r.name, js.keywords.notification)).length;
line('命中数', `[源] ${notifSrc}`, `[conf] ${notifConf}`, `[js] ${notifJs}`);
if (suspects.length) {
  console.log('  ⚠️ 看着像通知节点但关键词表没抓到 —— 逐个看三套口径各自漏不漏：');
  for (const s of suspects) {
    const c = hit(s.name, conf.exclude[0]?.filter);
    const j = hit(s.name, js.keywords.notification);
    const missed = [!c && 'conf', !j && 'js'].filter(Boolean);
    console.log(`     - ${s.name}${missed.length ? `   漏：${missed.join(' / ')}（会留在测速组里）` : '   conf 与 js 都已排除'}`);
  }
}

console.log('\n=== 地区归属需人工确认（只靠 2 位拉丁缩写命中，命名习惯差异容易误判）===');
if (!misjudge.length) console.log('  （无）');
for (const m of misjudge) console.log(`  ? ${m.name}   命中 ${m.via} -> 归入 ${m.into}`);

const none = table.filter((r) => r.srcRegions.length === 0 && !r.resi && !r.lowCjk && !r.lowNum && !r.notif);
console.log(`\n=== 未命中任何地区/特性的节点：${none.length} 个（js 归入「🌐 其他地区」）===`);
for (const n of none) console.log(`  - ${n.name}`);
