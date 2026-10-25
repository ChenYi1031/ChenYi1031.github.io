---
title: CollabAgent：用 LangGraph 搭建多 Agent 协作研究报告系统
date: 2026-09-08 10:00:00
tags:
  - LangGraph
  - Multi-Agent
  - FastAPI
  - SSE
  - 项目复盘
categories:
  - 技术分享
description: CollabAgent（Multi-Agents）项目复盘：LangGraph StateGraph 编排 Researcher / Writer / Fact-Checker 三个 Agent 生成带引用的研究报告。重点写工程实现——课题拆解与多路检索、质量校验与自动修复、截断续写、SSE 流式前端、65 个不依赖真实 API 的测试。
---

# CollabAgent：用 LangGraph 搭建多 Agent 协作研究报告系统

> 之前写过一篇[从 LangChain 到 LangGraph 的概念梳理](/2026/06/23/2026-06-23-langchain-to-langgraph-agent/)，这篇不讲概念，只讲把多 Agent 系统真正落地时的工程决策。

CollabAgent 是一个多 AI Agent 协作系统：输入一个研究主题，Researcher 检索资料、Writer 撰写带引用的报告、Fact-Checker 做事实核查，最后返回结构化 Markdown。整体是"专业团队分工"的隐喻——不是为了堆 Agent 数量，而是因为**单 Agent 干这件事有三个结构性缺陷**：

1. **检索和写作互相干扰**：一个上下文里又要想搜索词又要写长文，两头都做不好
2. **幻觉没人管**：自己写自己查，引用和正文经常对不上
3. **长文截断**：输出到 token 上限直接断尾，没有任何补救

项目地址：[ChenYi1031/Multi-Agents](https://github.com/ChenYi1031/Multi-Agents)

## 整体架构

```
用户 → 前端 (Vue 3 + Element Plus)
         │  SSE /research/stream?topic=...
         ▼
  FastAPI (api.py)
         │
         ▼
  LangGraph StateGraph (graph.py)
         ├─ researcher_node  课题拆解 → 多路检索 → 正文抓取
         ├─ writer_node      报告撰写 → 质量校验 → 自动修复
         └─ fact_check_node  事实核查
```

- **编排**：LangGraph 0.2+，三节点线性工作流，MemorySaver 做状态持久化
- **Agent**：LangChain 0.3+，LLM 走 DeepSeek（OpenAI 兼容接口）
- **搜索**：默认 DuckDuckGo（免费），Tavily 作备用
- **抓取**：Jina Reader 拿正文，免 Key
- **前端**：Vue 3 + Element Plus，SSE 实时流式进度
- **容器**：Docker（python:3.11-slim）

## Researcher：检索质量决定报告上限

Researcher 是三个节点里逻辑最重的，分三步：

**第一步，课题拆解。** 用户输入往往是"大模型在医疗行业的应用"这种宽泛主题，直接拿去搜只能得到一堆新闻稿。所以先让 LLM 做一次规划（`_plan_sub_queries`），把主题拆成 3~5 个互补的子查询——现状综述、技术路线、行业案例、争议与风险……每个子查询都是可以直接喂给搜索引擎的具体问题。

**第二步，多路检索。** 每个子查询独立检索，DuckDuckGo 免费额度为主，结果为空或质量差时降级到 Tavily。多路结果合并去重后再进入下一步。

**第三步，正文抓取与可信度评分。** 搜索结果摘要太薄，用 Jina Reader 抓正文；同时给来源做可信度评分（域名权重、内容与子查询的相关性），低分源直接丢弃。Writer 后面要用的每一条素材，都是"正文 + 可信度 + URL"的完整结构。

这一步的心得：**宁可多花一轮 LLM 调用做检索规划，也不要让 Writer 面对一堆低质量素材**——后面所有自动修复的复杂度，都源自素材质量。

## Writer：校验、修复、续写

Writer 拿到结构化素材后撰写报告，三条硬性产出要求：编号引用 `[n]`、文末参考文献列表、结构化 Markdown 标题层级。

但 LLM 输出不能直接信，所以写了一个 `validate_report()` 做确定性校验：

- 所有 `[n]` 是否都有对应的参考文献条目
- 参考文献是否都被正文引用过
- 章节结构是否完整（有没有空章节）

**校验失败不直接报错，而是把失败原因拼回 prompt 让 LLM 重写**——大多数情况下一次修复就能过。这是整个系统里性价比最高的一段代码：它把"看起来很美但引用是编的"这类输出挡在了流水线内。

另一个细节是**截断检测**（`_is_truncated`）：输出撞到 token 上限时，文末经常停在半句话。检测到截断就发起续写（`_continue_report`），带着已有内容和参考文献继续生成，直到收尾完整。没有这个机制，长主题的报告会随机性地"腰斩"。

## Fact-Checker

事实核查员拿 Writer 的报告和 Researcher 的素材库做交叉核对：抽取报告中的关键论断（数字、时间、结论性表述），逐条在素材中寻找支撑，标注"有支撑 / 无支撑 / 存疑"。核查结果附在报告尾部，让用户自己判断可信边界。

## SSE 流式前端

多 Agent 流水线动辄跑一两分钟，同步接口体验是灾难。后端 FastAPI 提供 `GET /research/stream`（SSE），把流水线内部的事件推给前端：

```python
@router.get("/research/stream")
async def research_stream(topic: str):
    async def event_gen():
        async for event in graph.astream_events(input_state, version="v2"):
            if event["event"] == "on_chain_start":
                yield sse("node_start", event["name"])
            ...
    return StreamingResponse(event_gen(), media_type="text/event-stream")
```

前端用 `EventSource` 订阅，Element Plus 的步骤条实时显示"正在检索 → 正在撰写（第 2 章）→ 正在核查"，报告正文也是流式追加渲染。**进度可视化对 Agent 产品不是锦上添花，是留存用户的关键**——用户知道系统在干活，才等得起。

## 测试策略：65 个测试，0 次真实调用

Agent 应用最容易在测试上摆烂（"要调 LLM 没法测"）。这个项目的原则是：**所有外部依赖全部 mock，测试确定性**：

- mock LLM：返回预置的结构化输出，测图的状态流转、校验逻辑、修复路径
- mock 搜索/抓取：固定素材集，测 Researcher 的拆解、合并、评分逻辑
- 真实只测"纯函数"：`validate_report`、截断检测、引用配对这些确定性逻辑覆盖到分支级

```python
@pytest.mark.asyncio
async def test_writer_citation_fix(mock_llm):
    # 第一次输出缺引用 → 校验失败 → mock 第二次返回修复版
    ...
```

65 个测试全绿只要几秒，不烧一分钱 API。配合刚加的 GitHub Actions CI，每次 push 自动回归。这套测试后来抓到过好几次重构引入的回归——**Agent 代码的可维护性，一半靠测试兜底**。

## 复盘与下一步

- MemorySaver 是内存级持久化，进程重启状态就没了，长任务落库是下一步
- 线性流水线的分工是清晰的，但 Writer 遇到素材不足时只能"硬写"，计划加一个回边：素材不足 → 返回 Researcher 定向补检索
- README 里规划的多 Agent **辩论机制**（多个角色对报告互相攻击）还没实装，那是这个项目走向"高可扩展协作框架"的关键一步

代码结构刻意保持了"一个节点一个文件"（`agents/researcher.py` / `writer.py` / `fact_checker.py`），加新 Agent = 加一个文件 + 图里插一个节点。后续如果做辩论机制，StateGraph 的条件边正好派上用场。
