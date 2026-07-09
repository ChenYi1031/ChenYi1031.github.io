---
title: 从 LangChain 到 LangGraph：一个多 Agent 协作系统的重构实录
date: 2026-06-23 10:00:00
tags:
  - LangGraph
  - 多Agent
  - LLM
  - Agent
categories:
  - AI工程化
description: 为什么从 LangChain 链式调用迁移到 LangGraph StateGraph？StateGraph 的节点设计、状态共享、条件路由和超限保护的完整实现方案与踩坑记录。
---

# 从 LangChain 到 LangGraph：一个多 Agent 协作系统的重构实录

## 为什么要迁移

我们的 CollabAgent 系统最初基于 LangChain 的 `AgentExecutor` + 链式调用搭建。核心流程是：

```
用户输入 → 规划器(Planner) → 执行器(Executor) → 总结器(Summarizer) → 输出
```

每个环节都是一个独立的 Chain，用 `SequentialChain` 串联。初期跑得很顺，但随着需求变复杂，问题开始暴露：

**问题 1：状态传递失控**

当 Agent 数量超过 3 个时，Chain 之间的状态依赖变成了意大利面。A 的输出需要传给 C 和 D，但 B 也要用 A 的一部分输出——你不得不在每个 Chain 的 output 里塞满所有下游可能需要的字段。

**问题 2：条件分支难以表达**

"如果工具调用结果包含错误，重试最多 3 次"这个逻辑，在 Chain 里只能用 `LLMRouterChain` + 一个硬编码的循环计数器来模拟，既不直观也不可靠。

**问题 3：超限保护都是黑盒 hack**

超时控制、重试次数限制、并行工具调用数的管理，全在 Chain 外部的 wrapper 里——业务逻辑和运维逻辑耦合得一塌糊涂。

## LangGraph 的重构方案

LangGraph 的 StateGraph 模型本质上是**一个有状态的有向图**。每个节点是一个计算单元，边定义了数据流向，全局状态在节点之间传递。这不就是多 Agent 协作系统天然的表达方式吗？

### 架构概览

重构后的 CollabAgent 架构是一个完整的 StateGraph：

```
                         ┌──────────────────┐
                         │    Human Input    │
                         └────────┬─────────┘
                                  ▼
                         ┌──────────────────┐
                         │    Supervisor     │  ← 任务分解与分配
                         └────────┬─────────┘
                                  ▼
                    ┌─────────────┴─────────────┐
                    ▼                           ▼
            ┌──────────────┐           ┌──────────────┐
            │   Planner    │           │   Retriever  │
            │  (子任务拆分)  │           │  (知识检索)   │
            └──────┬───────┘           └──────┬───────┘
                    ▼                           ▼
            ┌──────────────┐           ┌──────────────┐
            │   Executor   │◄──────────│   Re-ranker  │
            │  (工具调用)   │           │  (结果排序)   │
            └──────┬───────┘           └──────┬───────┘
                    ▼                           │
            ┌──────────────┐                    │
            │  Quality     │────────────────────┘
            │  Checker     │
            └──────┬───────┘
                    ▼
            ┌──────────────┐
            │  Summarizer  │
            └──────────────┘
```

### StateGraph 的核心实现

