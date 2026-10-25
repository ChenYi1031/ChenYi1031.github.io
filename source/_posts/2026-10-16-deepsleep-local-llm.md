---
title: DeepSleep：用 Ollama 本地大模型做睡眠建议应用
date: 2026-10-16 10:00:00
tags:
  - Ollama
  - 本地大模型
  - FastAPI
  - React
  - 项目复盘
categories:
  - 技术分享
description: DeepSleep 项目复盘：为什么睡眠数据这种隐私敏感场景值得用本地大模型——Ollama + deepseek-r1:8b 完全本地推理，FastAPI + React 前后端分离，从模型选型、API 设计到本地推理体验的完整记录。
---

# DeepSleep：用 Ollama 本地大模型做睡眠建议应用

DeepSleep 是一个帮用户改善睡眠的智能应用：描述自己的睡眠情况，大模型分析并给出个性化的睡眠改善建议。它和市面上同类产品的核心区别只有一个——**模型跑在你自己电脑上**（Ollama + deepseek-r1:8b），睡眠数据不出本机。

项目地址：[ChenYi1031/DeepSleep](https://github.com/ChenYi1031/DeepSleep)

## 为什么坚持本地推理

给"睡眠建议"接大模型，最容易的做法是调个云端 API。但这个问题域有个特殊性：**睡眠数据是高隐私数据**。

- 入睡时间、夜醒次数、午休时长，拼起来就是你的完整生活作息规律
- 睡眠问题往往关联情绪、工作压力，这些是用户最不希望被云端记录的内容
- 长期记录才有效果，意味着数据会持续累积，云端的"隐私协议"承诺一年两年后还在不在，没人知道

所以这个项目的架构决策从隐私倒推：**推理必须本地**。顺带还收获两个好处——零 API 成本（8B 模型无限次调用不花钱）、断网可用。

## 模型选型：deepseek-r1:8b

选 Ollama 生态的两个原因：一行命令部署（`ollama pull deepseek-r1:8b`），以及 OpenAI 兼容的本地接口，后端对接成本极低。

模型选 deepseek-r1 的 8B 版本，考量是：

- **推理能力够用**：睡眠建议不是高难推理任务，8B 的思考深度足够给出结构化、有逻辑的建议，r1 的思考链反而让输出的"分析过程"部分质量不错
- **消费级硬件可跑**：8B 量化后在 8GB 显存的卡上流畅，纯 CPU 也能跑只是慢
- **中文能力好**：目标用户全中文，这点比英文强的同级别模型重要

## 架构：前后端分离，推理层独立

```
React + Ant Design (frontend/)
        │ HTTP
        ▼
FastAPI + SQLite (backend/)
   ├─ api/endpoints/chat.py      对话入口
   ├─ core/ollama.py             Ollama 客户端封装
   ├─ db/ (models/crud/session)  SQLAlchemy 分层
   └─ core/security.py           基础安全
        │ HTTP (localhost:11434)
        ▼
   Ollama (deepseek-r1:8b)
```

两个设计点：

**1. Ollama 客户端独立封装（`core/ollama.py`）**，而不是在 endpoint 里直接裸调。这样换模型、加重试、做流式适配都只动一个文件。Ollama 暴露的是 OpenAI 兼容接口，封装层用统一的 chat 方法收口：

```python
class OllamaClient:
    async def chat(self, messages: list[dict], model: str = "deepseek-r1:8b"):
        async with httpx.AsyncClient(base_url=OLLAMA_BASE) as client:
            resp = await client.post("/v1/chat/completions", json={
                "model": model, "messages": messages, "stream": False,
            })
            resp.raise_for_status()
            return resp.json()["choices"][0]["message"]["content"]
```

**2. SQLite + SQLAlchemy 分层**（models / crud / session / init_db）。用户睡眠档案（作息、环境、历史记录）是建议质量的根基，结构化存 SQLite；首次启动 `init_db` 自动建表，本地跑零配置。

## 提示词设计：顾问，不是医生

睡眠建议的提示词有两个红线：**不能给出医疗诊断**，**不能只输出空洞的正确废话**（"保持规律作息、睡前少玩手机"这种谁都知道的话没有价值）。

所以 system prompt 做了三件事：

1. **角色限定**：睡眠健康顾问，基于用户描述分析作息模式，输出改善建议；明确声明不做医疗诊断，出现疑似病理特征（长期严重失眠、呼吸暂停症状）建议就医
2. **结构化输出**：现状分析 → 可能的影响因素 → 可执行的改善建议（按优先级）→ 一张可落地的作息调整表
3. **个性化锚定**：要求建议必须引用用户档案里的具体信息（"你提到平均 1 点入睡但 6 点半起床，睡眠时长不足 6 小时"），逼模型基于上下文而不是模板说话

r1 的思考链在这里是加分项：用户能看到模型的"分析过程"，比直接吐结论更有可信感。

## 本地推理的真实体验

说实话部分：

- **延迟是最大短板**。CPU 推理时 r1:8b 的首 token 延迟在秒级到十秒级，思考链还会拉长总时长。GPU 上体验流畅，纯 CPU 建议换更小模型
- **Ollama 的进程管理很省心**，模型加载后常驻显存，后续请求快；长时间空闲自动卸载，不影响日常用机
- **质量上，8B 做睡眠建议是够用的**——这个任务的本质是"结构化常识 + 个性化组织"，不是知识密集型推理

和云端 API 的对比：质量上 GPT/Claude 级别的模型确实更强，但对"睡眠建议"这个任务，8B + 好的提示词能做到云端 80 分方案的水准，而隐私、成本、离线三项完胜。**选本地还是云端，取决于问题域对隐私的敏感度，而不是模型榜单排名**——这是这个项目给我最大的认知修正。

## 局限与下一步

- 目前 `stream=False` 一把梭，长思考时前端等待明显，流式输出（SSE）是第一优先级
- 睡眠数据靠手动描述，之前写过[小米健康数据接入](/2026/07/17/xiaomi-health-integration/)的实践，把可穿戴设备的睡眠分期数据自动接进来，建议的个性化程度会上一个台阶
- SQLite 单机版足够，但如果做多设备，需要把档案同步和 RAG 检索补上

整个项目的代码结构不复杂，但它验证了一个趋势：**在隐私敏感的个人数据场景，本地小模型 + 好的提示词工程，已经可以做出"够用且敢用"的 AI 应用**。
