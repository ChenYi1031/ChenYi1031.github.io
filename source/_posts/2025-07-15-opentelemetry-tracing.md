---
title: 分布式追踪入门：OpenTelemetry 把日志、指标、Trace 串起来
date: 2025-07-15 10:00:00
tags:
  - OpenTelemetry
  - 可观测性
  - 追踪
categories:
  - 开发运维
description: 从 request_id 到 trace_id，建立端到端链路追踪，让线上问题定位不再靠猜。
---

# 分布式追踪入门：OpenTelemetry 把日志、指标、Trace 串起来

## 目标\n\n当一次请求跨越网关、多个服务、数据库与消息队列时，你仍然能在同一条链路上看清耗时与错误点。\n\n## 三件事先做对\n\n1. 统一传播 Trace Context\n2. 关键 span 命名规范\n3. 错误与重试要打到 span 上（含原因）\n\n## 与日志联动\n\n日志里必须打印 trace_id/span_id，这样才能从日志跳回追踪页面。
