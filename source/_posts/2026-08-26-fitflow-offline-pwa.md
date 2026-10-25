---
title: FitFlow 开发复盘：离线优先的健身 PWA 与 RAG AI 教练
date: 2026-08-26 10:00:00
tags:
  - PWA
  - Vue3
  - Dexie.js
  - RAG
  - 项目复盘
categories:
  - 技术分享
description: FitFlow 项目全记录：1,324 个动作的离线优先健身 PWA。Dexie.js(IndexedDB) 选型理由、动作库数据清洗、AI 教练的 RAG 注入设计、讯飞星火浏览器 CORS 代理方案、PWA 离线策略与语音播报的实现。
---

# FitFlow 开发复盘：离线优先的健身 PWA 与 RAG AI 教练

FitFlow 是一个功能比较完整的健身 Web 应用：1,324 个动作的动作库、训练计划与逐组记录、RAG 增强的 AI 教练、力量曲线与训练量分析、身体数据追踪。做它最早的动机只有一个——**健身房的信号是真的差**，地下室器械区网页半天刷不出来，所以从第一天起就定了"离线优先"的架构。

项目地址：[ChenYi1031/fitflow](https://github.com/ChenYi1031/fitflow)

## 技术选型

| 组件 | 选型 | 理由 |
|---|---|---|
| 框架 | Vue 3 (Composition API) + Vite | 熟悉，PWA 插件生态成熟 |
| 状态 | Pinia | 标配 |
| 本地存储 | Dexie.js (IndexedDB) | 见下文，关键选型 |
| 图表 | Chart.js | 轻量够用 |
| PWA | vite-plugin-pwa | precache + manifest 一站式 |
| AI | 讯飞星火（OpenAI 兼容接口） | 国内可直连，有免费额度 |

**为什么是 Dexie.js 而不是 localStorage**：训练记录这种数据是结构化的、会增长的、要按多个维度查询的（按日期、按动作、按部位）。localStorage 只有 KV、同步阻塞、5MB 上限，存几百条训练记录就到头了。IndexedDB 有索引、有事务、容量大，Dexie 又把它的回调地狱包成了干净的 Promise 链式 API：

```typescript
const db = new Dexie('FitFlow');
db.version(1).stores({
  exercises: '++id, name, *bodyParts, *equipment, *targetMuscles',
  workoutLogs: '++id, date, templateId, [templateId+date]',
  bodyMetrics: '++id, date, type',
  chatSessions: '++id, updatedAt',
});
```

`*bodyParts` 这类多值索引让"筛选胸部 + 杠铃 + 目标肌群胸大肌"变成一次 `where` 查询，配合无限滚动，1,324 条数据在本地查询毫无压力。

## 1,324 个动作的数据处理

动作库基于开源数据集，但拿来不能直接用，做了三件事：

1. **清洗与中文化**：去重、统一器械/部位分类、补中文说明
2. **GIF 懒加载**：动作演示 GIF 是大头，全部放进 `public/media`，列表页只渲染可视区域的 `<img loading="lazy">`，进入详情弹窗才真正请求
3. **建立筛选维度**：部位 / 器械 / 目标肌群三个维度都建成可检索字段，配合替代动作映射（某个动作做不了时推荐同类）

数据静态化在 JSON 里随 PWA 一起 precache，这也是"离线可用"的另一半：**代码和数据第一次加载后就全部驻留本地**。

## 训练模式：那些"小功能"才是工程量

核心训练流程听起来简单（选模板 → 逐组记录重量次数），但真正花时间的是细节：

- **组间休息倒计时**：切到后台也要准，用时间戳差值而不是 `setInterval` 累加
- **语音播报**：Web Speech API（`speechSynthesis`）报组数和休息结束提醒——练的时候没法看手机，这个功能价值极大
- **失败处理**：某组做不动了，标记失败或现场换动作，记录链不断
- **训练完成总结**：本次总容量、对比上次同动作表现，即时反馈

## AI 教练：RAG 注入本地数据

AI 教练用讯飞星火的 OpenAI 兼容接口，流式打字机输出。直接对话意义不大，价值在于 **RAG 注入**——每次提问前，从本地检索两类上下文拼进 system prompt：

1. **动作库检索**：用户问"卧推手腕疼怎么办"，检索出卧推的动作说明、目标肌群、常见错误
2. **训练记录摘要**：最近 N 次训练的动作、组数、重量、失败标记，让教练知道"你上周卧推 60kg×5×3，这周建议怎么渐进"

```typescript
async function buildCoachPrompt(question: string) {
  const actions = await searchExercises(question);       // 动作库检索
  const recent = await getRecentWorkoutSummary(5);       // 近期训练摘要
  return `${SYSTEM_PROMPT}
【动作库参考资料】${actions.map(a => a.brief).join('\n')}
【用户近期训练】${recent}
【用户提问】${question}`;
}
```

这让"AI 教练"从通用聊天机器人变成**看得见你训练数据**的教练——上下文是本地的，隐私也留在本地。

## 踩坑：星火接口的浏览器 CORS

星火的 OpenAI 兼容接口**不允许浏览器跨域直连**，前端直接 fetch 会被 CORS 拦死。解法是同源代理转发：

- **开发环境**：Vite 内置 proxy，`/api/spark` 转发到星火
- **生产环境**：Serverless 函数兜底（`netlify/functions/spark.mjs`），只做转发不落任何数据

```javascript
// vite.config.js
server: {
  proxy: {
    '/api/spark': {
      target: 'https://spark-api-open.xf-yun.com',
      changeOrigin: true,
    },
  },
}
```

用户的 API Key 只存浏览器本地（系统设置里可替换为自己的 Key），不经过任何第三方服务器——这个原则在踩过一次坑之后写进了 README。

## 数据追踪

- **1RM 力量曲线**：Epley 公式 `1RM = w × (1 + r/30)`，按动作画周趋势
- **训练量分布**：部位/动作模式的容量饼图
- **渐进超负荷预警**：连续 N 次训练同一动作重量无增长时提醒——这是把"渐进超负荷"原则直接做成了产品逻辑
- **身体数据**：体重/体脂/围度双轴趋势图

## PWA 离线策略

`vite-plugin-pwa` 的 generateSW 模式把构建产物全量 precache，运行时策略只留两条：GIF 走 StaleWhileRevalidate（更新不重要，加载速度重要），API 代理走 NetworkOnly（失败就提示离线）。所有业务数据在 IndexedDB，**断网状态下除了 AI 教练，全功能可用**。

## 小结

FitFlow 是我做过的功能密度最高的纯前端项目。最大的收获有两点：一是**离线优先是架构决策而不是功能**——它反过来决定了存储层选型、数据同步思路甚至 UI 交互；二是 AI 功能的溢价来自上下文注入（RAG），而"上下文在本地"这件事恰好和离线优先、隐私优先完全一致。
