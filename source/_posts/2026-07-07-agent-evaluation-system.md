---
title: Agent 评测体系从 0 到 1：离线评测、Bad Case 回流与在线归因
date: 2026-07-07 10:00:00
tags:
  - Agent
  - 评测
  - 质量保障
categories:
  - AI工程化
description: 多 Agent 协作系统的评测体系搭建实战：评测集设计、多维度指标、Bad Case 回流机制、在线指标归因方法，以及 3 个被问爆的踩坑经验。
---

# Agent 评测体系从 0 到 1：离线评测、Bad Case 回流与在线归因

## 为什么 Agent 评测比 RAG 评测更难

做过 RAG 评测的人都知道，核心指标就是**命中率 + 生成准确率**——输入是 query，输出是 answer，对比 ground truth 就行。

但 Agent 不一样。一个任务可能涉及：

- 3 轮对话交互
- 5 次工具调用
- 2 次知识库检索
- 条件分支选择
- 中间状态的正确性

**评测 Agent 不是在评测"回答对不对"，而是在评测"决策过程对不对"**。

举个例子：用户问"帮我查一下上个季度的销售数据，画出趋势图发给团队"。一个正确的 Agent 执行路径可能是：

```
1. 调用 BI 工具查询销售数据（正确参数：2026 Q1-Q2）
2. 调用图表生成工具（选择折线图）
3. 调用飞书 API 发送消息（选择正确的群组）
```

如果第 1 步查成了今年的数据而不是上个季度，后面再花哨也没用。所以 Agent 评测必须**逐环节、分层级**地进行。

## 三层评测体系

我们的评测体系分为三层，每层覆盖不同阶段的验证需求：

```
┌─────────────────────────────────────────────────────┐
│                    Agent 评测体系                      │
├─────────────────────────────────────────────────────┤
│                                                       │
│  ┌──────────────────────────────────────────────┐    │
│  │          L1: 离线评测集（发布前）               │    │
│  │  · 200+ 条覆盖场景的标注测试集                  │    │
│  │  · 每个 case 标注：任务、预期路径、预期结果      │    │
│  │  · 全自动跑批，输出通过率报告                   │    │
│  └──────────────────────────────────────────────┘    │
│                          │                            │
│                          ▼                            │
│  ┌──────────────────────────────────────────────┐    │
│  │          L2: Bad Case 回流（迭代中）            │    │
│  │  · 线上采集失败案例 + 人工标注 ground truth    │    │
│  │  · 补充到离线评测集，防止回归                  │    │
│  │  · 每周一次回归跑批                            │    │
│  └──────────────────────────────────────────────┘    │
│                          │                            │
│                          ▼                            │
│  ┌──────────────────────────────────────────────┐    │
│  │          L3: 在线监控（生产环境）               │    │
│  │  · 任务完成率、工具调用准确率                    │    │
│  │  · 节点级超时率、重试率                         │    │
│  │  · 用户满意度（隐式反馈 + 显式评分）             │    │
│  └──────────────────────────────────────────────┘    │
│                                                       │
└─────────────────────────────────────────────────────┘
```

### L1：离线评测集

这是评测体系的基础设施。我们的离线评测集覆盖 **7 类场景、200+ 条 case**：

| 场景类别 | Case 数 | 覆盖内容 |
|---------|--------|---------|
| 知识问答 | 50 | 法条查询、政策解读、合规咨询 |
| 工具调用 | 40 | 参数构造、错误输入、超长输入 |
| 多轮对话 | 30 | 追问澄清、上下文引用、话题切换 |
| 复杂任务分解 | 30 | 多步规划、子任务依赖、并行执行 |
| 边界情况 | 25 | 空输入、无关问题、模糊意图 |
| 错误恢复 | 15 | 工具调用失败后的重试与回退 |
| 安全合规 | 15 | 拒绝回答越权问题、敏感信息过滤 |

评测执行器会逐条跑测，自动评估各个环节的通过情况：

