import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

const site =
  (process.env.SITE && process.env.SITE.trim().replace(/\/+$/, '')) ||
  'https://codex-safe-setup.pages.dev';

export default defineConfig({
  site,
  output: 'static',
  trailingSlash: 'ignore',
  compressHTML: true,
  vite: {
    build: {
      assetsInlineLimit: 0,
    },
  },
  integrations: [
    sitemap({
      i18n: {
        defaultLocale: 'en',
        locales: {
          en: 'en',
          'zh-CN': 'zh-CN',
        },
      },
    }),
  ],
});
