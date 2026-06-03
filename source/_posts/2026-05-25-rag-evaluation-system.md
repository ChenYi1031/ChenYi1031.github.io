---
title: 构建RAG评测体系：让问答准确率稳定在85%+
date: 2026-05-25 10:00:00
tags:
  - RAG
  - 评测
  - Prompt工程
categories:
  - AI工程化
---

## 引言

在RAG系统的开发和迭代过程中，**如何科学地评测系统效果**是一个关键问题。本文分享我们在阿里云百炼平台上构建离线+在线评测体系的经验，以及如何通过Prompt优化让问答准确率稳定在85%+。

## 评测体系架构

### 整体架构

```
┌─────────────────────────────────────────────────────────┐
│                    RAG评测体系                           │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │  离线评测   │  │  在线评测   │  │  A/B测试    │     │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
│         │                │                │             │
│         ▼                ▼                ▼             │
│  ┌─────────────────────────────────────────────────┐   │
│  │              评测指标体系                        │   │
│  │  · 准确率  · 相关性  · 一致性  · 响应时间        │   │
│  └─────────────────────────────────────────────────┘   │
│         │                                               │
│         ▼                                               │
│  ┌─────────────────────────────────────────────────┐   │
│  │              数据采集与分析                      │   │
│  │  · 查询日志  · 用户反馈  · 系统性能              │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## 离线评测体系

### 1. 评测数据集构建

```python
# 评测数据集构建
class RAGEvalDataset:
    """RAG评测数据集"""
    
    def __init__(self):
        self.test_cases = []
    
    def add_test_case(self, query, expected_answer, 
                      context_docs=None, category=None):
        """添加测试用例"""
        self.test_cases.append({
            'id': len(self.test_cases) + 1,
            'query': query,
            'expected_answer': expected_answer,
            'context_docs': context_docs,
            'category': category,
            'created_at': datetime.now()
        })
    
    def load_from_json(self, file_path):
        """从JSON文件加载评测数据"""
        import json
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            for item in data:
                self.add_test_case(
                    query=item['query'],
                    expected_answer=item['expected_answer'],
                    context_docs=item.get('context_docs'),
                    category=item.get('category')
                )
    
    def save_to_json(self, file_path):
        """保存评测数据到JSON文件"""
        import json
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(self.test_cases, f, ensure_ascii=False, indent=2)
    
    def get_statistics(self):
        """获取数据集统计信息"""
        categories = {}
        for case in self.test_cases:
            cat = case['category'] or '未分类'
            categories[cat] = categories.get(cat, 0) + 1
        
        return {
            'total_cases': len(self.test_cases),
            'categories': categories
        }


# 创建评测数据集
dataset = RAGEvalDataset()

# 加载测试数据
dataset.load_from_json('eval_dataset.json')

# 打印统计信息
stats = dataset.get_statistics()
print(f"总测试用例: {stats['total_cases']}")
print(f"分类分布: {stats['categories']}")
```

### 2. 评测指标实现

```python
# 评测指标计算
import numpy as np
from collections import Counter

