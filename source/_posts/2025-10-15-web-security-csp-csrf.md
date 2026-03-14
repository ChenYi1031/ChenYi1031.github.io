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

## CSP：减少 XSS 的爆炸半径\n\nCSP 不是万能药，但能显著减少第三方脚本和内联脚本的风险。\n\n## SameSite：默认防护的一部分\n\n合理设置 SameSite=Lax/Strict 可以降低 CSRF 风险，但要兼顾业务跳转与第三方登录。\n\n## CSRF：用双重校验\n\n- 同源策略 + SameSite\n- 再加 CSRF token（对敏感操作）\n- 对关键接口做重放防护（nonce/时间窗）
