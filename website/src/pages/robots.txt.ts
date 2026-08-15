import type { APIContext } from 'astro';

export function GET(context: APIContext) {
  const origin = context.site?.origin ?? 'https://codex-safe-setup.pages.dev';
  return new Response(`User-agent: *\nAllow: /\n\nSitemap: ${origin}/sitemap-index.xml\n`, {
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
}

export const prerender = true;
