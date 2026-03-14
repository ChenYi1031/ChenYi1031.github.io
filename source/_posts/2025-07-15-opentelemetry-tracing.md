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

## 你真正想要的是“端到端定位能力”

当请求跨越网关、多个服务、数据库与队列时，你仍能回答：

- 哪一段最慢
- 错在哪里
- 与日志怎么关联

## 三件事先做对

1. Trace Context 传播：入口生成 trace_id，跨服务传递
2. Span 命名规范：同类操作命名一致
3. 错误记录：异常原因、重试、降级都要写进 span

## 与日志联动的最低要求

日志必须打印：

- trace_id
- span_id
- request_id（如果你系统已有）

这样你才能从日志跳回追踪页面。