```python
class AgentEvaluator:
    """Agent 评测执行器"""
    
    def __init__(self, test_suite: List[TestCase], agent: Agent):
        self.test_suite = test_suite
        self.agent = agent
    
    async def run_evaluation(self) -> EvaluationReport:
        """全量跑批评测"""
        results = []
        
        for case in self.test_suite:
            result = await self._evaluate_single(case)
            results.append(result)
        
        return self._aggregate(results)
    
    async def _evaluate_single(self, case: TestCase) -> CaseResult:
        """单条 case 评测"""
        # 执行 Agent
        agent_output = await self.agent.run(case.query)
        
        # 逐维度评测
        scores = {
            "path_correctness": self._eval_path(
                agent_output.trajectory, case.expected_path
            ),  # 路径正确性（最高权重）
            "tool_accuracy": self._eval_tool_calls(
                agent_output.tool_calls, case.expected_tool_calls
            ),  # 工具调用准确率
            "final_answer": self._eval_answer(
                agent_output.final_answer, case.expected_answer
            ),  # 最终答案正确性
            "efficiency": self._eval_efficiency(
                agent_output.tool_calls, agent_output.latency
            ),  # 执行效率
        }
        
        # 总分：加权平均
        weights = {
            "path_correctness": 0.35,
            "tool_accuracy": 0.30,
            "final_answer": 0.25,
            "efficiency": 0.10,
        }
        
        total = sum(scores[k] * weights[k] for k in weights)
        
        return CaseResult(
            case_id=case.id,
            passed=total >= case.pass_threshold,
            scores=scores,
            total=total,
            details=agent_output,
        )
```

**路径正确性** 是 Agent 评测的核心指标。我们把它定义为：Agent 的任务分解和执行路径与期望路径的 **Levenshtein 相似度**（编辑距离的变体），而不是简单的"最后答对了就行"。

### L2：Bad Case 回流闭环

离线评测集最大的问题是**静态化**——发布时测的是好的，上线后用户的真实输入和评测集分布完全不同。

Bad Case 回流机制就是为了解决这个漂移问题。

```
生产环境 → 采集失败案例 → 人工标注 ground truth → 
补充到离线评测集 → 回归跑批 → 修复 → 上线验证
```

**采集策略**：不是所有失败都要回流。我们的采集优先级：

1. **用户显式负面反馈**（点"没用"、输入"这回答不行"）：P0，立即采集
2. **工具调用失败**（返回异常、超时、空结果）：P0，立即采集
3. **完成率低**（任务开始但中途退出）：P1，日级采集
4. **隐式负反馈**（用户重复提问相同问题）：P2，周级采集

**标注规范**：每个 Bad Case 入库时必须标注三个字段：

| 字段 | 含义 | 示例 |
|------|------|------|
| `failure_layer` | 失败层次 | `retrieval` / `reasoning` / `tool` / `generation` |
| `failure_type` | 失败类型 | `wrong_params` / `missing_context` / `loop_deadlock` |
| `severity` | 严重程度 | `critical` / `major` / `minor` |

有了 `failure_layer`，我们就可以统计**哪个环节最薄弱**——这是驱动迭代方向的关键数据。

### L3：在线指标与归因

在线监控的核心目的不是"知道系统挂了"，而是**快速定位哪个环节出了问题**。

**指标体系**：

```python
# 在线指标（通过埋点采集）
ONLINE_METRICS = {
    # 任务级指标
    "task_completion_rate": "任务最终完成率",           # 预期 95%+
    "avg_task_duration": "平均任务完成时间",            # 预期 <30s
    "tool_call_success_rate": "工具调用成功率",          # 预期 98%+
    
    # 节点级指标
    "planner_timeout_rate": "规划器超时率",             # 预期 <1%
    "executor_retry_rate": "执行器重试率",               # 预期 <5%
    "quality_fallback_rate": "质检降级率",               # 预期 <3%
    
    # 用户满意度
    "explicit_satisfaction": "用户主动评分（1-5）",       # 预期 >4.0
    "implicit_satisfaction": "隐式满意度（停留/复访）",   # 综合模型计算
}
```

