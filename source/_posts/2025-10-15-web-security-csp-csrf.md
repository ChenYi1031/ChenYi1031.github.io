---
title: Web 安全实践：CSP、SameSite、CSRF 的正确打开方式
date: 2025-10-15 10:00:00
tags:
  - CSP
  - CSRF
  - Cookie
categories:
  - 网络安全
description: 不靠“加个 token 就完事”：梳理浏览器安全机制的协作方式与常见误用。
---

# Web 安全实践：CSP、SameSite、CSRF 的正确打开方式

## 三者不是互斥，而是协作

- CSP：降低 XSS 影响面
- SameSite：降低 CSRF 默认风险
- CSRF Token：对敏感操作做强校验

## CSP 的落地建议

先从 report-only 开始，观察阻断情况，再逐步收紧策略。

## SameSite 怎么选

- `Lax`：大多数站点的默认更稳
- `Strict`：更安全但可能影响第三方登录/跳转

## CSRF Token 的关键点

- 只对有副作用的操作（POST/PUT/DELETE）强制校验
- 结合重放防护（nonce/时间窗）对关键接口更稳