```python
from typing import Dict, List, Optional, TypedDict, Literal, Any
from langgraph.graph import StateGraph, Graph
from langgraph.checkpoint import MemorySaver
from langgraph.types import NodeReturn


# ─── Agent 全局状态定义 ───
class AgentState(TypedDict):
    """全局共享状态"""
    messages: List[Dict]          # 完整的对话历史
    task_plan: Optional[Dict]     # 当前任务的分解计划
    tool_results: List[Dict]      # 工具调用结果
    current_node: str             # 当前所处的节点
    errors: List[str]             # 节点级错误记录
    retry_count: int              # 当前 retry 次数
    max_retries: int              # 最大 retry 次数
    is_complete: bool             # 是否完成
    final_answer: Optional[str]   # 最终输出


# ─── 节点定义 ───
def supervisor_node(state: AgentState) -> NodeReturn:
    """Supervisor：分析用户输入，分配任务"""
    messages = state["messages"]
    # 用 LLM 判断当前需要哪个子节点处理
    decision = call_llm_for_decision(messages)
    
    return {
        "current_node": decision["next_node"],
        "task_plan": decision.get("plan"),
    }


def planner_node(state: AgentState) -> NodeReturn:
    """Planner：将复杂任务拆解为可执行的子任务序列"""
    task = state["task_plan"]
    plan = decompose_task(task)
    
    # 更新状态中的子任务列表
    return {
        "task_plan": {**task, "subtasks": plan},
        "current_node": "executor",
    }


def executor_node(state: AgentState) -> NodeReturn:
    """Executor：执行工具调用，支持多工具并行"""
    subtasks = state["task_plan"].get("subtasks", [])
    results = []
    errors = []
    
    for subtask in subtasks:
        try:
            result = execute_tool(subtask)
            results.append({"task": subtask, "result": result})
        except Exception as e:
            errors.append({"task": subtask, "error": str(e)})
    
    return {
        "tool_results": state["tool_results"] + results,
        "errors": state["errors"] + errors,
        "current_node": "quality_checker",
    }


def quality_checker_node(state: AgentState) -> NodeReturn:
    """Quality Checker：校验执行结果质量，决定是否重试或继续"""
    errors = state["errors"]
    retry_count = state["retry_count"]
    max_retries = state["max_retries"]
    
    if errors and retry_count < max_retries:
        return {
            "retry_count": retry_count + 1,
            "current_node": "executor",  # 回到 executor 重试
        }
    elif errors and retry_count >= max_retries:
        return {
            "current_node": "summarizer",  # 超限后进入总结阶段
            "errors": errors + ["Max retries exceeded"],
        }
    else:
        return {"current_node": "summarizer"}
```

### 条件路由的边界情况处理

条件路由（Conditional Edge）是 LangGraph 最强大的特性之一，但也是最容易写错的地方。

```python
# ─── 构建图结构 ───
def build_agent_graph() -> Graph:
    workflow = StateGraph(AgentState)
    
    # 添加节点
    workflow.add_node("supervisor", supervisor_node)
    workflow.add_node("planner", planner_node)
    workflow.add_node("executor", executor_node)
    workflow.add_node("quality_checker", quality_checker_node)
    workflow.add_node("summarizer", summarizer_node)
    
    # 设置入口
    workflow.set_entry_point("supervisor")
    
    # ─── 条件路由 ───
    # Supervisor 根据输入复杂度决定走哪个子节点
    workflow.add_conditional_edges(
        "supervisor",
        lambda state: state["current_node"],
        {
            "planner": "planner",      # 复杂任务 → 先规划
            "executor": "executor",    # 简单任务 → 直接执行
            "summarizer": "summarizer", # 无需执行 → 直接总结
        }
    )
    
    # Planner → Executor（固定边）
    workflow.add_edge("planner", "executor")
    
    # Quality Checker 的条件路由
    workflow.add_conditional_edges(
        "quality_checker",
        lambda state: state["current_node"],
        {
            "executor": "executor",      # 重试
            "summarizer": "summarizer",  # 继续
        }
    )
    
    workflow.add_edge("summarizer", END)
    
    return workflow.compile(
        checkpointer=MemorySaver(),
    )
```

**踩坑记录**：条件路由的 `lambda` 函数中访问 `state` 时，需要确保 `state` 中对应的 key 已经被初始化。我们在 `AgentState` 中给所有字段都设置了默认值或 `Optional` 类型，避免在图首次执行时因 key 缺失而报错。

### 超限保护的工程化实现

Agent 系统最怕的就是死循环或者无限 retry。LangGraph 的打断机制（Interrupt）是官方推荐方案，但我们的场景更复杂——需要分节点、分级别的超限保护。

