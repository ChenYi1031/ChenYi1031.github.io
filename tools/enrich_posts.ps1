Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-FrontMatterAndBody([string]$path) {
  $raw = Get-Content -LiteralPath $path -Raw -Encoding utf8
  if ($raw -notmatch "^\s*---\s*\r?\n") {
    throw "Missing front-matter start '---' in $path"
  }
  $m = [regex]::Match($raw, "^\s*---\s*\r?\n(?<fm>[\s\S]*?)\r?\n---\s*\r?\n(?<body>[\s\S]*)$", "Singleline")
  if (-not $m.Success) {
    throw "Missing front-matter end '---' in $path"
  }
  return @{
    frontMatter = $m.Groups["fm"].Value.TrimEnd()
    body = $m.Groups["body"].Value
  }
}

function Write-Post([string]$path, [string]$frontMatter, [string]$body) {
  $out = @()
  $out += "---"
  $out += $frontMatter
  $out += "---"
  $out += ""
  $out += $body.Trim()
  $out += ""
  ($out -join "`n") | Out-File -LiteralPath $path -Encoding utf8 -NoNewline
}

function Ensure-BackgroundImage {
  $root = (Get-Location).Path
  $srcDir = Join-Path $root "source\img"
  New-Item -ItemType Directory -Path $srcDir -Force | Out-Null

  $candidates = @(
    (Join-Path $root "img\bcak.jpg"),
    (Join-Path $root "img\back.jpg"),
    (Join-Path $root "img\heard.jpg")
  )

  $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $found) {
    throw "No background image found. Looked for: $($candidates -join ', ')"
  }

  Copy-Item -LiteralPath $found -Destination (Join-Path $srcDir "bcak.jpg") -Force
  # Also keep a copy under the original file name for clarity.
  Copy-Item -LiteralPath $found -Destination (Join-Path $srcDir ([IO.Path]::GetFileName($found))) -Force
  Write-Host "Background image source: $found"
}

function Update-ButterflyTopImages {
  $cfg = Join-Path (Get-Location) "themes\butterfly\_config.yml"
  if (-not (Test-Path $cfg)) { throw "Missing theme config: $cfg" }

  $raw = Get-Content -LiteralPath $cfg -Raw -Encoding utf8
  $repls = @{
    "default_top_img" = "/img/bcak.jpg"
    "index_img"       = "/img/bcak.jpg"
    "archive_img"     = "/img/bcak.jpg"
    "tag_img"         = "/img/bcak.jpg"
    "category_img"    = "/img/bcak.jpg"
  }
  foreach ($k in $repls.Keys) {
    $v = $repls[$k]
    $pat = "(?m)^${k}:\s*.*$"
    if ($raw -match $pat) {
      $raw = [regex]::Replace($raw, $pat, "${k}: $v")
    } else {
      # Fallback: append near "Image Settings" if key missing.
      $raw += "`n${k}: $v`n"
    }
  }
  $raw | Out-File -LiteralPath $cfg -Encoding utf8 -NoNewline
}

