---
title: LifeOS 开发踩坑全记录：从 OOM 到 HTTPS 521
date: 2026-08-04 10:00:00
tags:
  - 踩坑
  - Next.js
  - Prisma
  - 部署
  - 服务器
categories:
  - 技术分享
description: LifeOS 项目（Next.js 16 + Prisma 7 + PostgreSQL + 腾讯云 + Cloudflare）开发部署过程中遇到的所有坑：构建 OOM、Prisma hashed client、HTTPS 521/525、NEXTAUTH_URL 域名不匹配等——每个坑的现象、原因和解决。
---

# LifeOS 开发踩坑全记录：从 OOM 到 HTTPS 521

LifeOS 是一个 AI 原生的个人工作台，技术栈是 Next.js 16 + Prisma 7 + PostgreSQL，部署在 2GB 内存的腾讯云轻量服务器上，前面套 Cloudflare CDN。开发部署过程中踩了不少坑，这篇文章按类别整理出来。

## 一、构建与部署

### 1.1 服务器内存不足导致 next build OOM

**现象**：在 2GB 内存的服务器上执行 `npm run build`，构建过程中进程被 kill（Out of Memory）。

**原因**：Next.js 构建需要大量内存（本项目约 3GB+），2GB 内存 + 无 swap 直接 OOM。

**解决**：构建必须在本地或 CI（GitHub Actions）完成，服务器只运行产物。使用 `output: "standalone"` 输出独立服务器包。

**教训**：低配服务器不要在上面构建——构建是重操作，2GB 内存跑 Next.js 构建必然 OOM。

### 1.2 Next.js standalone 部署结构理解

**现象**：`.next/standalone` 里出现 `src/`、`AGENTS.md`、`mobile/` 等整个项目的副本。

**原因**：Next.js 16（Turbopack）的 standalone 结构 + tracing 根目录覆盖过大。

**解决**：打包时显式排除源文件；用 `--exclude='./node_modules'` 只排除顶层（勿伤 `.next/node_modules`）。

**教训**：`tar --exclude='node_modules'` 和 `--exclude='./node_modules'` 是两回事——前者会递归排除所有含 node_modules 的子目录，包括 `.next/node_modules`。

---

## 二、Prisma 7 + Next.js 16

### 2.1 Prisma 7 的 hashed client（最坑的一个）

**现象**：`Cannot find module '@prisma/client-2c3a283f134fdcb6'`。

**原因**：Prisma 7 + Turbopack 构建时生成 **hashed client**（`@prisma/client-<hash>`），`.next` 硬引用它；`.next/node_modules/` 里是符号链接指向顶层 `node_modules/@prisma/client`。

**解决**：打包必须保留 `.next/node_modules/`；⚠️ `tar --exclude='node_modules'` 会误伤，应写 `--exclude='./node_modules'`。

**教训**：Prisma 7 的 hashed client 机制意味着 `.next` 目录和 `node_modules` 的关系更紧密——打包时必须理解这个依赖关系。

### 2.2 服务器需要 `prisma generate`

**现象**：`Cannot find module '.prisma/client/default'`。

**原因**：`@prisma/client` 的 `default.js` 里 `require('.prisma/client/default')`，需要 `prisma generate` 生成。

**解决**：部署脚本执行 `npx prisma generate --schema=prisma/schema.prisma` 并校验产物存在。

**教训**：Prisma 的 client 不是安装就有的——每次依赖变动后都必须 generate。

### 2.3 服务器 `.prisma/client` 可能滞后（新字段不生效）

**现象**：新增 Prisma 字段后，服务器 API 报"unknown argument"。

**原因**：部署脚本的 generate 未在 schema 更新后执行，或生成的 client 是旧版。

**解决**：`prisma db push` 后必须 `prisma generate`；部署脚本顺序：db push → generate → restart。

### 2.4 Prisma 7 需要 driver adapter

**解决**：`@prisma/adapter-pg`，`new PrismaClient({ adapter })`。

---

## 三、服务器运维

### 3.1 腾讯云服务器访问 GitHub 域名被阻断

**测试结果**：`github.com` 被阻断（000）；`api.github.com` / `codeload` / `objects.githubusercontent.com` 可达。

**解决**：下载 Release 资产用 API 端点（302 到 objects CDN），带 `Authorization: Bearer <token>`。

**教训**：国内服务器访问 GitHub 有选择性阻断——主站不通但 API/CDN 通是常态。CI/CD 设计要考虑这个现实。

### 3.2 私有仓库 Release 下载需要 token

**解决**：服务器存只读 token（600 权限），API 请求带 Bearer。

### 3.3 跨境下载速度慢

**解决**：`curl -C -` 断点续传 + 长超时 + cron 重试；服务器内网 npm 镜像（`mirrors.tencentyun.com`）装依赖 ~25s。

### 3.4 部署脚本 lock 卡死

**解决**：lock 文件记录 PID，进程死了自动清理。

### 3.5 部署时 `.env` 必须保留

**解决**：备份/清理都排除 `.env`。

---

## 四、SSL 证书与 HTTPS

### 4.1 自签名证书 → Android 报 Trust anchor

**解决**：Expo config plugin 注入 network_security_config 信任打包证书。

### 4.2 自签名证书无 SAN → Hostname not verified

**解决**：**不要用自签名证书**。接入 Cloudflare 用域名（边缘有受信任证书）。

### 4.3 Cloudflare 回源 521/525（重要）

