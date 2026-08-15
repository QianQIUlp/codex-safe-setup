// Geometric layout audit (compensates for screenshot review).
// Usage: node scripts/layout-check.mjs  (run from website/, after `npm run build`)
import { createServer } from 'node:http';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname, extname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright-core';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const dist = join(root, 'dist');

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
  const file = join(dist, path);
  if (!existsSync(file)) {
    res.writeHead(404);
    res.end('not found');
    return;
  }
  res.writeHead(200, { 'Content-Type': MIME[extname(file)] ?? 'application/octet-stream' });
  res.end(readFileSync(file));
});
await new Promise((resolve) => server.listen(4174, resolve));

const browser = await chromium.launch({
  executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  headless: true,
});
const page = await browser.newPage();

let failures = 0;
function check(name, ok, detail = '') {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  [${detail}]` : ''}`);
  if (!ok) failures++;
}

// --- 375px mobile: hero visual stacking order & no overlap
await page.setViewportSize({ width: 375, height: 812 });
await page.goto('http://localhost:4174/', { waitUntil: 'networkidle' });
const m = await page.evaluate(() => {
  const box = document.querySelector('.boundary-visual .b-box').getBoundingClientRect();
  const crossing = document.querySelector('.boundary-visual .b-crossing').getBoundingClientRect();
  const denied = document.querySelector('.boundary-visual .b-denied').getBoundingClientRect();
  const heroGrid = getComputedStyle(document.querySelector('.hero-grid'));
  return {
    box,
    crossing,
    denied,
    heroCols: heroGrid.gridTemplateColumns,
    overflow: document.documentElement.scrollWidth - window.innerWidth,
  };
});
check('m375: boundary box above crossing', m.box.bottom <= m.crossing.top + 1);
check('m375: crossing above denied strip', m.crossing.bottom <= m.denied.top + 1);
check('m375: hero is single column', m.heroCols.split(' ').length === 1, m.heroCols);

// --- 1440px desktop: hero 2 columns, visual right of copy
await page.setViewportSize({ width: 1440, height: 900 });
await page.goto('http://localhost:4174/', { waitUntil: 'networkidle' });
const d = await page.evaluate(() => {
  const copy = document.querySelector('.hero-copy').getBoundingClientRect();
  const visual = document.querySelector('.boundary-visual').getBoundingClientRect();
  const grid = getComputedStyle(document.querySelector('.hero-grid'));
  return { copy, visual, cols: grid.gridTemplateColumns.split(' ').length };
});
check('d1440: hero two columns', d.cols === 2, `${d.cols} cols`);
check('d1440: visual right of copy', d.visual.left >= d.copy.right - 1);
check('d1440: visual not overflowing column', d.visual.right <= 1440);

// --- clipping audit: no text clipped inside key containers
for (const route of ['/', '/zh-CN/']) {
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto(`http://localhost:4174${route}`, { waitUntil: 'networkidle' });
  const clipped = await page.evaluate(() => {
    const bad = [];
    for (const el of document.querySelectorAll('p, li, h1, h2, h3, span, a, td, pre')) {
      if (el.scrollWidth > el.clientWidth + 1 && el.clientWidth > 0) {
        const cls = el.className && typeof el.className === 'string' ? el.className : el.tagName;
        bad.push(`${el.tagName}.${cls.slice(0, 24)}:${el.scrollWidth}>${el.clientWidth}`);
      }
    }
    return bad.slice(0, 5);
  });
  check(`${route} 375: no clipped text`, clipped.length === 0, clipped.join(' | ') || 'none');
}

// --- keyboard focus visibility: focus the copy button and measure outline
await page.setViewportSize({ width: 1440, height: 900 });
await page.goto('http://localhost:4174/', { waitUntil: 'networkidle' });
const focus = await page.evaluate(() => {
  const btn = document.querySelector('[data-copy]');
  btn.focus();
  const s = getComputedStyle(btn);
  return { outline: s.outlineStyle, width: s.outlineWidth };
});
check('focus: visible outline on copy button', focus.outline !== 'none' && parseFloat(focus.width) >= 2, `${focus.outline} ${focus.width}`);