**归因方法：三步定位法**

当在线指标出现异常时，用三步法定位问题：

```
Step 1: 确定异常维度
  ↓  task_completion_rate 从 96% 跌到 82%
Step 2: 分层下钻
  ↓  tool_call_success_rate 从 98% 跌到 85% → 问题在工具层
Step 3: 根因定位
  ↓  查看具体失败的工具调用 → 发现 Confluence API 认证过期
```

这个归因流程看似简单，但**自动化**做起来很麻烦。我们用了一个归因分析器来辅助：

```python
class AttributionAnalyzer:
    """在线指标异常自动归因"""
    
    def analyze(self, baseline: dict, current: dict) -> AttributionResult:
        
        # 1. 全局异常检测
        deltas = {}
        for metric, value in current.items():
            if isinstance(value, (int, float)):
                baseline_val = baseline.get(metric, value)
                change = (value - baseline_val) / baseline_val
                deltas[metric] = change
        
        # 2. 找出最大下降指标
        worst_metric = min(deltas, key=deltas.get)
        
        # 3. 根据指标类型定位层次
        layer_hints = {
            "retrieval": ["hit_rate", "context_relevance"],
            "reasoning": ["path_correctness", "planner_timeout_rate"],
            "tool": ["tool_call_success_rate", "executor_retry_rate"],
            "generation": ["answer_accuracy", "hallucination_rate"],
        }
        
        for layer, metrics in layer_hints.items():
            if worst_metric in metrics:
                return AttributionResult(
                    abnormal_metric=worst_metric,
                    delta=deltas[worst_metric],
                    likely_layer=layer,
                    confidence=self._calculate_confidence(deltas, layer),
                )
```

## 踩坑实录

**坑 1：评测集的 ground truth 维护成本**

一开始我们让每个人各自标注 case，结果同一个 case 在不同人手里 ground truth 能差 30%。后来做了三件事：
1. 标注前统一写 annotation guideline（写清楚期望路径的判定边界）
2. 每个 case 至少 2 人背靠背标注，不一致的 case 走仲裁
3. 标注完成后，用自动脚本跑一遍"标注者一致性"——对标注差异 > 10% 的 case 打回重标

**坑 2：在线指标和离线评测结果对不上**

离线评测通过率 95%，上线后任务完成率只有 78%。排查后发现问题出在"用户输入长度"——离线评测集的 query 平均长度是 30 字，但线上用户的 query 平均长度是 120 字，长 query 导致检索层和推理层的表现显著变差。

修复方案：**离线评测集要定期用线上真实分布来刷新**。每月从线上日志中采样 50 条真实 query 替换掉评测集中过时的 case。

**坑 3：归因分析的滞后性**

出问题后才发现，比"定位到问题了"更重要的是"什么时候开始出问题的"。最初我们的监控粒度是 1 小时，但很多问题的根因（比如 API 认证过期、模型服务的隐式降级）在用户感知到之前就已经发生了。

最后把关键指标的监控粒度缩短到 5 分钟，并且对每个指标设置了**基线偏离预警**——指标在 15 分钟内偏离基线超过 3 个标准差就自动告警，不等人工巡检。

## 总结

评测体系是 Agent 系统的"仪表盘"——没有它，你只是在凭感觉优化。三层评测体系（离线集 → Bad Case 回流 → 在线监控）构成了一个完整质量闭环：

- **离线集**确保发布前质量
- **Bad Case 回流**防止问题反复出现
- **在线监控**确保生产环境稳定

最大的一点感悟：评测体系的建设不是一步到位的。先搭最简单的离线评测（50 条 case 起步），跑起来后再加回流，再加在线监控——比一开始就想建完美体系实际得多。
