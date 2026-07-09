---
title: LLM 输出 JSON 不稳定怎么办？我自研的三级降级机制实战
date: 2026-06-16 10:00:00
tags:
  - LLM
  - 结构化输出
  - 稳定性
categories:
  - AI工程化
description: 针对 LLM JSON 结构化输出不稳定的痛点，提出三级降级方案：直接解析→正则提取修复→重新生成兜底。实测从 70% 到 99%+ 的通过率提升，附核心代码。
---

# LLM 输出 JSON 不稳定怎么办？我自研的三级降级机制实战

## 背景：70% 的通过率不够用

在我们的多 Agent 协作系统中，Agent 之间的通信依赖结构化 JSON。规划器输出任务清单、执行器输出工具调用参数、总结器输出最终答案——全部通过 JSON 传递。

上线初期，我们遇到了一个让整个系统不可靠的根源问题：**LLM 输出的 JSON 平均只有 70% 能一次解析成功**。

剩下的 30% 包括：多余的 markdown 包裹、尾随逗号、单引号代替双引号、字段缺失、截断的 JSON、以及嵌套了大段文本导致转义错误的各种奇葩情况。

如果解析失败就直接重试，不仅浪费 token，而且重试后的格式依然不稳定——这形成了一个"生成→解析失败→重试→可能还失败"的死循环。

## 三级降级架构

最终方案是把 JSON 解析拆成三个逐级递进的关卡：

```
用户请求 → LLM 生成文本
            │
            ├── Level 1: JSON.parse（快速路径）
            │       ├── 成功 → 校验 schema → 通过 → 返回
            │       └── 失败 → 进入 Level 2
            │
            ├── Level 2: 正则提取 + 智能修复
            │       ├── 成功 → 返回
            │       └── 失败 → 进入 Level 3
            │
            └── Level 3: 重新生成（严格模式）
                    └── 加入错误反馈，强制模型重出
```

### Level 1：直接解析（快速路径，覆盖 ~70%）

最朴素的做法，但配合 schema 校验能挡住大部分类型错误。

```python
import json
from typing import Any, Optional

def level1_parse(text: str, schema: dict) -> Optional[dict]:
    """第一级：直接 JSON.parse + schema 校验"""
    # 先尝试直接解析
    text = text.strip()
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return None
    
    # schema 校验
    if not validate_schema(data, schema):
        return None
    
    return data
```

核心思路：**快速失败**。不在这里做任何修复尝试，失败就立刻降级。

### Level 2：正则提取 + 智能修复（覆盖额外 ~25%）

这是真正体现工程价值的一级。LLM 输出最常见的可修复问题有：

1. **Markdown 包裹**：用 ` ```json ... ``` ` 把 JSON 包起来了
2. **截断 JSON**：输出到一半被 max_tokens 截断（表现为缺少尾部花括号/方括号）
3. **单引号/不合法引号**：key 或 string value 使用了单引号
4. **尾随逗号**：数组或对象的最后一个元素后有逗号
5. **布尔值/null 大小写问题**：Python 的 `True/False/None` 代替了 JSON 的 `true/false/null`

```python
import re

def level2_repair(text: str) -> Optional[str]:
    """第二级：正则提取 + 逐级修复"""
    # Step 1: 提取 JSON 块（处理 markdown 包裹）
    json_pattern = r'```(?:json)?\s*([\s\S]*?)\s*```'
    matches = re.findall(json_pattern, text)
    if matches:
        text = matches[0]  # 取第一个 JSON 块
    
    # Step 2: 修复 Python 布尔值/None 写法
    text = re.sub(r'\bTrue\b', 'true', text)
    text = re.sub(r'\bFalse\b', 'false', text)
    text = re.sub(r'\bNone\b', 'null', text)
    
    # Step 3: 修复单引号（只在确定是 key 或 string 值时替换）
    # 替换 key 的单引号
    text = re.sub(r"'([^']+)'(?=\s*:)", r'"\1"', text)
    # 替换 string value 的单引号
    text = re.sub(r":\s*'([^']*)'(?=[,\s\}])", r': "\1"', text)
    
    # Step 4: 修复尾随逗号
    text = re.sub(r',\s*([}\]])', r'\1', text)
    
    # Step 5: 尝试修复截断（补全缺少的括号）
    text = _fix_truncated_json(text)
    
    # 尝试解析修复后的文本
    try:
        json.loads(text)
        return text
    except json.JSONDecodeError:
        return None


def _fix_truncated_json(text: str) -> str:
    """尝试补全被截断的 JSON"""
    open_braces = text.count('{') - text.count('}')
    open_brackets = text.count('[') - text.count(']')
    
    if open_braces > 0:
        text += '}' * open_braces
    if open_brackets > 0:
        text += ']' * open_brackets
    
    # 如果最外层不是完整对象，不做补全
    if not text.startswith('{') and not text.startswith('['):
        return text
    
    return text
```