class RAGMetrics:
    """RAG评测指标"""
    
    def __init__(self):
        pass
    
    def accuracy(self, predictions, ground_truth):
        """
        计算准确率
        
        Args:
            predictions: 模型预测结果列表
            ground_truth: 真实答案列表
        """
        correct = 0
        for pred, gt in zip(predictions, ground_truth):
            # 使用模糊匹配计算准确率
            if self._fuzzy_match(pred, gt):
                correct += 1
        
        return correct / len(predictions) if predictions else 0
    
    def relevance(self, retrieved_docs, query):
        """
        计算检索相关性
        
        Args:
            retrieved_docs: 检索到的文档列表
            query: 用户查询
        """
        if not retrieved_docs:
            return 0
        
        relevance_scores = []
        for doc in retrieved_docs:
            # 计算文档与查询的语义相似度
            score = self._calculate_semantic_similarity(query, doc)
            relevance_scores.append(score)
        
        return np.mean(relevance_scores)
    
    def consistency(self, responses, n_samples=3):
        """
        计算回答一致性
        
        Args:
            responses: 对同一问题的多次回答
            n_samples: 采样次数
        """
        if len(responses) < 2:
            return 1.0
        
        # 计算回答之间的相似度
        similarities = []
        for i in range(len(responses)):
            for j in range(i + 1, len(responses)):
                sim = self._calculate_semantic_similarity(
                    responses[i], responses[j]
                )
                similarities.append(sim)
        
        return np.mean(similarities)
    
    def completeness(self, response, expected_info):
        """
        计算回答完整性
        
        Args:
            response: 模型回答
            expected_info: 期望包含的信息点
        """
        if not expected_info:
            return 1.0
        
        covered = 0
        for info in expected_info:
            if info.lower() in response.lower():
                covered += 1
        
        return covered / len(expected_info)
    
    def _fuzzy_match(self, pred, gt, threshold=0.8):
        """模糊匹配"""
        # 使用编辑距离或语义相似度进行匹配
        pred_lower = pred.lower().strip()
        gt_lower = gt.lower().strip()
        
        # 简单的包含关系匹配
        if gt_lower in pred_lower or pred_lower in gt_lower:
            return True
        
        # 计算字符级相似度
        similarity = self._calculate_char_similarity(pred_lower, gt_lower)
        return similarity >= threshold
    
    def _calculate_semantic_similarity(self, text1, text2):
        """计算语义相似度"""
        # 这里使用简单的词重叠作为示例
        # 实际项目中应使用Embedding模型
        words1 = set(text1.split())
        words2 = set(text2.split())
        
        if not words1 or not words2:
            return 0
        
        intersection = words1 & words2
        union = words1 | words2
        
        return len(intersection) / len(union)
    
    def _calculate_char_similarity(self, text1, text2):
        """计算字符级相似度"""
        if not text1 or not text2:
            return 0
        
        # 使用最长公共子序列
        m, n = len(text1), len(text2)
        dp = [[0] * (n + 1) for _ in range(m + 1)]
        
        for i in range(1, m + 1):
            for j in range(1, n + 1):
                if text1[i-1] == text2[j-1]:
                    dp[i][j] = dp[i-1][j-1] + 1
                else:
                    dp[i][j] = max(dp[i-1][j], dp[i][j-1])
        
        lcs_length = dp[m][n]
        return 2 * lcs_length / (m + n)
```

### 3. 自动化评测脚本

```python
# 自动化评测脚本
import json
from datetime import datetime

class RAGEvaluator:
    """RAG系统自动评测器"""
    
    def __init__(self, rag_system, eval_dataset):
        """
        Args:
            rag_system: RAG系统实例
            eval_dataset: 评测数据集
        """
        self.rag_system = rag_system
        self.dataset = eval_dataset
        self.metrics = RAGMetrics()
        self.results = []
    
    def run_evaluation(self, batch_size=10):
        """运行完整评测"""
        print("=" * 60)
        print("开始RAG系统评测")
        print("=" * 60)
        
        predictions = []
        ground_truths = []
        
        for i, test_case in enumerate(self.dataset.test_cases):
            print(f"\r评测进度: {i+1}/{len(self.dataset.test_cases)}", 
                  end="", flush=True)
            
            # 获取模型预测
            prediction = self.rag_system.query(test_case['query'])
            predictions.append(prediction['answer'])
            ground_truths.append(test_case['expected_answer'])
            
            # 记录详细结果
            self.results.append({
                'test_case': test_case,
                'prediction': prediction,
                'metrics': self._calculate_case_metrics(
                    prediction, test_case
                )
            })
        
        print("\n")
        
        # 计算整体指标
        overall_metrics = self._calculate_overall_metrics(
            predictions, ground_truths
        )
        
        # 生成评测报告
        report = self._generate_report(overall_metrics)
        
        return report
    
    def _calculate_case_metrics(self, prediction, test_case):
        """计算单个测试用例的指标"""
        return {
            'accuracy': self.metrics.accuracy(
                [prediction['answer']], 
                [test_case['expected_answer']]
            ),
            'relevance': self.metrics.relevance(
                prediction.get('retrieved_docs', []),
                test_case['query']
            ),
            'completeness': self.metrics.completeness(
                prediction['answer'],
                test_case.get('expected_info', [])
            )
        }
    
    def _calculate_overall_metrics(self, predictions, ground_truths):
        """计算整体指标"""
        return {
            'accuracy': self.metrics.accuracy(predictions, ground_truths),
            'avg_relevance': np.mean([
                r['metrics']['relevance'] for r in self.results
            ]),
            'avg_completeness': np.mean([
                r['metrics']['completeness'] for r in self.results
            ]),
            'consistency': self._measure_consistency()
        }
    
    def _measure_consistency(self):
        """测量一致性（对同一问题多次查询）"""
        # 选取部分测试用例进行一致性测试
        sample_cases = self.dataset.test_cases[:10]
        
        consistency_scores = []
        for case in sample_cases:
            responses = []
            for _ in range(3):
                response = self.rag_system.query(case['query'])
                responses.append(response['answer'])
            
            score = self.metrics.consistency(responses)
            consistency_scores.append(score)
        
        return np.mean(consistency_scores)
    
    def _generate_report(self, overall_metrics):
        """生成评测报告"""
        report = {
            'timestamp': datetime.now().isoformat(),
            'dataset_size': len(self.dataset.test_cases),
            'overall_metrics': overall_metrics,
            'detailed_results': self.results,
            'summary': self._generate_summary(overall_metrics)
        }
        
        # 保存报告
        report_path = f"eval_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(report_path, 'w', encoding='utf-8') as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
        
        print(f"评测报告已保存: {report_path}")
        
        return report
    
    def _generate_summary(self, metrics):
        """生成评测摘要"""
        summary = f"""
============================================================
                    RAG系统评测报告摘要
============================================================

评测时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
测试用例数: {len(self.dataset.test_cases)}

核心指标:
  - 准确率 (Accuracy): {metrics['accuracy']:.2%}
  - 平均相关性 (Relevance): {metrics['avg_relevance']:.2%}
  - 平均完整性 (Completeness): {metrics['avg_completeness']:.2%}
  - 一致性 (Consistency): {metrics['consistency']:.2%}

总体评价: {'优秀' if metrics['accuracy'] >= 0.9 else '良好' if metrics['accuracy'] >= 0.8 else '需改进'}
============================================================
"""
        print(summary)
        return summary