```python
from langgraph.errors import GraphInterrupt
from datetime import datetime, timedelta

class TimeoutGuard:
    """节点级超时保护"""
    
    def __init__(self, node_timeouts: Dict[str, int]):
        self.node_timeouts = node_timeouts  # 每个节点的超时秒数
        self.node_start_times: Dict[str, datetime] = {}
    
    def on_node_enter(self, node_name: str):
        """节点开始时记录时间"""
        self.node_start_times[node_name] = datetime.now()
    
    def on_node_exit(self, node_name: str):
        """节点结束时清除记录"""
        self.node_start_times.pop(node_name, None)
    
    def check_timeout(self, node_name: str) -> bool:
        """检查当前节点是否超时"""
        if node_name not in self.node_timeouts:
            return False
        if node_name not in self.node_start_times:
            return False
        
        elapsed = (datetime.now() - self.node_start_times[node_name]).seconds
        return elapsed > self.node_timeouts[node_name]


# 全局循环检测
class LoopDetector:
    """循环检测：防止 Agent 在两个节点之间无限跳转"""
    
    def __init__(self, threshold: int = 5):
        self.visit_counts: Dict[str, int] = {}
        self.transition_history: List[tuple] = []
        self.threshold = threshold
    
    def record_transition(self, from_node: str, to_node: str) -> bool:
        """
        记录一次节点转移。
        返回 True 表示检测到循环，需要打断。
        """
        self.transition_history.append((from_node, to_node))
        
        # 检测两节点循环（A→B→A→B→...）
        if len(self.transition_history) >= 4:
            recent = self.transition_history[-4:]
            if (recent[0][0] == recent[2][0] and 
                recent[0][1] == recent[2][1] and
                recent[1][0] == recent[3][0] and
                recent[1][1] == recent[3][1]):
                return True  # 检测到 A→B→A→B 循环
        
        return False
```

### 迁移后的效果数据

| 维度 | LangChain 链式 | LangGraph StateGraph |
|------|---------------|-------------------|
| 代码行数（核心编排） | ~850 行 | ~520 行 |
| 状态管理 | 手动拼接 dict | TypedDict 自动状态传递 |
| 条件分支 | LLMRouterChain + 外部 if/else | Conditional Edge（原生） |
| 超限保护 | 外部 wrapper | Graph Interrupt + 自定义 Guard |
| 失败率 | ~8.3% | ~3.1% |
| 平均响应时间 | 4.2s | 3.8s |
| 可观测性 | 手动打点 | LangSmith 原生追踪 |

## 迁移引入的新问题

LangGraph 不是银弹。迁移后我们遇到了几个新问题：

**问题 1：状态冲突**

多个节点同时写同一个状态字段时，后执行的节点会覆盖前面的结果。我们的解决方案是**逐节点明确写权限**——每个节点只写自己负责的字段，读其他字段。如果在 `AgentState` 里加一个字段，必须在代码注释中标明"哪个节点写入"。

**问题 2：调试复杂度上升**

链式调用的调试思路是线性的：A→B→C，出问题查 A 的输出就行。图结构的问题可能是路径选择错了，也可能是某个节点的状态被另一个节点污染了。我们最终靠 LangSmith 的 tracing 和图可视化来做调试定位——肉眼追代码已经不可行了。

**问题 3：图的序列化与恢复**

当图执行到一半中断（比如 LLM 调用超时），重启后图的状态恢复并不完美。`MemorySaver` 保存了 checkpointer state，但外部系统的状态（已经执行的工具调用、半完成的子任务）不会自动回滚。我们加了一层 Saga 模式的补偿逻辑——每个节点在执行前注册一个 rollback 回调。

## 总结

从 LangChain 到 LangGraph 的迁移，最大的收益不是性能提升（虽然确实有），而是**把 Agent 的协作逻辑从"线性代码"变成了"图结构"**——这让复杂的状态管理、条件分支和超限保护有了原生的表达方式。

如果你也在做 3 个以上 Agent 的协作系统，并且已经遇到了状态传递失控的问题，LangGraph 值得一试。但不要低估图的调试难度和状态恢复的复杂性——这些是图结构本身的代价，框架解决不了。
