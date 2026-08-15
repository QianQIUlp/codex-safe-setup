# Codex Safe Setup — Website

Static marketing site for [Codex Safe Setup](https://github.com/QianQIUlp/codex-safe-setup).
Built with [Astro](https://astro.build) (static output), TypeScript, native CSS, and
almost no client-side JavaScript.

- English: `/`
- 简体中文: `/zh-CN/`

## Development

```powershell
npm install
npm run dev          # local dev server
npm run build        # production build -> dist/
npm run check        # Astro/TypeScript validation
npm run validate     # post-build link/metadata/CSP audit
```

Node 24 is pinned in `.nvmrc` (matches the repository CI).

## Deployment — Cloudflare Pages

Use the Cloudflare Pages **Git integration** with these settings:

```text
Root directory:        website
Build command:         npm run build
Build output directory: dist
```

No Workers, Pages Functions, KV, D1, R2, or server runtime is used. The site is fully static.

### Site URL / canonical

Canonical URLs, Open Graph, and the sitemap are generated from the Astro `site` setting.
It defaults to `https://codex-safe-setup.pages.dev`. If you bind a custom domain, set the
`SITE` environment variable in Cloudflare Pages (e.g. `SITE=https://example.com`) and
rebuild — no code change needed.

### Security headers

Static security headers (`CSP`, `X-Content-Type-Options`, `Referrer-Policy`,
`Permissions-Policy`, `X-Frame-Options`, `Strict-Transport-Security`) are served from
[`public/_headers`](public/_headers), which Cloudflare Pages applies automatically.
The CSP matches the exact resources the site emits; re-run `npm run validate` after any
change that adds assets to confirm the policy still covers them.

## Content policy

The site is generated from the repository facts in `README.md`, `README.zh-CN.md`,
`docs/threat-model.md`, `docs/how-it-works.md`, and the released plugin. It makes no
claims beyond what the repository documents. The current supported platform is Windows.