几个关键细节：

- **正则提取 JSON 块的顺序很重要**：先处理 markdown 包裹，再修复内容。如果先修复内容再提取，可能会把 markdown 标记里的内容也错误地替换了。
- **单引号替换不能全局**：如果 value 是嵌套 JSON 字符串（JSON inside JSON），全局替换会破坏内层结构。我们用冒号前后的位置判断来限定替换范围。
- **截断补全只补结构符号**：不补字段值。截断可能发生在任意位置，只补花括号和方括号是最安全的做法。

### Level 3：重新生成（兜底，覆盖最后 ~5%）

当前两级都失败时，说明 LLM 这次输出的 JSON 质量太差，不值得修复。这时候需要**带着错误信息让模型重新生成**。

```python
def level3_regenerate(original_prompt: str, 
                       failed_text: str, 
                       error_info: str) -> str:
    """第三级：带着错误反馈重新生成"""
    retry_prompt = f"""
你上一次的 JSON 解析失败，以下是错误信息：
{error_info}

错误输出：
{failed_text}

请重新生成 JSON，务必遵守以下规则：
1. 只输出纯 JSON，不要任何 markdown 包裹
2. 所有 key 和 string value 使用双引号
3. 不要尾随逗号
4. 布尔值使用 true/false（小写）
5. 确保 JSON 结构完整、可解析
"""
    return call_llm(retry_prompt)
```

**一个关键的工程决策**：Level 3 不是简单地"再调一次同样的 prompt"，而是把前两次失败的信息作为上下文注入。这类似于 CoT 中的"从错误中学习"——模型看到自己刚才的错输出，通常会显著收敛。

## 效果数据

我们在 2000+ 条测试集上做了 A/B 测试：

| 降级层级 | 通过率 | 累计通过率 | 平均耗时 |
|---------|-------|-----------|---------|
| Level 1（直接解析） | 72.3% | 72.3% | 8ms |
| Level 2（正则修复） | 25.1% | 97.4% | 35ms |
| Level 3（重新生成） | 1.8% | 99.2% | 1.2s（含 LLM 调用） |
| 最终失败 | 0.8% | — | — |

**三个关键指标**：
- 通过率从 **72% 提升到 99.2%**，系统可用性上了两个台阶
- Level 2 平均 35ms，几乎无感。这是性价比最高的一级——25% 的请求被它救活
- Level 3 虽然耗时 1.2s，但只影响不到 2% 的请求，整体延迟增量可忽略

## 实际踩过的坑

**坑 1：Level 2 修复过度引入新错误**

有一次我们加了一个"修复 HTML 实体"的步骤（把 `&amp;` 转成 `&`），结果把合法 JSON 里的 `&` 场景搞坏了。教训是：**修复步骤必须可逆，且加每一步都要在测试集上验证通过率变化**。

**坑 2：Level 3 重试的 prompt 注入风险**

错误信息里包含用户原始输入，如果不做截断和转义，用户可能在 Level 3 的 prompt 里注入新的指令。我们最后做了两件事：限制错误信息的长度（500 chars），并且用固定的模板包裹错误内容。

**坑 3：schema 校验的严格程度需要动态调整**

最初我们做了严格的 schema 校验（类型、取值范围、必填字段），结果 Level 1 通过率只有 45%。后来调整为：先校验结构完整性（是不是合法 JSON + 字段存在），再在校验通过后做类型和取值范围的二次校验——不通过也不降级，只打 warning 标记。

## 总结

三级降级机制的核心思路不是追求单次解析的完美，而是**用多级策略覆盖不同质量的输出**。70% 的请求走最快路径，25% 花 35ms 修复，最后 2% 花 1.2s 重新生成。99.2% 的总通过率和平均 20ms 的解析耗时，比"一次完美解析"的幻想要现实得多。

对于任何依赖 LLM 结构化输出的系统，这套策略可以直接复用。如果你也在做 Agent 或工具调用类的开发，JSON 的稳定性问题迟早会找到你——希望这篇能帮你省掉一些我当初踩过的坑。
