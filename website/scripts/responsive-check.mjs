// Visual/responsive audit for the built site using a locally installed Chromium.
// Usage: node scripts/responsive-check.mjs  (run from website/, after `npm run build`)
import { createServer } from 'node:http';
import { readFileSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright-core';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');
const shots = join(root, '.tmp-shots');
mkdirSync(shots, { recursive: true });

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.xml': 'application/xml',
  '.txt': 'text/plain; charset=utf-8',
};

const server = createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  let path = decodeURIComponent(url.pathname);
  if (path.endsWith('/')) path += 'index.html';
  let file = join(dist, path);
  if (!existsSync(file)) {
    res.writeHead(404);
    res.end('not found');
    return;
  }
  res.writeHead(200, {
    'Content-Type': MIME[extname(file)] ?? 'application/octet-stream',
    'Content-Security-Policy':
      "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'none'; font-src 'self'; manifest-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
  });
  res.end(readFileSync(file));
});

await new Promise((resolve) => server.listen(4173, resolve));

const chromePath = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const browser = await chromium.launch({
  executablePath: chromePath,
  headless: true,
});
const context = await browser.newContext({
  permissions: ['clipboard-read', 'clipboard-write'],
});
const page = await context.newPage();

const consoleErrors = [];
page.on('console', (msg) => {
  if (msg.type() === 'error') consoleErrors.push(msg.text());
});
page.on('pageerror', (err) => consoleErrors.push(`pageerror: ${err.message}`));

let failures = 0;
function check(name, ok, detail = '') {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  [${detail}]` : ''}`);
  if (!ok) failures++;
}

const viewports = [
  { name: 'mobile-375', width: 375, height: 812 },
  { name: 'tablet-768', width: 768, height: 1024 },
  { name: 'desktop-1440', width: 1440, height: 900 },
];

for (const route of ['/', '/zh-CN/']) {
  for (const vp of viewports) {
    const tag = `${route.replaceAll('/', '_').replaceAll('_', '') || 'en'}-${vp.name}`;
    await page.setViewportSize({ width: vp.width, height: vp.height });
    await page.goto(`http://localhost:4173${route}`, { waitUntil: 'networkidle' });

    const layout = await page.evaluate(() => {
      const doc = document.documentElement;
      const h1 = document.querySelector('h1');
      const header = document.querySelector('.site-header');
      const navMenu = document.querySelector('.nav-menu');
      const heroVisual = document.querySelector('.boundary-visual');
      const rect = h1 ? h1.getBoundingClientRect() : null;
      return {
        scrollW: doc.scrollWidth,
        innerW: window.innerWidth,
        h1Top: rect ? Math.round(rect.top) : null,
        h1VisibleInFirstViewport: rect ? rect.top < window.innerHeight * 0.9 : false,
        headerH: header ? header.getBoundingClientRect().height : 0,
        menuVisible: navMenu ? getComputedStyle(navMenu).display !== 'none' : null,
        bodyFont: getComputedStyle(document.body).fontFamily.slice(0, 40),
        bodyBg: getComputedStyle(document.body).backgroundColor,
        bodyColor: getComputedStyle(document.body).color,
        mutedColor: getComputedStyle(document.querySelector('.sec-lead')).color,
        lang: document.documentElement.lang,
      };
    });

    check(`${tag}: no horizontal scroll`, layout.scrollW <= layout.innerW, `scrollW=${layout.scrollW} innerW=${layout.innerW}`);
    check(`${tag}: h1 visible in first viewport`, layout.h1VisibleInFirstViewport, `h1 top=${layout.h1Top}`);
    check(`${tag}: page lang set`, layout.lang !== '', layout.lang);
    if (vp.name === 'mobile-375') {
      check(`${tag}: mobile menu shown`, layout.menuVisible === true);
    } else if (vp.name === 'desktop-1440') {
      check(`${tag}: full nav on desktop`, layout.menuVisible === false);
    }

    await page.screenshot({ path: join(shots, `${tag}.png`), fullPage: false });
    await page.screenshot({ path: join(shots, `${tag}-full.png`), fullPage: true });
  }
}

// contrast check (WCAG ratio) for key colors
const colors = await page.evaluate(() => {
  const get = (sel) => {
    const el = document.querySelector(sel);
    if (!el) return null;
    const s = getComputedStyle(el);
    return { color: s.color, bg: getComputedStyle(document.body).backgroundColor };
  };
  return {
    body: get('body'),
    secLead: get('.sec-lead'),
    link: get('a.link-arrow'),
    mutedMono: get('.eyebrow'),
  };
});

function luminance(rgb) {
  const m = rgb.match(/(\d+),\s*(\d+),\s*(\d+)/);
  if (!m) return 0;
  const [r, g, b] = [+m[1], +m[2], +m[3]].map((v) => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

for (const [name, pair] of Object.entries(colors)) {
  if (!pair) continue;
  const l1 = luminance(pair.color);
  const l2 = luminance(pair.bg);
  const ratio = (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
  check(`contrast: ${name} >= 4.5`, ratio >= 4.5, `${ratio.toFixed(2)}:1`);
}

// reduced motion: block-pulse must be disabled
await page.emulateMedia({ reducedMotion: 'reduce' });
await page.setViewportSize({ width: 1440, height: 900 });
await page.goto('http://localhost:4173/', { waitUntil: 'networkidle' });
const anim = await page.evaluate(() => {
  const el = document.querySelector('.b-block');
  if (!el) return null;
  const s = getComputedStyle(el);
  return { duration: s.animationDuration, iteration: s.animationIterationCount };
});
const animDisabled =
  !!anim && anim.iteration === '1' && (parseFloat(anim.duration) ?? 1) <= 0.001;
check('reduced motion: pulse disabled', animDisabled, `${anim?.duration} x ${anim?.iteration}`);

// copy button
await page.emulateMedia({ reducedMotion: null });
await page.goto('http://localhost:4173/', { waitUntil: 'networkidle' });
await page.evaluate(() => {
  const btn = document.querySelector('[data-copy]');
  btn?.click();
});
await page.waitForTimeout(300);
const copiedLabel = await page.evaluate(() => document.querySelector('[data-copy]')?.textContent);
check('copy button: shows copied feedback', copiedLabel === 'Copied', copiedLabel);

check('no console errors', consoleErrors.length === 0, consoleErrors.join(' | ') || 'none');

console.log('');
console.log(`Screenshots in ${shots}`);
console.log(`Failures: ${failures}`);
await browser.close();
server.close();
process.exitCode = failures > 0 ? 1 : 0;