# 运行评测
evaluator = RAGEvaluator(rag_system, dataset)
report = evaluator.run_evaluation()
```

## 在线评测体系

### 1. 用户反馈收集

```python
# 用户反馈系统
class FeedbackCollector:
    """用户反馈收集器"""
    
    def __init__(self):
        self.feedback_data = []
    
    def collect_feedback(self, query_id, rating, comment=None):
        """
        收集用户反馈
        
        Args:
            query_id: 查询ID
            rating: 评分 (1-5)
            comment: 用户评论
        """
        self.feedback_data.append({
            'query_id': query_id,
            'rating': rating,
            'comment': comment,
            'timestamp': datetime.now()
        })
    
    def analyze_feedback(self):
        """分析用户反馈"""
        if not self.feedback_data:
            return {}
        
        ratings = [f['rating'] for f in self.feedback_data]
        
        return {
            'total_feedback': len(self.feedback_data),
            'avg_rating': np.mean(ratings),
            'rating_distribution': Counter(ratings),
            'satisfaction_rate': sum(1 for r in ratings if r >= 4) / len(ratings)
        }
```

### 2. 实时性能监控

```python
# 实时性能监控
import time
from functools import wraps

class PerformanceMonitor:
    """性能监控器"""
    
    def __init__(self):
        self.metrics = {
            'response_times': [],
            'query_count': 0,
            'error_count': 0
        }
    
    def monitor_response_time(self, func):
        """装饰器：监控响应时间"""
        @wraps(func)
        def wrapper(*args, **kwargs):
            start_time = time.time()
            try:
                result = func(*args, **kwargs)
                self.metrics['query_count'] += 1
                return result
            except Exception as e:
                self.metrics['error_count'] += 1
                raise
            finally:
                response_time = time.time() - start_time
                self.metrics['response_times'].append(response_time)
        return wrapper
    
    def get_performance_stats(self):
        """获取性能统计"""
        response_times = self.metrics['response_times']
        
        if not response_times:
            return {}
        
        return {
            'total_queries': self.metrics['query_count'],
            'total_errors': self.metrics['error_count'],
            'error_rate': self.metrics['error_count'] / max(self.metrics['query_count'], 1),
            'avg_response_time': np.mean(response_times),
            'p95_response_time': np.percentile(response_times, 95),
            'p99_response_time': np.percentile(response_times, 99)
        }
