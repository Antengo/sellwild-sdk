import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'Sellwild SDK',
  description: 'Multi-platform SDK for native in-app advertising powered by server-side header bidding.',
  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' }],
    ['link', { rel: 'preconnect', href: 'https://fonts.googleapis.com' }],
    ['link', { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' }],
    ['link', { href: 'https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,100..1000;1,9..40,100..1000&family=IBM+Plex+Mono:wght@400;500;600&display=swap', rel: 'stylesheet' }],
  ],
  themeConfig: {
    logo: { light: '/logo.svg', dark: '/logo-dark.svg' },
    siteTitle: 'SDK',
    nav: [
      { text: 'Guide', link: '/guide/' },
      { text: 'Platforms', items: [
        { text: 'iOS', link: '/guide/ios' },
        { text: 'Android', link: '/guide/android' },
        { text: 'React Native', link: '/guide/react-native' },
        { text: 'Flutter', link: '/guide/flutter' },
      ]},
      { text: 'Prebid Server', link: '/guide/prebid-server' },
    ],
    sidebar: {
      '/guide/': [
        {
          text: 'Getting Started',
          items: [
            { text: 'Introduction', link: '/guide/' },
            { text: 'Architecture', link: '/guide/architecture' },
            { text: 'Quick Start', link: '/guide/quick-start' },
          ],
        },
        {
          text: 'Platform Guides',
          items: [
            { text: 'iOS (Swift)', link: '/guide/ios' },
            { text: 'Android (Kotlin)', link: '/guide/android' },
            { text: 'React Native', link: '/guide/react-native' },
            { text: 'Flutter', link: '/guide/flutter' },
          ],
        },
        {
          text: 'Ad Server',
          items: [
            { text: 'Prebid Server', link: '/guide/prebid-server' },
            { text: 'Configuration', link: '/guide/configuration' },
            { text: 'Privacy & Consent', link: '/guide/privacy' },
          ],
        },
        {
          text: 'Reference',
          items: [
            { text: 'API Reference', link: '/guide/api-reference' },
          ],
        },
      ],
    },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/Antengo/sellwild-sdk' },
    ],
    footer: {
      message: 'Sellwild SDK Documentation',
      copyright: 'Copyright 2026 Sellwild, Inc. All rights reserved.',
    },
    search: {
      provider: 'local',
    },
  },
})