**现象**：`https://域名` 返回 521（web server down）/ 525（SSL handshake failed），但源服务器正常。

**根因**（两个叠加）：
1. **nginx 只监听 IPv4**（`0.0.0.0`），但服务器有公网 IPv6 → Cloudflare 走 AAAA 回源被拒 → 521
2. **证书无 SAN** → Cloudflare "Full (strict)" 模式握手失败 → 525

**解决**：
1. nginx 加 `listen [::]:80/443;`（IPv6 双栈）
2. 重新生成带 SAN 的证书（`DNS:yxgzos.cloud, IP:122.51.242.95, IP:IPv6`）
3. 配置脚本已入库

**教训**：Cloudflare + nginx 的 HTTPS 链路有多个潜在故障点——IPv6 双栈、SAN 证书、Full strict 模式，缺一个就可能 521/525。

### 4.4 NEXTAUTH_URL 必须与访问域名一致

**解决**：`.env` 里 `NEXTAUTH_URL="https://yxgzos.cloud"`（部署保留 .env，改一次持久生效）。

---

## 五、GitHub Actions CI/CD

### 5.1 健康检查 status=000 假失败

**原因**：`pm2 restart` 立即返回，Next.js 需几秒监听。

**解决**：健康检查重试循环（90s）。

### 5.2 美国 runner → 中国服务器 scp 慢

**解决（方案 A：服务器反向拉取）**：GitHub 构建瘦包（3.3MB）传 Release；服务器 cron 检测新版本 → 下载（API 端点）→ npm ci（内网镜像）→ prisma generate/db push → pm2 restart。

### 5.3 scp-action 空归档 / tar 解压冲突

**解决**：tar 输出到 `$GITHUB_WORKSPACE`；解压前 `rm -rf` 清理。

---

## 六、移动端 React Native / Expo

### 6.1 EAS 云端找不到 `@expo/config-plugins`

**解决**：装到 devDependencies。

### 6.2 config plugin 里 `__dirname` 路径问题

**解决**：用 `config.modRequest.projectRoot`。

### 6.3 Expo 信任自签名证书

证书放 `assets/`，plugin 生成 network_security_config + 复制到 res/raw，Manifest 引用。

### 6.4 移动端没有图标库

**解决**：用 emoji（👁/🙈）做密码显示切换。

---

## 七、小米健康数据接入

### 7.1 逆向 API 基础

端点：`POST https://hlth.io.mi.com/app/v1/data/get_fitness_data_by_time`

认证：passToken → `serviceLogin` 换 ssecurity + location → 跟随拿 serviceToken cookie

数据请求：data=JSON，RC4 加密 + SHA1 签名 + base64

### 7.2 70016 异地登录风控（最坑）

**现象**：同步报"登录验证失败"（code 70016），数据全 0。

**根因**：70016 = 小米异地登录安全验证。服务器 IP 首次登录该小米账号，需浏览器手动授权信任 IP。

**误判陷阱**：`Promise.allSettled` + `safe()` 把认证失败静默吞掉 → 返回全 0 → 误以为"小米没数据"。

**解决**：
1. 修复吞错 bug（全失败必须抛出真实错误）
2. 登录响应 `location` 字段 = 验证 URL，用户在浏览器登录授权，约 1 小时后生效
3. 系统实现：verifyUrl 存 DB → API 暴露 → 设置页显示"前往小米账号安全验证"

**教训**：第三方 API 错误处理绝不能静默吞掉；包装错误时保留自定义属性。

### 7.3 passToken 获取方式

**方式 A（推荐）**：二维码扫码登录（设置页"使用手机扫码连接"），自动获取凭据。

**方式 B**：浏览器登录 `account.xiaomi.com` → F12 → Cookie 里复制 userId + passToken。

---

## 八、其他

### 8.1 r.js / ssh-b64.js 辅助脚本

`r.js` 有 90s 硬超时 → 长任务用 `ssh-b64.js`；复杂脚本 base64 传输避免转义问题。

### 8.2 服务器 npm 内网镜像

`npm ci --registry=https://mirrors.tencentyun.com/npm`（940 包 ~25s）。

### 8.3 Next.js 16 特殊路径

- `/api/health/qr` 路径 404：相同代码改名 `xiaomi-qr` 就正常——`qr` 是 Next.js 16 保留/特殊路径
- GET 路由被静态预渲染（`x-nextjs-prerender:1`）：即使 `force-dynamic` 也偶发 → 改用 POST 端点

---

## 经验总结

做 LifeOS 这个项目最大的感受：**坑不在于单个有多深，而在于它们组合起来的密度**。

1. **2GB 内存是硬约束**：构建在本地做，服务器只跑产物
2. **Prisma 7 的 hashed client 是隐形炸弹**：打包必须理解 `.next/node_modules` 的符号链接关系
3. **国内服务器访问 GitHub 有选择性阻断**：CI/CD 设计要考虑这个现实
4. **Cloudflare HTTPS 链路有多个故障点**：IPv6 双栈、SAN 证书、NEXTAUTH_URL，缺一个就 521/525
5. **第三方 API 错误绝不能静默吞掉**：全失败时必须抛出真实错误
6. **NEXTAUTH_URL 与访问域名严格一致**：含 www 前缀，cookie 域匹配是命门
7. **部署脚本必须覆盖所有依赖变动**：lockfile 判断 + prisma generate + 健康检查重试

这 20+ 个坑，每一个都是"排查几小时到几天"的代价。记录下来，希望后来者能少走弯路。
