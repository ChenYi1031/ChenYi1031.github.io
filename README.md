# 陈 Yi 的小站 - 个人博客

🌐 **在线访问**: [https://chenyi1031.github.io](https://chenyi1031.github.io)

---

## 📖 项目简介

这是一个基于 **Hexo** 静态博客框架搭建的个人博客，使用 **Butterfly** 主题进行美化。博客主要用于记录学习笔记、技术分享和生活感悟。

### ✨ 特性

- 🚀 **快速加载** - 静态页面，CDN 加速
- 📱 **响应式设计** - 完美适配 PC 和移动设备
- 🎨 **精美主题** - Butterfly 主题，支持多种配色方案
- 🌙 **夜间模式** - 自动/手动切换深色模式
- 🔍 **站内搜索** - 快速查找文章内容
- 💬 **评论系统** - 支持 LeanCloud 评论
- 📊 **访问统计** - 不蒜子访问统计
- 🎯 **SEO 优化** - 搜索引擎友好

---

## 🛠️ 技术栈

| 技术 | 说明 |
|------|------|
| **Hexo** | 静态博客框架 |
| **Butterfly** | Hexo 主题 |
| **GitHub Pages** | 博客托管 |
| **Node.js** | 运行环境 |
| **Markdown** | 文章编写格式 |

---

## 📝 文章分类

- 📚 **学习笔记** - 计算机基础知识、软考笔记
- 💻 **技术分享** - 前端开发、框架使用、工具教程
- 📖 **生活感悟** - 日常记录、心得体会

---

## 🚀 本地运行

### 环境要求

- Node.js >= 14.0
- npm >= 6.0

### 安装依赖

```bash
# 克隆项目
git clone https://github.com/ChenYi1031/ChenYi1031.github.io.git

# 进入目录
cd ChenYi1031.github.io

# 安装依赖
npm install
```

### 启动本地服务

```bash
# 生成静态文件
hexo generate

# 启动本地服务器
hexo server

# 访问 http://localhost:4000
```

### 常用命令

```bash
# 新建文章
hexo new <article-name>

# 生成静态文件
hexo generate  # 或 hexo g

# 本地预览
hexo server  # 或 hexo s

# 部署到 GitHub
hexo deploy  # 或 hexo d

# 清理缓存
hexo clean
```

---

## 📁 项目结构

```
ChenYi1031.github.io/
├── _config.yml          # 站点配置文件
├── package.json         # 项目依赖配置
├── scaffolds/           # 文章模板
├── source/              # 资源文件
│   ├── _posts/          # 文章目录
│   ├── _data/           # 自定义数据
│   ├── categories/      # 分类页面
│   ├── tags/            # 标签页面
│   ├── about/           # 关于页面
│   └── img/             # 图片资源
├── themes/              # 主题目录
│   └── Butterfly/       # Butterfly 主题
└── public/              # 生成的静态文件
```

---

## ⚙️ 主题配置

### 主要配置文件

- **`_config.yml`** - 站点配置
- **`themes/Butterfly/_config.yml`** - 主题配置

### 常用配置项

```yaml
# 站点信息
title: 陈 Yi 的小站
subtitle: 我欲穿花寻路，直入白云深处
author: 陈 Yi 的小站
language: zh-CN

# 菜单配置
menu:
  首页: / || fa fa-home
  归档: /archives/ || fa fa-archive
  标签: /tags/ || fa fa-tags

# 社交链接
social:
  fa fa-github: https://github.com/ChenYi1031

# 代码高亮
highlight_theme: light
highlight_copy: true
highlight_lang: true

# 夜间模式
darkmode:
  enable: true
```

---

## 🎨 主题 customization

### 修改配色

在 `themes/Butterfly/_config.yml` 中配置：

```yaml
theme_color:
  enable: true
  main: "#49B1F5"
  paginator: "#00c4b6"
  button_hover: "#FF7242"
```

### 添加特效

```yaml
# 打字特效
activate_power_mode:
  enable: true

# 背景线条
canvas_nest:
  enable: true
  
# 烟花特效
fireworks:
  enable: true
```

---

## 📦 依赖插件

```json
{
  "hexo": "^6.3.0",
  "hexo-generator-archive": "^2.0.0",
  "hexo-generator-category": "^2.0.0",
  "hexo-generator-index": "^3.0.0",
  "hexo-generator-tag": "^2.0.0",
  "hexo-renderer-ejs": "^2.0.0",
  "hexo-renderer-marked": "^6.0.0",
  "hexo-renderer-stylus": "^3.0.0",
  "hexo-server": "^3.0.0"
}
```

---

## 📄 许可证

本博客文章采用 **CC BY-NC-SA 4.0** 许可协议
- ✅ 允许分享和改编
- ⚠️ 需注明原作者
- ⚠️ 禁止商业用途
- ⚠️ 相同方式共享

---

## 📬 联系方式

- **GitHub**: [@ChenYi1031](https://github.com/ChenYi1031)
- **博客**: [https://chenyi1031.github.io](https://chenyi1031.github.io)
- **Email**: [通过 GitHub 联系](https://github.com/ChenYi1031)

---

## 🙏 致谢

- [Hexo 官方文档](https://hexo.io/zh-cn/)
- [Butterfly 主题](https://github.com/jerryc127/hexo-theme-butterfly)
- [GitHub Pages](https://pages.github.com/)

---

<p align="center">
  <i>如果觉得不错，欢迎 Star ⭐️</i>
</p>