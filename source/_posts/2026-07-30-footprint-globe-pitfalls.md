---
title: 足迹地球踩坑录：12 个真实 bug 与它们的教训
date: 2026-07-30 10:00:00
tags:
  - 踩坑
  - 地图
  - MapLibre
  - Globe.gl
  - 异步竞态
categories:
  - 技术分享
description: 足迹地球模块从 3D globe.gl 迁移到 2D MapLibre 过程中遇到的 12 个真实 bug：渲染引擎兼容性、数据源地域限制、异步竞态、部署环境问题——每个坑的现象、根因、解决和经验教训。
---

# 足迹地球踩坑录：12 个真实 bug 与它们的教训

做「足迹地球」模块（LifeOS 项目中的 3D/2D 足迹地图）时，从 globe.gl 3D 球体迁移到 MapLibre 2D 矢量地图，一共踩了 12 个坑。每个坑都不算特别复杂，但组合在一起耗掉了大量时间。这篇文章把它们整理出来，希望对做地图类项目的读者有参考价值。

## 踩坑全景图

| # | 坑 | 现象 | 根因 | 解决 |
|---|---|---|---|---|
| 1 | globe.gl ESM/Turbopack | 地图初始化但 style 永不加载 | 3D 方案不适合 2D 足迹交互 | 迁移 MapLibre |
| 2 | MapLibre 6 ESM-only | 图层不渲染、无日志 | v6 是纯 ESM，Turbopack 不兼容 | 降级 v5.24.0 |
| 3 | CartoDB 底图不可达 | style.load 永不触发 | 国外 CDN 国内超时 | 移除外部底图，纯本地 GeoJSON |
| 4 | DataV 海外 403 | 地球纯黑 | Cloudflare 边缘 IP 被 DataV 拒绝 | 本地打包 35 个 GeoJSON |
| 5 | 区县级数据缺失 | 市视图空白 | 300+ 市无法全部打包 | 服务器代理懒加载 |
| 6 | MapLibre 字符串化 properties | 经纬度没自动填充 | center 变字符串 `"[lng,lat]"` | JSON.parse 解析 |
| 7 | base-ui Button 无 asChild | TS 报错 | 项目用 base-ui 变体 | 用 render prop |
| 8 | Source already exists | 地图空白 + 报错 | useEffect 重复触发并发加载 | in-flight 防重 + 防御性移除 |
| 9 | flyTo 兜底到全国中心 | 市视图"空白" | center 表只有省级 adcode | 缺失时保持当前位置 |
| 10 | npm ci 2 小时 | Cloudflare 522 中断服务 | 部署触发依赖重装 | 安全部署脚本跳过 |
| 11 | Prisma Client 缺模型 | places API 崩溃 | npm ci 后 client 未同步 schema | 强制 prisma generate |
| 12 | NEXTAUTH_URL 域不匹配 | 登录后 API 401 | www 与无 www cookie 域不同 | 统一为 www |

---

## 渲染引擎选型与迁移的坑

### 坑 1：3D globe.gl 与需求不匹配（决策层）

**现象**：globe.gl 实现了"地球仪"，但用户要的是**高德足迹式 2D 平面地图**交互。

**难点**：3D 球面投影让自动化测试点击省份极不稳定；HTML 元素 3D 投影 50 个标注就卡顿；bundle 900KB，2C2G 服务器吃力。

**解决**：整体迁移到 MapLibre GL JS。

**经验**：**选型前先确认交互范式**——"地球仪" vs "足迹地图"是完全不同的交互模型。3D 适合展示，2D 适合操作。

### 坑 2：MapLibre 6.1.0 ESM-only 与 Turbopack 不兼容

**现象**：地图初始化成功（canvas 存在）但 `map.isStyleLoaded()` 永远 false，图层不渲染、**零 console 日志**。

**根因**：`maplibre-gl@6.x` 的 `package.json` 是 `"type": "module"` 且 `main: undefined`（纯 ESM），Next.js 16 Turbopack 处理异常。

**解决**：降级到 `maplibre-gl@5.24.0`（CJS+ESM 双格式）。

```bash
npm install maplibre-gl@5.24.0
```

**经验**：**新大版本库先验证与构建工具的兼容性**——ESM-only 的库在 Next/Turbopack 里是高危信号。

### 坑 3：`map.on("load")` 依赖底图瓦片就绪

