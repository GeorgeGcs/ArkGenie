import { defineConfig } from 'vitepress'

export default defineConfig({
  lang: 'zh-CN',
  title: 'ArkGenie',
  description: 'HarmonyOS AI 对话与 A2UI 生成式 UI 组件套件',
  themeConfig: {
    nav: [
      { text: '指南', link: '/guide/quick-start' },
      { text: 'API', link: '/guide/api' }
    ],
    sidebar: [
      { text: '开始使用', items: [{ text: '快速开始', link: '/guide/quick-start' }, { text: 'API 概览', link: '/guide/api' }] },
      { text: '生成式 UI', items: [{ text: 'A2UI 安全模型', link: '/guide/a2ui' }] }
    ]
  }
})