// --- details menu keyboard open (mobile viewport where menu is visible)
await page.setViewportSize({ width: 375, height: 812 });
await page.goto('http://localhost:4174/', { waitUntil: 'networkidle' });
const details = await page.evaluate(() => {
  const el = document.querySelector('.nav-menu');
  const sum = el.querySelector('summary');
  sum.focus();
  return { focused: document.activeElement === sum };
});
check('a11y: details summary focusable', details.focused);
await page.keyboard.press('Enter');
const opened = await page.evaluate(() => document.querySelector('.nav-menu').open);
check('a11y: Enter opens menu', opened);
await page.keyboard.press('Tab');
const tabTarget = await page.evaluate(() => {
  const a = document.activeElement;
  return a ? `${a.tagName} ${a.textContent.trim().slice(0, 30)}` : 'none';
});
check('a11y: Tab moves into opened menu', tabTarget.startsWith('A'), tabTarget);

// --- semantic heading order
const order = await page.evaluate(() => {
  const seq = [...document.querySelectorAll('h1,h2,h3')].map((h) => h.tagName);
  let prev = 0;
  for (const h of seq) {
    const lvl = +h[1];
    if (lvl > prev + 1) return { ok: false, seq };
    prev = lvl;
  }
  return { ok: true, seq };
});
check('semantics: heading order h1->h2->h3', order.ok, order.seq.join(' '));

// --- structural system: rail, bands, module alternation
await page.setViewportSize({ width: 1440, height: 900 });
await page.goto('http://localhost:4174/', { waitUntil: 'networkidle' });
const structure = await page.evaluate(() => {
  const ids = ['principle', 'limits', 'before-after', 'verification', 'install', 'not-protected', 'open-source'];
  const bg = (el) => getComputedStyle(el).backgroundColor;
  const bands = ids.map((id) => ({ id, white: bg(document.getElementById(id)) === 'rgb(255, 255, 255)' }));
  const railNodes = [...document.querySelectorAll('.rail-node')].map((n) => n.textContent.trim());
  const ghostNos = [...document.querySelectorAll('.sec-no')].map((n) => n.textContent.trim());
  const moduleOrder = [...document.querySelectorAll('.limit-module')].map((m) => {
    const copy = m.querySelector('.limit-copy').getBoundingClientRect();
    const vis = m.querySelector('.b-mini').getBoundingClientRect();
    return vis.left < copy.left ? 'left' : 'right';
  });
  const expectedAlt = ['white', 'plain', 'white', 'plain', 'white', 'plain', 'white'];
  const bandOk = bands.every((b, i) => b.white === (expectedAlt[i] === 'white'));
  return { bandOk, bands: bands.map((b) => `${b.id}:${b.white ? 'W' : 'P'}`).join(' '), railNodes, ghostNos, moduleOrder };
});
check('structure: bands alternate white/plain', structure.bandOk, structure.bands);
check('structure: rail nodes 01..07', structure.railNodes.join(',') === '01,02,03,04,05,06,07', structure.railNodes.join(','));
check('structure: ghost numbers 01..07', structure.ghostNos.join(',') === '01,02,03,04,05,06,07', structure.ghostNos.join(','));
check('structure: limit modules alternate', structure.moduleOrder.join(',') === 'right,left,right', structure.moduleOrder.join(','));
const splitOk = await page.evaluate(() => {
  const title = document.querySelector('#install .sec-title').getBoundingClientRect();
  const lead = document.querySelector('#install .sec-lead').getBoundingClientRect();
  return lead.left >= title.right - 1 && Math.abs(lead.bottom - title.bottom) < 60;
});
check('structure: install split header (lead right of title)', splitOk);

// --- anchor targets exist for every internal # link
const anchors = await page.evaluate(() => {
  const ids = new Set([...document.querySelectorAll('[id]')].map((e) => e.id));
  const missing = [];
  for (const a of document.querySelectorAll('a[href^="#"], a[href*="/#"]')) {
    const hash = a.getAttribute('href').split('#')[1];
    if (hash && !ids.has(hash)) missing.push(hash);
  }
  return missing;
});
check('links: all in-page anchors resolve', anchors.length === 0, anchors.join(',') || 'none');

console.log('');
console.log(`Failures: ${failures}`);
await browser.close();
server.close();
process.exitCode = failures > 0 ? 1 : 0;
