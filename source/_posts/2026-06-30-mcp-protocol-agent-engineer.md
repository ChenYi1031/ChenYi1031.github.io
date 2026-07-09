---
title: MCP 协议：为什么 2026 年所有 Agent 工程师都应该懂它
date: 2026-06-30 10:00:00
tags:
  - MCP
  - Agent
  - 协议
categories:
  - AI工程化
description: 从 MCP 协议要解决的 M×N 工具集成问题出发，讲解协议核心设计、Server 搭建实践，以及如何在你的 Agent 框架中借鉴 MCP 的设计思想。
---

# MCP 协议：为什么 2026 年所有 Agent 工程师都应该懂它

## 一个每天都在上演的低效场景

你在做一个 Agent 系统，需要对接：

- 企业内部 Wiki（Confluence API）
- 代码仓库（GitHub API）
- Jira 工单系统
- 飞书/钉钉的消息推送
- 内部运维平台的工单系统

每个工具都要写一套独立的 tool definition：认证方式不同、参数格式不同、错误信息不同、限频策略不同。

过了一个月，你的 teammate 在做另一个 Agent 系统，他又重复写了一遍 Confluence tool。再过两个月，第三个 team 又写了一遍。

**这就是 M×N 问题**：M 个 Agent 系统 × N 个工具，每个对接都是 N² 级别的复杂度。

MCP（Model Context Protocol）要解决的就是这件事——它为 AI 应用（Host）和工具/数据源（Server）定义了一个标准协议，让工具可以"一次接入，到处使用"。

## MCP 协议的核心设计

MCP 采用了类似 client-server 的架构，但角色定义略有不同：

```
┌──────────────┐        ┌──────────────┐        ┌──────────────┐
│   MCP Host   │ ◄────► │  MCP Client  │ ◄────► │  MCP Server  │
│  (AI 应用)    │        │  (SDK/协议层) │        │  (工具封装)   │
│              │        │              │        │              │
│ - Claude     │        │ - 建立连接    │        │ - 暴露 Tools  │
│ - VS Code    │        │ - 能力协商    │        │ - 暴露 Resources
│ - 你的 Agent  │        │ - 调用转发    │        │ - 提供 Prompts │
└──────────────┘        └──────────────┘        └──────────────┘
```

### 三大核心抽象

MCP 定义了三类资源，每个 MCP Server 可以选择性地提供一个或多个：

**1. Tools（工具）**
函数式接口，AI 模型可以调用。有明确的输入 schema 和输出格式。**这是 Agent 系统最常对接的部分。**

**2. Resources（资源）**
类似 REST API 中的 GET 端点，用于向模型提供上下文数据。比如：当前项目文件、数据库 schema、用户信息等。

**3. Prompts（提示模板）**
预定义的 prompt 模板，用户或 AI 可以复用特定的交互模式。

### 一个 MCP Server 的完整实现

下面是一个真实的 MCP Server 示例——我们用它来封装公司的内部工具：

```python
from mcp.server import Server, NotificationOptions
from mcp.server.models import InitializationOptions
import mcp.server.stdio
import mcp.types as types
from typing import Any

class InternalToolServer:
    """公司内部工具的 MCP Server"""
    
    def __init__(self):
        self.server = Server("internal-tools")
        self._register_tools()
        self._register_resources()
    
    def _register_tools(self):
        """注册所有工具"""
        
        @self.server.list_tools()
        async def handle_list_tools() -> list[types.Tool]:
            return [
                types.Tool(
                    name="search_confluence",
                    description="搜索 Confluence 知识库",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "搜索关键词",
                            },
                            "space": {
                                "type": "string",
                                "description": "限定空间（可选）",
                            },
                            "limit": {
                                "type": "integer",
                                "description": "返回结果数",
                                "default": 5,
                            },
                        },
                        "required": ["query"],
                    },
                ),
                types.Tool(
                    name="get_incident",
                    description="查询运维工单详情",
                    inputSchema={
                        "type": "object",
                        "properties": {
                            "incident_id": {
                                "type": "string",
                                "description": "工单 ID",
                            },
                        },
                        "required": ["incident_id"],
                    },
                ),
            ]
        
        @self.server.call_tool()
        async def handle_call_tool(
            name: str, arguments: dict[str, Any] | None
        ) -> list[types.TextContent]:
            if name == "search_confluence":
                result = await self._confluence_search(arguments)
                return [types.TextContent(type="text", text=result)]
            elif name == "get_incident":
                result = await self._incident_query(arguments)
                return [types.TextContent(type="text", text=result)]
            else:
                raise ValueError(f"Unknown tool: {name}")
    
    def _register_resources(self):
        """注册资源提供"""
        
        @self.server.list_resources()
        async def handle_list_resources() -> list[types.Resource]:
            return [
                types.Resource(
                    uri="internal://users/me",
                    name="Current User",
                    description="当前登录用户信息",
                    mimeType="application/json",
                ),
            ]
        
        @self.server.read_resource()
        async def handle_read_resource(uri: str) -> str:
            if uri == "internal://users/me":
                return json.dumps({"name": "current_user", "role": "engineer"})
            raise ValueError(f"Unknown resource: {uri}")
```

### 在 Agent 中集成 MCP Client

我们的 CollabAgent 在 Agent 侧封装了一个 MCP Client Manager，统一管理所有 MCP Server 的连接：

