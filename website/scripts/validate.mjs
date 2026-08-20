// Post-build audit for the Codex Safe Setup website.
// Usage: node scripts/validate.mjs   (run from website/, after `npm run build`)
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');

const results = [];
let failures = 0;
let warnings = 0;

function check(name, ok, detail = '') {
  results.push({ name, ok, detail });
  if (!ok) failures++;
}

function warn(name, ok, detail = '') {
  results.push({ name, ok: null, detail });
  if (!ok) warnings++;
}

function htmlFiles() {
  const files = [];
  for (const entry of readdirSync(dist, { recursive: true })) {
    if (entry.endsWith('.html')) files.push(join(dist, entry));
  }
  return files;
}

const pages = htmlFiles();

// ---------------------------------------------------------------- 1. routes
const expectedFiles = [
  'index.html',
  join('zh-CN', 'index.html'),
  'robots.txt',
  'sitemap-index.xml',
  'sitemap-0.xml',
  '_headers',
  'favicon.svg',
];
for (const f of expectedFiles) {
  check(`route: /${f.replaceAll('\\', '/')}`, existsSync(join(dist, f)));
}
check('route: only two HTML pages', pages.length === 2, `${pages.length} html files`);

// ---------------------------------------------------------------- 2. metadata
for (const page of pages) {
  const html = readFileSync(page, 'utf8');
  const rel = page.replace(dist, '').replaceAll('\\', '/');
  const hasTitle = /<title>[^<]+<\/title>/.test(html);
  const hasDescription = /<meta name="description" content="[^"]+"/.test(html);
  const hasCanonical = /<link rel="canonical" href="https:\/\/[^"]+"/.test(html);
  const hreflangEn = /<link rel="alternate" hreflang="en" href="https:\/\/[^"]*\/"/.test(html);
  const hreflangZh = /<link rel="alternate" hreflang="zh-CN" href="https:\/\/[^"]*\/zh-CN\/"/.test(html);
  const hreflangX = /<link rel="alternate" hreflang="x-default"/.test(html);
  const hasOg = /<meta property="og:title" content="[^"]+"/.test(html) && /<meta property="og:description"/.test(html) && /<meta property="og:locale"/.test(html);
  const hasTwitter = /<meta name="twitter:card" content="summary"/.test(html);
  const hasFavicon = /<link rel="icon"[^>]*favicon\.svg/.test(html);
  const langMatch = /<html lang="([a-zA-Z-]+)"/.exec(html);
  const langOk = rel.includes('zh-CN') ? langMatch?.[1] === 'zh-CN' : langMatch?.[1] === 'en';
  const singleH1 = (html.match(/<h1[ >]/g) ?? []).length === 1;
  const canonical = /<link rel="canonical" href="([^"]+)"/.exec(html)?.[1];
  const canonicalOk = rel.includes('zh-CN') ? canonical?.endsWith('/zh-CN/') : canonical === 'https://codex-safe-setup.pages.dev/';
  check(`meta: ${rel} title`, hasTitle);
  check(`meta: ${rel} description`, hasDescription);
  check(`meta: ${rel} canonical (${canonical})`, canonicalOk);
  check(`meta: ${rel} hreflang en/zh/x-default`, hreflangEn && hreflangZh && hreflangX);
  check(`meta: ${rel} og+twitter`, hasOg && hasTwitter);
  check(`meta: ${rel} favicon`, hasFavicon);
  check(`meta: ${rel} html lang`, langOk, `lang="${langMatch?.[1]}"`);
  check(`meta: ${rel} single h1`, singleH1);
}