function Enrich-Posts {
  $root = (Get-Location).Path
  $postsDir = Join-Path $root "source\_posts"

  $targets = @{}

  $targets["2024-01-15-local-llm-dev-environment.md"] = @'
# 本地大模型开发环境搭建：Ollama 与 LM Studio 的选择

## 这篇笔记要解决什么

如果你想在本地做 LLM 学习与实验，最常见的痛点是：

- 环境装好了但不好用：模型下载散、参数不知道怎么调、跑起来还慢。
- 只能对话不能集成：想把推理能力接进脚本、测试工具或 Web 服务，却没有统一入口。
- 没法复现：今天能跑、明天升级后就跑不了。

本文目标是给你一套“可复现、可扩展”的本地 LLM 工具链选择与落地路径。

## 选择思路：你更像“用服务”还是“用客户端”

### Ollama 更适合

- 你希望有一个稳定的本地推理服务（HTTP API）
- 你要写脚本、写后端、做小型 RAG/代理工具
- 你希望模型管理更“工程化”（拉取、启动、查看列表）

### LM Studio 更适合

- 你更偏向“先试用再集成”
- 你需要桌面 UI 来对比不同模型参数、速度、显存占用
- 你希望快速导入/下载并立刻对话

## 推荐组合（学习 + 工程两不误）

1. **Ollama 做统一推理入口**：后续不管你换模型还是换前端，脚本调用不变。
2. **LM Studio 做对比与调参**：用 UI 快速试错，找到你机器上性价比最高的模型组合。

## 最小可用清单

- Windows Terminal / PowerShell（建议 UTF-8）
- 至少 16GB 内存（更高更稳）
- 若有 NVIDIA GPU：确保驱动与 CUDA 运行环境正常（具体取决于你用的后端）

## 统一调用的“自检步骤”

1. 列出模型（确认服务能响应）

```bash
curl http://localhost:11434/api/tags
```

2. 跑一个短 prompt（确认首 token 延迟与输出正常）
3. 观察资源占用（CPU、内存、显存），记录 token/s

## 常见坑与排查顺序

- **乱码**：优先确认终端编码；其次检查文章/文件是否 UTF-8。
- **很慢**：先确认是否走到 GPU；再看模型量化等级是否过高/过低。
- **上下文不够**：看模型自身上下文限制；不要只调 max_tokens。
- **输出不稳定**：降低温度、加结构化约束，再考虑换模型或微调。

## 建议你把它变成“可复现环境”

把以下内容写进一个 `docs/local-llm.md`（或你自己的笔记里）：

- 使用的模型名与版本
- 推理参数（温度、top_p、最大输出）
- 你的机器配置与大致性能指标（TTFT、token/s）
- 一条固定回归 prompt（用来对比升级是否退化）
'@

  $targets["2024-02-15-python-project-engineering.md"] = @'
# Python 项目工程化：pyproject.toml、依赖锁定与可复现构建

## 目标：让本地与 CI 一致

工程化不是“工具越多越好”，而是把项目变成：

- 新同学拉下来能跑
- 你换电脑/换环境也能跑
- CI 能稳定跑，并且失败好定位

## 一套推荐的落地顺序

1. 统一入口：`pyproject.toml`
2. 固定解释器版本（例如 3.11/3.12）
3. 锁依赖（避免“今天装到 A，明天装到 B”）
4. 加质量门禁：lint、测试、类型检查（按需）

## pyproject.toml 里建议集中哪些配置

- 格式化与 lint：`ruff`/`black`
- 测试：`pytest`（覆盖率可选）
- 类型检查：`mypy`（可选）

这样避免多个配置文件互相打架。

## 依赖管理的实用原则

- 生产依赖与开发依赖分组
- 升级小步快跑：一次升级一类核心依赖
- 关键库要有版本约束区间，减少破坏性更新

## 目录结构建议（最小可维护）

```text
project/
  pyproject.toml
  src/<pkg>/
  tests/
  .github/workflows/
```

## CI 里的三个关键固定项

1. Python 版本固定
2. 依赖安装方式固定（用 lock 或者固定版本）
3. 测试命令固定（不要“本地一个命令，CI 另一个命令”）

## 一条很管用的经验

当 CI 失败时，你应该能用“一条命令”在本地复现失败。否则工程化还没完成。
'@

  $targets["2024-03-15-api-test-architecture.md"] = @'
# API 自动化测试架构：分层、数据驱动与可观测性

## 为什么接口测试越写越难维护

常见问题是把所有东西都写在用例里：

- 鉴权、重试、超时到处复制
- 测试数据写死，换环境全挂
- 失败只看到 500，不知道请求细节

## 推荐的三层分工

### 1) client 层：只关心“怎么发请求”

- base_url、超时、重试、日志
- 统一注入鉴权 header
- 统一收集 request_id、耗时等信息

### 2) service 层：只关心“业务动作”

例如：登录、创建订单、查询订单、取消订单。

service 层避免散落的接口细节，让测试更像“业务脚本”。

### 3) test 层：只关心“断言与编排”

用例应该读起来像：

1. 用户登录
2. 创建订单
3. 断言订单状态与金额

## 数据驱动怎么做才不会乱

- 输入数据与断言数据分开
- 关键字段带 trace_id，失败时能追踪
- 对随机数据做“可追踪随机”（例如固定 seed 或记录生成值）

## 可观测性：让失败可定位

建议每个请求都记录：

- method + path
- 核心入参（脱敏）
- 响应码与响应体摘要
- request_id / trace_id
- 耗时

## 一个简单但有效的策略

当用例失败时，先回答三个问题：

1. 是网络/环境不稳定还是业务回归
2. 是鉴权/权限问题还是参数问题
3. 是否能用同一个 request_id 在日志里追踪到后端原因
'@

  $targets["2024-04-15-stride-threat-modeling.md"] = @'
# 威胁建模入门：用 STRIDE 给 Web 项目做风险清单

## STRIDE 是什么

STRIDE 把威胁分成六类：

1. Spoofing（伪造身份）
2. Tampering（篡改数据）
3. Repudiation（抵赖）
4. Information Disclosure（信息泄露）
5. Denial of Service（拒绝服务）
6. Elevation of Privilege（权限提升）

它的价值在于：让你不靠拍脑袋，也能系统梳理风险。

## 最小落地流程（建议 1 小时内完成一版）

1. 画数据流图（用户、前端、网关、服务、数据库、第三方）
2. 对每条数据流、每个存储点套 STRIDE
3. 输出风险清单：威胁 -> 影响 -> 缓解措施 -> 优先级

## 重点链路优先做

- 登录/鉴权
- 文件上传与下载
- 管理后台与权限系统
- 支付/订单

## 缓解措施要“落到工程里”

避免写成“加强安全”这种空话。更好的写法：

- 增加统一鉴权中间件 + 访问控制策略
- 对上传文件做类型校验与病毒扫描
- 审计日志必须包含 user、action、object、request_id、ip
- 对敏感信息脱敏与加密存储

## 一条很实用的验收标准

威胁建模的输出应该能变成：

- 需求/任务列表（能排期）
- 代码改动点（能落地）
- 回归用例（能验证）
'@

  $targets["2024-05-15-vite-build-performance.md"] = @'
# 前端构建提速：Vite 项目里最常见的 8 个性能坑

## 先明确你要优化的是哪一段

构建慢通常分三类：

- 本地 dev 启动慢
- 生产 build 慢
- CI 构建慢（缓存缺失/机器慢）

## 8 个高频坑（对照自查）

1. 依赖预构建没命中（频繁重新 optimize）
2. 大型库全量引入（没按需）
3. sourcemap 全开（产物变大、生成慢）
4. 图片/字体不压缩（产物大、加载慢）
5. chunk 拆分策略缺失（首屏大包）
6. 插件堆叠且无评估（有些插件只在开发期需要）
7. CI 不缓存（npm cache、构建缓存、pnpm store 等）
8. 构建机资源不足（CPU/IO）

## 最小改动获得最大收益

建议顺序：

1. 产物分析（先知道胖在哪里）
2. 依赖按需 + chunk 分组
3. CI 缓存（npm cache、构建缓存）

## 一个简单的实践建议

每次做性能优化，只改一个变量，并记录：

- build 时间
- 产物体积
- 首屏关键资源大小

否则你很容易“优化了，但不知道为什么变快/变慢”。
'@

  $targets["2024-06-15-rag-foundations.md"] = @'
# RAG 基础：向量检索、Chunking 与评估的实战笔记

## 先别急着换模型

很多 RAG 效果差，根因不在模型，而在：

- 切分方式（chunking）不合理
- 召回策略单一（只向量召回）
- 没有评估闭环（调参全靠感觉）

## Chunking：最容易被低估的环节

建议：

- 优先按语义/标题层级切分，而不是固定长度硬切
- 做适度 overlap，避免跨段信息断裂
- 给 chunk 带上 metadata（标题、来源、章节）

## 检索：从“召回”到“可用”

一个常见组合：

1. 向量召回 TopK
2. 关键词/规则补召回（对专有名词很有用）
3. rerank（提升相关性）

## 评估闭环：至少要有三类题

- 事实型：答案是否正确
- 步骤型：是否漏步骤/顺序错
- 对比型：是否能讲清差异与取舍

## 防止胡编的两条措施

- 检索不到就明确返回“不确定/无证据”
- 让模型引用检索片段（或至少给出来源标题）

RAG 的工程化关键不是“做出来”，而是“持续可改进”。
'@

  $targets["2024-07-15-ci-quality-gates.md"] = @'
# CI 质量门禁设计：从 lint 到覆盖率的可操作清单

## 门禁的目标

门禁不是为了卡人，而是把问题前置：在合并前发现，让修复成本更低。

## 推荐的门禁顺序（从快到慢）

1. lint/format（最快，收益高）
2. 单元测试
3. 覆盖率阈值（可以逐步提高）
4. 依赖漏洞扫描（可选）
5. 构建产物检查（体积、关键文件）

## 一些可执行的规则建议

- PR 必须通过所有检查才能合并
- 关键目录必须有 reviewer
- 禁止直接 push 到 main（只走 PR）

## 覆盖率怎么设才不“逼疯人”

- 先设一个较低阈值（例如 50%）
- 每个季度提高 5-10%
- 对核心模块单独设阈值

## 失败定位要点

门禁失败时，要能一眼看出是：

- 代码风格
- 单测失败
- 环境不稳定
- 依赖/构建问题

把日志写清楚，比堆更多规则更重要。
'@

  $targets["2024-08-15-owasp-top10-checklist.md"] = @'
# 安全测试清单：把 OWASP Top 10 落到具体用例

## 为什么需要清单

安全测试如果只靠“经验”，很难稳定覆盖。OWASP Top 10 可以做覆盖面框架，但必须拆成可执行用例。

## 拆解方法：先找入口

按业务入口列清单：

- 登录/注册/找回密码
- 搜索与筛选
- 文件上传/下载
- 导出报表
- 管理后台

## 用例示例（按类别）

- 注入：特殊字符、编码绕过、参数边界
- 认证：弱口令、会话固定、token 过期与刷新
- 访问控制：水平越权、垂直越权、IDOR
- 敏感数据：日志脱敏、下载权限、缓存控制
- 配置：默认账户、调试接口暴露、错误信息泄露

## 自动化与人工结合

- 能自动化的：鉴权、越权、参数边界、弱口令策略
- 难自动化的：业务逻辑漏洞、复杂权限组合、供应链

建议你把清单固化为每次发布前的“安全回归最小集”。
'@

  $targets["2024-09-15-db-index-and-explain.md"] = @'
# 数据库索引与查询优化：从 EXPLAIN 读懂性能瓶颈

## 先别猜，先看执行计划

慢查询优化的第一步不是加索引，而是回答：

- 是否走索引
- 扫描了多少行
- 是否回表
- 是否排序/临时表

## 索引设计三条规则

1. 高选择性列更适合做前导列
2. 复合索引遵循最左前缀
3. 避免在索引列上做函数/隐式转换

## 常见优化手段（按侵入程度从低到高）

- 覆盖索引减少回表
- 改写 SQL（OR -> UNION 等）
- 分页优化（避免深分页）
- 分表/分区（最后手段）

## 一个小技巧

每次优化只改一件事，并记录前后对比：

- 耗时
- 扫描行数
- CPU/IO 指标

这样你才知道改动是否真的有效。
'@

  $targets["2024-10-15-prompt-structured-output.md"] = @'
# 提示词工程实践：结构化输出、约束与工具调用

## 结构化输出的价值

当模型输出要被程序消费（生成用例、生成配置、生成报告）时，结构化输出能显著降低后处理成本。

## 三个实用技巧

1. 明确 schema：字段、类型、可选/必填、枚举
2. 给出边界与反例：告诉模型哪些是不合法输出
3. 失败重试要“纠错提示”：让模型修正而不是重新生成

## 一个通用模板（可直接复用）

```text
你必须只输出 JSON，禁止输出任何解释文字。
schema:
- field_a: string
- field_b: number (0-100)
校验规则:
- field_a 不能为空
- field_b 必须是整数
如果校验失败：只输出 {"error": "..."} 并说明哪个字段不满足。
```

## 工具调用的正确姿势

把“查资料/查状态”交给工具，把“推理与总结”留给模型，整体更稳、更省成本。
'@

  $targets["2024-11-15-playwright-e2e-stability.md"] = @'
# Playwright 端到端测试：稳定性、并行与失败复现

## 稳定性的核心：可复现

当 E2E 不稳定时，先追求“可复现”，再谈修复。

建议打开：

- trace（失败可回放）
- screenshot/video（关键步骤留证据）

## 三个稳定性要点

1. **选择器策略**：优先 `data-testid`，避免脆弱的 CSS/文本选择器
2. **等待策略**：等状态而不是等时间（避免固定 sleep）
3. **数据隔离**：每条用例自带数据，不复用脏数据

## 并行怎么做才不互相伤害

- 按业务模块拆分测试集
- 资源重的用例单独队列
- 对共享资源（账号/环境）做隔离或加锁

## 失败排查最短路径

1. 看 trace：卡在哪一步
2. 看网络请求：是否接口异常/超时
3. 看环境：是否被限流/数据被污染
'@

  $targets["2024-12-15-software-supply-chain-security.md"] = @'
# 软件供应链安全入门：SBOM、依赖扫描与签名

## 为什么供应链风险高

现代项目依赖数量巨大，上游一个恶意包或投毒事件，可能影响所有下游。

## 最小落地三件套

1. 生成 SBOM（组件清单）
2. CI 中做依赖漏洞扫描
3. 对构建产物做签名与校验

## 让它真正有用的关键点

- SBOM 要版本化，能追溯“某次发布用了哪些组件”
- 扫描要有阈值策略：高危必须修复，低危允许延期
- 签名与校验要贯穿发布流程，而不是只在本地做一次

供应链安全是流程问题，不是一次性动作。
'@

  $targets["2025-06-15-container-image-slimming.md"] = @'
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
'@

  $targets["2025-07-15-opentelemetry-tracing.md"] = @'
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
'@

  $targets["2025-08-15-llm-evaluation-system.md"] = @'
# LLM 评测体系：离线基准、线上 A/B 与回归集的组合

## 为什么必须做评测闭环

没有评测闭环，你永远在“感觉变好了”。模型升级、参数调整、提示词改动，都可能引入退化。

## 三层评测

- 离线基准：统一对比模型/参数
- 回归集：防止改动引入退化
- 线上 A/B：验证真实用户效果

## 指标建议（按场景选）

- 事实正确率
- 结构化输出通过率（可解析/可执行）
- 延迟与成本
- 用户满意度（显式/隐式）

## 数据要版本化

评测数据必须可回放：你才能回答“到底是模型变了还是数据变了”。
'@

  $targets["2025-09-15-code-review-checklist.md"] = @'
# 代码审查清单：从可读性到安全性的一页纸

## Review 的目标

不是挑刺，而是让代码在未来更容易维护、更容易测试、更不容易出事故。

## 一页纸清单（建议放进 PR 模板）

- 命名与职责是否清晰
- 是否处理边界条件与空值
- 是否有测试（尤其是回归点）
- 是否引入安全风险（注入、鉴权、敏感信息）
- 是否影响性能（N+1、重试风暴、无界循环）

## 让 Review 更高效的做法

- 小 PR：减少一次改动的认知负担
- 先写变更说明与风险点
- 对关键模块设必须 reviewer
'@

  $targets["2025-10-15-web-security-csp-csrf.md"] = @'
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
'@

  $targets["2025-11-15-shift-left-contract-testing.md"] = @'
# 测试左移：契约测试与测试金字塔的重构路线

## 为什么要左移

越晚发现问题，修复成本越高。左移的目标是把风险尽可能早地暴露在开发阶段。

## 契约测试是什么

消费者定义期望的请求/响应契约，提供者在 CI 中验证是否满足。这样能在不启动全套环境的情况下发现不兼容。

## 落地路线（建议从一个接口开始）

1. 选一个高频变更接口
2. 建契约规范与版本策略
3. 把验证接进提供者 CI
4. 逐步扩展到核心链路

## 与测试金字塔如何配合

契约测试补齐“服务间协议”这一层，让 E2E 不必承担过多兼容性验证压力。
'@

  $targets["2025-12-15-engineering-toolbox-2025.md"] = @'
# 年度复盘：我的工程效率工具箱（2025）

## 工具的价值

工具不等于花哨。真正的效率来自：

- 减少上下文切换
- 减少手工步骤
- 减少不可复现

## 我常用的五类工具

- 任务与笔记：把零散想法变成可追踪行动
- 代码质量：格式化、静态检查、测试
- 自动化脚本：一键生成、清理、发布
- 可观测性：日志/指标/追踪
- 安全：依赖扫描、密钥检查

## 给自己的一条规则

每次遇到重复劳动，先问一句：能不能脚本化？
'@

  $targets["2026-01-20-lora-qlora-tradeoffs.md"] = @'
# 大模型微调进阶：LoRA/QLoRA 的权衡与排坑

## 1. 什么时候该微调

微调更适合解决“行为稳定性”问题：例如结构化输出、风格一致、特定任务指令遵循。

如果你的问题是“知识缺失”，通常优先考虑 RAG。

## 2. LoRA vs QLoRA：选择建议

- **LoRA**：更稳，资源需求更高
- **QLoRA**：更省显存，但训练更敏感，参数不合适更容易发散

实用建议：资源够用优先 LoRA；资源受限再上 QLoRA。

## 3. 数据准备的三条红线

1. 去重与清洗：重复样本会让模型记忆化
2. 输出规范统一：字段名、单位、格式一致
3. 明确“不知道就说不知道”：减少胡编

## 4. 上线前回归清单

- 结构化输出通过率
- 关键事实正确率
- 延迟与成本（输出长度是否飙升）

微调要配合评测闭环，否则很容易“这次好了，下次又坏”。
'@

  $targets["2026-02-18-llm-inference-optimization.md"] = @'
# 大模型推理优化：KV Cache、量化、并发与成本

## 1. 先把指标量出来

优化前先统一看：

- 首 token 延迟（TTFT）
- token/s
- 显存占用
- 单次请求成本（与输出长度强相关）

## 2. KV Cache：为什么它关键

KV Cache 能避免重复计算历史 token 的注意力，尤其在长上下文对话里收益很大。

你要关注：

- 上下文越长，KV Cache 越占显存
- 并发越高，总显存压力越大

## 3. 量化：速度、精度与稳定性的三角

更低比特通常更省显存、更快，但可能造成输出退化（尤其数字/代码）。

建议：量化切换必须过回归集。

## 4. 并发策略

- 先限制最大并发与最大输出长度
- 再考虑 batching
- 长短请求隔离队列，避免互相拖死
'@

  $targets["2026-03-01-openclaw-install-guide.md"] = @'
# OpenClaw 安装使用指南（更新：2026-03-01）

## 这篇文章适合谁

如果你想把一个 AI 助手跑在自己机器上，并且希望它能：

- 扩展技能（脚本、文件操作、搜索）
- 接入不同平台（按你自己的需求）
- 逐步做自动化（定时任务/工作流）

这份指南会帮你把“能跑起来”变成“能长期用”。

## 1. 环境准备

- Node.js（建议 LTS）
- 稳定的终端环境（Windows Terminal/PowerShell）

## 2. 安装与验证

```bash
npm install -g openclaw
openclaw --version
```

如果版本能输出，说明安装成功。

## 3. 初始化配置（建议先走默认）

```bash
openclaw setup
```

先让它跑通一条最小链路：对话 -> 调用一个内置能力 -> 输出结果。

## 4. 常见问题排查

- 命令找不到：检查 Node/npm 是否在 PATH
- 运行时报权限问题：确认当前目录权限与文件读写权限
- 网络相关失败：确认代理/证书设置（避免关闭 TLS 校验）

## 5. 后续怎么“用起来”

建议你把技能按场景分组：

- 写作/内容：生成草稿、标题、摘要
- 工程：生成脚本、检查配置、生成测试用例
- 运维：日志分析、发布检查清单

最后把常用命令写到一个 `README` 或笔记里，减少每次查找成本。
'@

  foreach ($kv in $targets.GetEnumerator()) {
    $path = Join-Path $postsDir $kv.Key
    if (-not (Test-Path $path)) { throw "Missing post: $path" }
    $parsed = Get-FrontMatterAndBody $path
    Write-Post $path $parsed.frontMatter $kv.Value
  }
}

Ensure-BackgroundImage
Update-ButterflyTopImages
Enrich-Posts

Write-Host "Done."