**现象**：省图层从未添加（`layers` 只有 `["base"]`），但地图已初始化。

**根因**：`map.on("load")` 等待底图瓦片加载完成，而 CartoDB 国外 CDN 在国内加载超时 → load 事件永不触发。

**解决**：移除外部底图（纯深色背景 + 本地 GeoJSON），改用 `load` + `style.load` 双监听。

```typescript
map.on("load", onReady);
map.on("style.load", onReady);  // style 就绪不等瓦片
```

**经验**：**国内网络环境慎用国外瓦片 CDN**。style.load 是样式就绪，load 可能等瓦片——语义不同。

### 坑 4：base-ui Button 不支持 asChild

**现象**：`<PopoverTrigger asChild><Button/></PopoverTrigger>` 报 TS 错误。

**根因**：项目用 shadcn/ui 的 base-ui 变体，Button 没有 radix 版的 `asChild` prop。

**解决**：用 base-ui 的 `render` prop：

```tsx
<PopoverTrigger render={<Button size="icon"><CalendarIcon /></Button>} />
```

**经验**：shadcn/ui 有多种底层实现（radix/base-ui），动手前看 `components/ui/` 里实际用的哪种。

---

## 地图数据源的坑

### 坑 5：DataV GeoAtlas 对海外 IP 返回 403 → 地球纯黑

**现象**：生产环境（Cloudflare 后面）地球纯黑；本机/服务器 curl 却正常（200）。

**根因**：浏览器请求经 Cloudflare 边缘节点（海外 IP），阿里云 DataV 的 OSS 对海外 IP 返回 403。

**解决**：本地打包 35 个 GeoJSON（全国 + 34 省）到 `public/geojson/`，加载链改为本地优先 + 服务器代理 + DataV 兜底三级回退。

**经验**：**国内数据源 + 海外 CDN = 必踩地域限制坑**。自托管/本地化是最稳方案。

### 坑 6：区县级数据无法全部打包 → 服务器代理

**现象**：市级下面的区县级边界（如长沙市的芙蓉区）加载不到。

**难点**：区县级 GeoJSON 有 300+ 个市，无法全部打包。

**解决**：新增 `/api/geojson/{adcode}` 服务器代理路由——服务器是境内 IP，DataV 可达，浏览器通过同源代理间接获取，内存缓存 24h。

**经验**：**浏览器直连受限的外部数据源，用服务器代理中转**是通用解法。

### 坑 7：MapLibre 字符串化非标量 properties

**现象**：点击地市后表单经纬度没自动填充。

**根因**：MapLibre GeoJSON source 会把非标量 properties 序列化成字符串——`"center": "[112.98, 28.19]"` 是字符串不是数组。

**解决**：解析字符串恢复数组：

```typescript
const raw = f.properties?.center;
if (Array.isArray(raw)) center = raw;
else if (typeof raw === "string") {
  try {
    const parsed = JSON.parse(raw);
    if (parsed.length === 2) center = [parsed[0], parsed[1]];
  } catch { /* ignore */ }
}
```

**经验**：**MapLibre 的 properties 只保证标量可靠**，数组/对象会被字符串化。

### 坑 8：台湾省 URL 后缀特殊

**现象**：台湾省（710000）数据加载失败。

**根因**：DataV 的台湾省接口没有 `_full` 后缀（`710000.json` 而非 `710000_full.json`）。

**解决**：加载路径统一判断 `adcode === "710000" ? "" : "_full"`。

---

## 异步竞态的坑（最难排查）

### 坑 9：Source "cities" already exists → 地图空白

**现象**：快速切换省/市时偶发，地图空白 + 提示"市级边界加载失败"。

**根因（三层）**：
1. 视图切换 useEffect 依赖 `places`——标注数据异步到达 → useEffect 重跑 → 再次调用 `loadCityLayer`
2. 两个 `loadCityLayer` 并发在 fetch 阶段
3. 第一个 `addSource("cities")` 成功后，第二个又 `addSource` → "already exists"

**解决（三重防护）**：

```typescript
// 1. in-flight 防重
if (loadingRef.current.city === adcode) return;
loadingRef.current.city = adcode;

// 2. 防御性移除
if (map.getSource("cities")) map.removeSource("cities");

// 3. 竞态校验
if (cur.viewAdcode !== adcode || cur.viewCityAdcode !== null) return;
```