```

## Prompt优化策略

### 1. Few-shot Prompting

```python
# Few-shot Prompt模板
FEW_SHOT_PROMPT = """
你是一个专业的知识问答助手。请根据提供的上下文信息回答问题。

## 示例

用户问题：什么是RAG？
上下文：RAG（检索增强生成）是一种结合检索和生成的AI技术架构...
回答：RAG（Retrieval-Augmented Generation，检索增强生成）是一种将信息检索
与大语言模型生成相结合的技术架构。它通过先从知识库中检索相关文档，再基于
检索结果生成回答，有效减少了大模型的幻觉问题。

用户问题：如何优化向量检索？
上下文：向量检索优化可以从以下几个方面入手：1. 选择合适的Embedding模型...
回答：优化向量检索可以从以下几个方面入手：
1. 选择合适的Embedding模型：根据领域特点选择专用模型
2. 调整检索参数：如TopK、相似度阈值等
3. 使用混合检索：结合向量检索和关键词检索
4. 引入重排序：使用Re-rank模型优化排序

## 当前任务

上下文信息：
{context}

用户问题：{query}

请根据上述上下文信息回答问题，如果上下文中没有相关信息，请说明无法回答。
"""
```

### 2. Chain-of-Thought Prompting

```python
# CoT Prompt模板
COT_PROMPT = """
你是一个专业的知识问答助手。请使用链式思考（Chain-of-Thought）方法回答问题。

## 回答步骤

1. **理解问题**：首先明确用户在问什么
2. **检索相关信息**：从上下文中找出与问题相关的内容
3. **分析推理**：基于检索到的信息进行分析和推理
4. **组织答案**：将分析结果组织成清晰的回答
5. **验证答案**：检查答案是否完整、准确

## 当前任务

上下文信息：
{context}

用户问题：{query}

请按照上述步骤，详细说明你的思考过程，然后给出最终答案。
"""
```

### 3. 结构化输出Prompt

```python
# 结构化输出Prompt
STRUCTURED_OUTPUT_PROMPT = """
你是一个专业的知识问答助手。请按照指定的JSON格式输出回答。

## 输出格式

```json
{
    "answer": "详细的回答内容",
    "confidence": 0.95,  // 置信度，0-1之间
    "sources": [  // 引用的信息来源
        {
            "content": "引用的内容片段",
            "relevance": "high"  // high/medium/low
        }
    ],
    "related_questions": [  // 相关问题建议
        "相关问题1",
        "相关问题2"
    ],
    "follow_up_needed": false  // 是否需要追问
}
```

## 当前任务

上下文信息：
{context}

用户问题：{query}

请按照上述JSON格式输出回答。
"""
```

## 评测结果与优化

### 优化前后对比

| 指标 | 优化前 | 优化后 | 提升幅度 |
|------|--------|--------|---------|
| 问答准确率 | 72% | 85%+ | +13% |
| 首条命中率 | 45% | 68% | +23% |
| 用户满意度 | 70% | 88% | +18% |
| 系统可用性 | 95% | 99.5% | +4.5% |

### Prompt迭代优化记录

```python
# Prompt优化记录
prompt_optimization_history = [
    {
        'version': 'v1.0',
        'accuracy': 0.65,
        'changes': '基础Prompt模板',
        'notes': '初始版本，准确率较低'
    },
    {
        'version': 'v1.1',
        'accuracy': 0.72,
        'changes': '添加Few-shot示例',
        'notes': '添加了3个示例，准确率提升7%'
    },
    {
        'version': 'v1.2',
        'accuracy': 0.78,
        'changes': '引入CoT推理',
        'notes': '使用链式思考，准确率提升6%'
    },
    {
        'version': 'v2.0',
        'accuracy': 0.85,
        'changes': '结构化输出+置信度',
        'notes': '添加置信度评估和引用，准确率提升7%'
    }
]
```

## 自动化回归测试

```python
# 自动化回归测试
class RegressionTester:
    """回归测试器"""
    
    def __init__(self, rag_system, test_suite):
        self.rag_system = rag_system
        self.test_suite = test_suite
    
    def run_regression_test(self):
        """运行回归测试"""
        results = []
        
        for test_case in self.test_suite:
            # 运行测试
            prediction = self.rag_system.query(test_case['query'])
            
            # 验证结果
            passed = self._verify_prediction(
                prediction, test_case
            )
            
            results.append({
                'test_case': test_case,
                'prediction': prediction,
                'passed': passed
            })
        
        # 生成报告
        report = self._generate_regression_report(results)
        
        return report
    
    def _verify_prediction(self, prediction, test_case):
        """验证预测结果"""
        # 检查关键信息是否包含
        expected_keywords = test_case.get('expected_keywords', [])
        
        for keyword in expected_keywords:
            if keyword not in prediction['answer']:
                return False
        
        return True
    
    def _generate_regression_report(self, results):
        """生成回归测试报告"""
        passed = sum(1 for r in results if r['passed'])
        total = len(results)
        
        return {
            'total_tests': total,
            'passed': passed,
            'failed': total - passed,
            'pass_rate': passed / total if total > 0 else 0,
            'details': results
        }