```python
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from contextlib import AsyncExitStack
from typing import Dict, List

class MCPClientManager:
    """管理多个 MCP Server 连接"""
    
    def __init__(self):
        self.servers: Dict[str, dict] = {}
        self.sessions: Dict[str, ClientSession] = {}
        self.exit_stack = AsyncExitStack()
    
    async def connect_server(self, name: str, command: str, args: List[str]):
        """连接一个 MCP Server"""
        server_params = StdioServerParameters(
            command=command,
            args=args,
        )
        
        transport = await self.exit_stack.enter_async_context(
            stdio_client(server_params)
        )
        
        read, write = transport
        session = await self.exit_stack.enter_async_context(
            ClientSession(read, write)
        )
        await session.initialize()
        
        self.servers[name] = {"params": server_params}
        self.sessions[name] = session
        
        # 获取该 Server 暴露的所有工具
        tools = await session.list_tools()
        print(f"Server '{name}' 暴露了 {len(tools.tools)} 个工具")
        return tools.tools
    
    async def call_tool(self, server_name: str, 
                        tool_name: str, arguments: dict) -> str:
        """调用指定 Server 上的工具"""
        if server_name not in self.sessions:
            raise ValueError(f"Server {server_name} 未连接")
        
        result = await self.sessions[server_name].call_tool(
            tool_name, arguments
        )
        return result.content[0].text
```

## 我们在 CollabAgent 中借鉴了 MCP 的设计思想

虽然我们的系统没有直接在生产环境部署 MCP 协议（这是下一步的计划），但 MCP 的设计思想深刻影响了我们的工具抽象层。

**核心思路**：把每个工具封装成一个独立的"插件"，通过统一的 ToolSpec 接口暴露：

```python
class ToolSpec:
    """工具规范——借鉴 MCP 的 Tool 定义"""
    name: str
    description: str
    input_schema: dict  # JSON Schema
    output_type: str
    
    async def execute(self, **kwargs) -> Any:
        """执行工具——具体子类实现"""
        pass
    
    async def validate(self, **kwargs) -> bool:
        """校验参数合法性"""
        pass
```

每个工具（Confluence 搜索、GitHub PR 查询、Jira 工单创建）都实现这个接口。Agent 通过 `list_tools()` 获取所有可用工具，通过 `call_tool()` 调度执行——和 MCP 的通信模式一模一样。

**这么做的好处**：
- 新增一个工具只需写一个类，不需要改 Agent 核心逻辑
- 所有工具的认证、限频、错误处理统一管理
- 未来切换到真正的 MCP 协议时，只需要把 ToolSpec 适配层换成 MCP Client 调用——核心业务代码几乎不用动

## 避坑指南

**坑 1：stdio 传输的可靠性**

MCP 默认的 stdio 传输（子进程 stdin/stdout）在 Server 进程意外退出时，Client 侧不一定能及时感知。我们在 Client Manager 里加了一层心跳检测：

```python
async def health_check(self, interval: int = 30):
    while True:
        for name, session in self.sessions.items():
            try:
                await asyncio.wait_for(
                    session.list_tools(), timeout=5
                )
            except (asyncio.TimeoutError, Exception):
                print(f"Server '{name}' 无响应，尝试重连")
                await self.reconnect(name)
        await asyncio.sleep(interval)
```

**坑 2：工具返回的内容长度**

MCP 的工具返回值没有大小限制，但 LLM 的上下文窗口有限。如果工具返回一篇完整的 10 万行日志，模型根本看不完。我们加了一层 Smart Truncation——根据 Agent 当前上下文的剩余窗口动态截断工具返回。

**坑 3：认证信息的传递**

MCP 协议本身没有定义认证机制。如果你的 Server 需要用户级别的认证（比如"查张三的工单"），你需要在工具参数里显式传入 user_id，或者在建立连接时通过 environment 参数注入 token。我们最后选择了后者——在 `stdio_server_params` 的环境变量里注入会话级别的认证凭据。

## 什么时候值得上 MCP

| 场景 | 建议 |
|------|------|
| 只有 1-2 个工具，且不跨团队共享 | 没必要上 MCP，直接写 tool function 更快 |
| 3-5 个工具，但都是你一个人维护 | 用 ToolSpec 接口抽象就够了，不一定要 MCP 协议 |
| 5+ 个工具，跨团队/跨项目复用 | **强烈建议上 MCP**——标准化的收益远超接入成本 |
| 你的 Agent 需要对接第三方 SaaS | MCP 是未来趋势，提前适配降低未来迁移成本 |

## 总结

MCP 本质上是一个**工具集成标准化协议**。它不解决"AI 怎么调度工具"的问题，它解决的是"工具怎么被 AI 发现和调用"的问题。这两者的边界非常清晰。

对于 Agent 工程师来说，2026 年理解 MCP 的意义不在于你是否在生产环境部署了它，而在于你是否从"给这个 Agent 写个工具"的思维模式升级到了"给我的工具生态定义一个标准接口"的思维模式——前者是堆代码，后者是建基础设施。

如果你正在搭建 Agent 系统的工具抽象层，即便现在不接入 MCP 协议，也建议参考它的接口设计思路。这样当哪天业务方说"能不能把我们这个工具也接进来"的时候，你的回答不是"又要加一个适配层"，而是"写一个 MCP Server"。