**经验**：
- **异步 + 状态依赖 = 竞态温床**
- 竞态 bug 的特征：**偶发、快速操作必现、console 有报错但无堆栈指向业务代码**
- 防御性编程虽然啰嗦，但能兜住所有想不到的路径

### 坑 10：flyTo 兜底到全国中心 → 市视图"空白"

**现象**：进入某市视图，地图却显示全国/空白。

**根因**：市视图 flyTo 的 center 计算中，`PROVINCE_CENTERS` 表只有省级 adcode，没有市级。`viewCityCenter` 为 null 时兜底到全国中心。

**解决**：center 缺失时保持当前地图中心，只放大 zoom。

```typescript
const curCenter = map.getCenter();
const cityCenter = viewCityCenter ?? [curCenter.lng, curCenter.lat];
map.flyTo({ center: cityCenter, zoom: CITY_ZOOM });
```

**经验**：**flyTo 的 center 永远不要无脑兜底到全图中心**——兜底值要考虑"当前视野"。

---

## 部署与环境的坑

### 坑 11：npm ci 触发 2 小时重装 → Cloudflare 522

**现象**：部署后网站 522（Cloudflare 连不上源站），持续 2 小时。

**根因**：部署脚本检测到 package-lock.json 变化 → `rm -rf node_modules` + `npm ci` → 2 小时。期间应用无法启动。

**解决**：安全部署脚本——lockfile 未变则跳过 npm ci：

```bash
if cmp -s node_modules/.package-lock.json package-lock.json; then
  echo "DEPS_UP_TO_DATE"  # 跳过重装
else
  npm ci --omit=dev --registry=https://mirrors.tencentyun.com/npm
fi
```

**经验**：**部署热路径绝不重装依赖**——依赖重装要可控，绝不在部署热路径上盲目重装。

### 坑 12：Prisma Client 缺模型 → places API 崩溃

**现象**：`/api/places` 报 `Cannot read properties of undefined (reading 'findMany')`。

**根因**：npm ci 重装依赖后，`node_modules/.prisma/client` 与 schema 不同步。

**解决**：部署脚本强制 `prisma generate` + 校验产物存在：

```bash
npx prisma generate --schema=prisma/schema.prisma
[ -f node_modules/.prisma/client/index.js ] || npx prisma generate
```

**经验**：**Prisma v7 每次依赖变动后 client 都可能过期**，部署脚本必须显式 generate 并校验。

### 额外坑：NEXTAUTH_URL 域名不匹配 → 登录后 API 401

**现象**：登录成功（session 有值）但 `/api/places` 返回 401。

**根因**：`.env` 里 `NEXTAUTH_URL="https://yxgzos.cloud"`（无 www），用户访问 `www.yxgzos.cloud`——cookie 域不匹配。

**解决**：统一为 `NEXTAUTH_URL="https://www.yxgzos.cloud"`。

**经验**：**NEXTAUTH_URL 必须与用户实际访问的域名完全一致**（含 www 前缀），否则 cookie 失效。

---

## 12 条经验教训

1. **选型前先确认交互范式**：足迹地图（2D 操作）用 MapLibre，地球仪（3D 展示）才用 globe.gl
2. **新库大版本先验证兼容性**：ESM-only 库在 Next/Turbopack 是高危
3. **国内项目慎用国外 CDN**：底图瓦片、数据源都要考虑地域可达性
4. **外部数据源要本地化/代理化**：能打包就打包，不能打包就服务器代理
5. **地图 properties 只信标量**：数组/对象会被字符串化，提前做好解析
6. **useEffect + 异步加载必须防竞态**：in-flight 防重 + 视图校验 + 防御性移除
7. **竞态 bug 靠日志和时序分析**：加 `[组件名]` 前缀日志，用请求时间戳还原执行顺序
8. **部署热路径绝不重装依赖**：lockfile 判断 + 跳过机制
9. **Prisma generate 必须进部署脚本**：依赖变动后 client 必过期
10. **NEXTAUTH_URL 与访问域名严格一致**：含 www 前缀
11. **地图自动化测试先确认投影模型**：2D 用 `map.project()`，3D 不可靠
12. **生产验证对 Cloudflare 间歇问题加重试**：区分"应用 bug"和"网络偶发"