```

## 使用Python封装API自动化回归脚本

```python
# API自动化回归脚本
import requests
import json
import time

class APIRegressionRunner:
    """API自动化回归测试运行器"""
    
    def __init__(self, api_url, api_key):
        self.api_url = api_url
        self.api_key = api_key
        self.session = requests.Session()
        self.session.headers.update({
            'Authorization': f'Bearer {api_key}',
            'Content-Type': 'application/json'
        })
    
    def test_query_api(self, query, expected_answer=None):
        """测试查询API"""
        start_time = time.time()
        
        response = self.session.post(
            f"{self.api_url}/query",
            json={'query': query}
        )
        
        response_time = time.time() - start_time
        
        result = {
            'status_code': response.status_code,
            'response_time': response_time,
            'response': response.json() if response.ok else None
        }
        
        # 验证响应
        if expected_answer:
            result['correct'] = self._verify_answer(
                result['response']['answer'],
                expected_answer
            )
        
        return result
    
    def run_regression_suite(self, test_suite):
        """运行回归测试套件"""
        results = []
        
        for test_case in test_suite:
            print(f"测试: {test_case['query'][:50]}...")
            
            result = self.test_query_api(
                test_case['query'],
                test_case.get('expected_answer')
            )
            
            results.append({
                'test_case': test_case,
                'result': result
            })
            
            # 避免请求过快
            time.sleep(0.1)
        
        return self._generate_report(results)
    
    def _verify_answer(self, predicted, expected):
        """验证答案"""
        # 简单的包含关系验证
        return expected.lower() in predicted.lower()
    
    def _generate_report(self, results):
        """生成测试报告"""
        total = len(results)
        passed = sum(1 for r in results if r['result'].get('correct', False))
        
        report = {
            'total_tests': total,
            'passed': passed,
            'failed': total - passed,
            'pass_rate': passed / total if total > 0 else 0,
            'avg_response_time': np.mean([
                r['result']['response_time'] for r in results
            ]),
            'details': results
        }
        
        print(f"\n回归测试报告:")
        print(f"  总测试数: {total}")
        print(f"  通过: {passed}")
        print(f"  失败: {total - passed}")
        print(f"  通过率: {report['pass_rate']:.2%}")
        print(f"  平均响应时间: {report['avg_response_time']:.3f}s")
        
        return report


# 运行回归测试
runner = APIRegressionRunner(
    api_url="https://api.bailian.com/v1",
    api_key="your_api_key"
)

# 加载测试套件
test_suite = json.load(open('test_suite.json'))

# 运行测试
report = runner.run_regression_suite(test_suite)
```

## 输出《Prompt设计指南》核心要点

### 1. Prompt设计原则

```
清晰性：明确说明任务要求和输出格式
具体性：提供具体的示例和约束条件
一致性：保持Prompt风格和格式一致
可测试性：设计可量化评估的Prompt
```

### 2. 常用Prompt技巧

```
Few-shot示例：提供3-5个高质量示例
链式思考：引导模型逐步推理
结构化输出：指定JSON等结构化格式
置信度评估：让模型评估回答的可信度
引用标注：要求标注信息来源
```

### 3. 评测指标参考

```
准确率 > 85%：优秀
准确率 80-85%：良好
准确率 70-80%：需优化
准确率 < 70%：需重新设计
```

## 总结

通过构建完整的离线+在线评测体系，配合持续的Prompt优化，我们成功将RAG问答准确率稳定在85%+，系统可用性达99.5%。

关键经验：
1. **评测先行**：建立科学的评测体系是优化的基础
2. **持续迭代**：Prompt优化是一个持续的过程
3. **自动化测试**：使用Python封装API自动化回归脚本
4. **数据驱动**：基于评测数据指导优化方向

这套评测体系已支撑日均千次稳定调用，有效保障了系统质量。

---

*评测体系的建设是AI工程化的重要环节，欢迎交流更多实践经验。*
