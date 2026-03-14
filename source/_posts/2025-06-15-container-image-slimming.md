---
title: 容器镜像瘦身与安全基线：多阶段构建实用技巧
date: 2025-06-15 10:00:00
tags:
  - Docker
  - 镜像
  - 安全
categories:
  - 开发运维
description: 用多阶段构建和最小化运行时依赖，让镜像更小、更快、更安全。
---

# 容器镜像瘦身与安全基线：多阶段构建实用技巧

## 为什么要瘦身

镜像越大：

- 拉取越慢
- 缓存命中越差
- 攻击面越大

## 多阶段构建（最实用）

思路：把“编译/构建”和“运行”拆开。

```dockerfile
# build stage
FROM node:20 AS build
WORKDIR /app
COPY . .
RUN npm ci && npm run build

# runtime stage
FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
```

## 安全基线建议

- 非 root 运行
- 固定基础镜像版本
- 依赖与镜像扫描（CVE）
- 禁止把密钥打进镜像（用环境变量/密钥管理）

## 交付验收清单

- 镜像体积是否达标
- 启动时间是否稳定
- 扫描结果是否可接受