// ---------------------------------------------------------------- 3. internal links
const enHtml = readFileSync(join(dist, 'index.html'), 'utf8');
const zhHtml = readFileSync(join(dist, 'zh-CN', 'index.html'), 'utf8');
const anchorIds = new Set([...enHtml.matchAll(/id="([^"]+)"/g)].map((m) => m[1]));

const internalLinks = new Set();
const externalLinks = new Set();
const hrefs = [];
for (const page of pages) {
  const html = readFileSync(page, 'utf8');
  for (const m of html.matchAll(/<a[^>]+href="([^"]+)"/g)) hrefs.push({ page: page.replace(dist, ''), href: m[1] });
}
for (const { page, href } of hrefs) {
  if (href.startsWith('http')) {
    externalLinks.add(href);
    continue;
  }
  if (href.startsWith('mailto:') || href.startsWith('#')) continue;
  const [pathPart, hash] = href.split('#');
  if (hash && pathPart === '') {
    check(`internal: ${page} #${hash}`, anchorIds.has(hash), href);
    continue;
  }
  const target = join(dist, pathPart.replace(/^\//, ''));
  check(`internal: ${page} -> ${href}`, existsSync(target), href);
}

// ---------------------------------------------------------------- 4. external links
const urlCounts = new Map();
for (const href of externalLinks) urlCounts.set(href, (urlCounts.get(href) ?? 0) + 1);
const seen = [];
for (const href of [...urlCounts.keys()].sort()) {
  try {
    const res = await fetch(href, {
      method: 'GET',
      redirect: 'follow',
      signal: AbortSignal.timeout(30000),
      headers: { 'User-Agent': 'codex-safe-setup-site-validation' },
    });
    seen.push({ href, status: res.status });
    check(`external: ${href}`, res.status >= 200 && res.status < 400, `HTTP ${res.status}`);
  } catch (err) {
    warn(`external: ${href}`, false, `${err?.cause?.code ?? err?.message ?? err}`);
  }
}

// ---------------------------------------------------------------- 5. sitemap / robots
const sitemap = readFileSync(join(dist, 'sitemap-0.xml'), 'utf8');
check('sitemap: en entry', /<loc>https:\/\/codex-safe-setup\.pages\.dev\/<\/loc>/.test(sitemap));
check('sitemap: zh-CN entry', /<loc>https:\/\/codex-safe-setup\.pages\.dev\/zh-CN\/<\/loc>/.test(sitemap));
check('sitemap: en hreflang alternate', /hreflang="en"/.test(sitemap));
check('sitemap: zh-CN hreflang alternate', /hreflang="zh-CN"/.test(sitemap));
const robots = readFileSync(join(dist, 'robots.txt'), 'utf8');
check('robots: sitemap line', robots.includes('Sitemap: https://codex-safe-setup.pages.dev/sitemap-index.xml'), robots.replace(/\n/g, ' | '));

// ---------------------------------------------------------------- 6. CSP audit
const headers = readFileSync(join(dist, '_headers'), 'utf8');
check('headers: CSP present', /Content-Security-Policy:/.test(headers));
check('headers: script-src self only', /script-src 'self'/.test(headers) && !headers.includes('unsafe-inline'));
check('headers: no unsafe-eval', !headers.includes('unsafe-eval'));
check('headers: frame-ancestors none', headers.includes("frame-ancestors 'none'"));
check('headers: X-Content-Type-Options', headers.includes('X-Content-Type-Options: nosniff'));
check('headers: Referrer-Policy', headers.includes('Referrer-Policy:'));
check('headers: Permissions-Policy', headers.includes('Permissions-Policy:'));
check('headers: X-Frame-Options', headers.includes('X-Frame-Options: DENY'));
check('headers: HSTS', headers.includes('Strict-Transport-Security'));

let inlineScripts = 0;
let inlineStyles = 0;
let externalResources = new Set();
for (const page of pages) {
  const html = readFileSync(page, 'utf8');
  inlineScripts += (html.match(/<script(?![^>]*src=)/g) ?? []).length;
  inlineStyles += (html.match(/<style/g) ?? []).length;
  for (const m of html.matchAll(/(?:src|href)="(\/_astro\/[^"]+)"/g)) externalResources.add(m[1]);
}
check('csp: no inline scripts in HTML', inlineScripts === 0, `${inlineScripts} inline`);
check('csp: no inline styles in HTML', inlineStyles === 0, `${inlineStyles} inline`);
check('csp: bundled assets exist on disk', [...externalResources].every((p) => existsSync(join(dist, p))), [...externalResources].join(', '));

// ---------------------------------------------------------------- 7. third-party absence
const thirdPartyPatterns = [
  'google-analytics', 'googletagmanager', 'doubleclick', 'facebook.net', 'segment.io',
  'hotjar', 'clarity.ms', 'matomo', 'plausible.io', 'simpleanalytics', 'fonts.googleapis',
  'fonts.gstatic', 'cdn.jsdelivr', 'unpkg.com', 'jsdelivr.net', 'cloudflareinsights', 'beacon',
  'mixpanel', 'amplitude', 'sentry.io', 'stripe.com', 'intercom.io',
];
let thirdPartyHits = [];
for (const page of pages) {
  const html = readFileSync(page, 'utf8');
  for (const pat of thirdPartyPatterns) {
    if (html.includes(pat)) thirdPartyHits.push(`${page}: ${pat}`);
  }
}
check('privacy: no analytics/tracker references', thirdPartyHits.length === 0, thirdPartyHits.join(', ') || 'none');

// external resource loads (img/script/link/iframe/font) must be same-origin
const crossOriginResources = [];
for (const page of pages) {
  const html = readFileSync(page, 'utf8');
  for (const m of html.matchAll(/<(?:img|script|link|iframe|source)[^>]+(?:src|href)="(https?:\/\/[^"]+)"/g)) {
    const u = m[1];
    if (!u.startsWith('https://codex-safe-setup.pages.dev')) crossOriginResources.push(`${page}: ${u}`);
  }
}
check('privacy: no cross-origin resource loads', crossOriginResources.length === 0, crossOriginResources.join(', ') || 'none');

// ---------------------------------------------------------------- 8. content facts
const enFacts = [
  ['install cmd 1', 'codex plugin marketplace add QianQIUlp/codex-safe-setup --ref main'],
  ['install cmd 2', 'codex plugin add codex-safe-setup@codex-safe-setup'],
  ['requires Codex CLI', 'DynamicUi and StrictProfile require Codex CLI 0.138.0 or newer'],
  ['PowerShell 7', 'PowerShell 7'],
  ['prompt text', 'Use $codex-safe-setup to audit my current permissions'],
  ['sha256 note', 'Get-FileHash -Algorithm SHA256'],
  ['principle', 'Approval is not a security boundary.'],
  ['test: config read', 'build-config.json'],
  ['test: copies from root', 'release\\latest'],
  ['test: answer lines', 'Remove-Item -Path'],
  ['group: agent accidents', 'Agent accidents'],
  ['group: permission boundary', 'More permission than the task needs'],
  ['example: sync erases', 'git clean -fdx'],
  ['example: encoded', 'EncodedCommand'],
  ['example: persistence', 'upd.ps1'],
  ['incident: relay injection', 'relay service'],
  ['incident: environment monitoring', 'environment monitoring'],
  ['semantic: resolves to root', 'root of the current drive'],
  ['semantic: config assignment', '$base = $config.outputDirectory'],
  ['h1', 'Safer Codex on Windows.'],
  ['disclaimer', 'Not affiliated with OpenAI'],
  ['status PASS', 'PASS'],
  ['status PARTIAL', 'PARTIAL'],
  ['status FAIL', 'FAIL'],
  ['status NOT CONTROLLED', 'NOT CONTROLLED'],
  ['execpolicy evidence', 'codex execpolicy check'],
  ['checkpoint refs', 'refs/codex-safe/checkpoints/*'],
  ['BoundedAutonomy', 'BoundedAutonomy'],
  ['modes: AskMe', 'AskMe'],
  ['modes: AutoReview', 'AutoReview'],
  ['verification: canary', 'canary'],
  ['install flow: read-only', 'Read-only assessment'],
  ['exposed: revoke', 'Revoke or rotate'],
  ['facts: validators', 'Skill and Plugin validators'],
  ['Windows tag', 'Windows'],
];
for (const [name, needle] of enFacts) {
  check(`content en: ${name}`, enHtml.includes(needle));
}
check('content en: no staged $base = "" init', !enHtml.includes('$base = &quot;&quot;'));
check('content zh: no staged $base = "" init', !zhHtml.includes('$base = &quot;&quot;'));
const zhFacts = [
  ['zh title', '在 Windows 上更安全地使用 Codex'],
  ['zh principle', '审批不是安全边界。'],
  ['zh test: intro', '先通读整段脚本'],
  ['zh test: answer', 'Remove-Item -Path'],
  ['zh group: agent accidents', '风险一'],
  ['zh group: permission boundary', '权限大于任务所需'],
  ['zh example: encoded', 'EncodedCommand'],
  ['zh example: persistence', 'upd.ps1'],
  ['zh incident: relay', '中转站'],
  ['zh incident: chain of thought', '思维链'],
  ['zh semantic: base var', '$base = '],
  ['zh modes: AskMe', 'AskMe'],
  ['zh modes: AutoReview', 'AutoReview'],
  ['zh verification: canary', 'canary'],
  ['zh install flow', '只读评估'],
  ['zh exposed: revoke', '吊销或轮换'],
  ['zh facts: checksum', 'SHA-256 校验文件'],
  ['zh install', 'codex plugin marketplace add QianQIUlp/codex-safe-setup --ref main'],
  ['zh requires', 'DynamicUi 与 StrictProfile 都需要 Codex CLI 0.138.0 或更高版本'],
  ['zh prompt', '$codex-safe-setup 审计我当前的 Codex 权限'],
  ['zh sha', 'Get-FileHash -Algorithm SHA256'],
  ['zh threat cta', '阅读威胁模型'],
  ['zh NOT CONTROLLED', 'NOT CONTROLLED'],
  ['zh disclaimer', '与 OpenAI 无关联'],
];
for (const [name, needle] of zhFacts) {
  check(`content zh: ${name}`, zhHtml.includes(needle));
}

// ---------------------------------------------------------------- summary
let i = 1;
for (const r of results) {
  const tag = r.ok === null ? 'WARN' : r.ok ? 'PASS' : 'FAIL';
  console.log(`${tag}  ${r.name}${r.detail ? `  [${r.detail}]` : ''}`);
}
console.log('');
console.log(`Total: ${results.length} checks, ${failures} failures, ${warnings} warnings.`);
process.exitCode = failures > 0 ? 1 : 0;
