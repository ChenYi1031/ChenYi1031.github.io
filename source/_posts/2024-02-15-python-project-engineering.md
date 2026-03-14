---
title: Python 项目工程化：pyproject.toml、依赖锁定与可复现构建
date: 2024-02-15 10:00:00
tags:
  - Python
  - 工程化
  - 依赖管理
categories:
  - 开发技术
description: 用 pyproject.toml 统一项目配置，结合锁文件与虚拟环境隔离，让本地与 CI 构建一致。
---

# Python 项目工程化：pyproject.toml、依赖锁定与可复现构建

## 目标：可复现\n\n工程化的核心不是『工具多』，而是你在本地能跑通的东西，在 CI 上也能 1:1 跑通。\n\n## pyproject.toml 统一入口\n\n把测试、格式化、类型检查的配置集中到 pyproject.toml，减少散落在多个文件里的配置漂移。\n\n## 依赖锁定与升级策略\n\n- 开发依赖和生产依赖分组管理\n- 升级用『小步快跑』：一次只升级一组关键依赖\n- 对关键库加约束范围，避免上游破坏性更新\n\n## 一个最小目录结构\n\n`	ext\nproject/\n  pyproject.toml\n  src/\n  tests/\n  .github/workflows/\n`\n\n## CI 要点\n\n在 CI 里固定 Python 版本、固定依赖锁文件，跑 pytest + 覆盖率，再跑 uff/black/mypy（按你团队习惯）。
