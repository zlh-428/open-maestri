<p align="center">
  <img src="Sources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" alt="open-maestri canvas" width="50">
</p>

<h1 align="center">open-maestri</h1>

<p align="center">
  <strong>面向 macOS 的开源多智能体编排画布</strong>
  <br>
  像管理团队一样管理 AI Agent，而不是一堆终端窗口。
  <br><br>
  <a href="README-zh.md"><strong>中文</strong></a> | <a href="README.md">English</a>
</p>

<p align="center">
  <a href="https://github.com/zlh-428/open-maestri/releases/latest"><img src="https://img.shields.io/github/v/release/zlh-428/open-maestri?style=flat-square&label=release&color=blue" alt="Latest Release"></a>
  <a href="https://github.com/zlh-428/open-maestri/stargazers"><img src="https://img.shields.io/github/stars/zlh-428/open-maestri?style=flat-square&color=yellow" alt="Stars"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL%20v3-green?style=flat-square" alt="License: GPL v3"></a>
  <a href="https://github.com/zlh-428/open-maestri/actions"><img src="https://img.shields.io/github/actions/workflow/status/zlh-428/open-maestri/ci.yml?style=flat-square&label=CI" alt="CI"></a>
</p>

<p align="center">
  <a href="https://github.com/zlh-428/open-maestri/releases">下载</a> &middot;
  <a href="#quick-start">快速开始</a> &middot;
  <a href="#how-it-works">工作原理</a> &middot;
  <a href="#omaestri-cli">CLI 参考</a> &middot;
  <a href="docs/roadmap.zh-CN.md">路线图</a> &middot;
  <a href="CONTRIBUTING.md">参与贡献</a>
</p>

<p align="center">
  <img src="docs/images/demo.gif" alt="open-maestri in action" width="720">
</p>

---

## open-maestri 是什么？

open-maestri 是专为 Agentic AI 时代打造的**画布式编排层**。它不是 AI Agent，而是围绕 Agent 的工作台与调度平台。

将终端、AI Agent、Markdown 笔记、文件浏览器、内嵌浏览器统一放置在无限空间画布上，通过物理绳索动画将它们相互连接，让 Agent 通过 `omaestri` CLI 直接通信，无需你充当人肉路由。

> *同时运行多个 AI 编码 Agent（Claude Code、Codex CLI、Gemini CLI 等）时，开发者被迫在多个终端窗口间手动传递上下文。open-maestri 消除了这种摩擦。*

## 为什么选择 open-maestri？

| | open-maestri | Maestri |
|---|---|---|
| 许可证 | **GPL v3**（永久免费、开源） | 专有软件（SetApp 订阅） |
| macOS 要求 | **14.0+（Sonoma）** | macOS 26.2+ |
| 源码开放 | 是 | 否 |
| 数据格式 | 完全兼容 | Maestri 私有格式 |
| CLI 兼容 | 是（`omaestri` = `maestri`） | 是 |
| Skill 生态 | 开放，可扩展 | 封闭 |

## 快速开始

### 方式一：下载安装包

从 [GitHub Releases](https://github.com/zlh-428/open-maestri/releases) 下载最新 `.dmg`。

> **macOS Gatekeeper 提示** — 由于构建未经 Apple 公证，首次启动时 macOS 可能弹出安全警告。可通过以下任一方式绕过：
>
> **方法 A** — 右键点击应用 → **打开** → **打开**（仅首次需要）
>
> **方法 B** — 安装后在终端执行：
> ```bash
> xattr -dr com.apple.quarantine /Applications/open-maestri.app
> ```

### 方式二：从源码构建

```bash
git clone https://github.com/zlh-428/open-maestri.git
cd open-maestri
open Package.swift   # 在 Xcode 中打开 — 点击 Run
```

### 方式三：使用 Swift Package Manager 构建

```bash
swift build -c release
```

首次启动后，open-maestri 会创建一个空工作区。在画布上添加 Terminal、Note、File Tree 或 Portal 节点即可开始使用。

> **系统要求**：macOS 14.0+（Sonoma）、Xcode 16+、Swift 5.9+

## 工作原理

```
Canvas (NSView infinite viewport)
  ├─ Terminal Node (SwiftTerm PTY) ← omaestri CLI 自动注入
  ├─ Note Node (Markdown)
  ├─ File Tree Node
  ├─ Portal Node (WKWebView)
  └─ Connection (physics-based rope)
        ↕ IPC (HTTP POST /cli)
InterAgentServer (仅 127.0.0.1，无外部访问)
        ↕ omaestri CLI
Agent 之间直接通信 — 你保持专注
```

所有通信均在本地完成。终端连接时 `omaestri` CLI 会自动注入。

<details>
<summary>架构详情</summary>

三个 Swift Package target：

| Target | 职责 |
|---|---|
| **open-maestri** | 主应用 — SwiftUI + AppKit UI、画布引擎（NSView）、持久化、IPC 服务 |
| **omaestri** | 轻量 CLI，在终端节点内被 Agent 调用，通过 HTTP 转发命令 |
| **OpenMaestriTests** | 单元测试与集成测试 |

数据流：

```
AppState (@Observable, 全局)
  └─ [WorkspaceManager] (每工作区一个实例, @Observable)
       └─ WorkspaceDocument (序列化根)
            ├─ [CanvasNode]       ← 节点列表（frame 以 [[x,y],[w,h]] 格式存储，兼容 Maestri）
            ├─ [TerminalConnection]
            ├─ CanvasState        ← origin + zoom（仅运行时，不持久化）
            └─ [NoteConnection / PortalConnection]
```

</details>

## 核心功能

<details>
<summary><strong>无限画布</strong></summary>

- 拖拽 Terminal、Note、File Tree、Portal、Text 节点到无限画布
- 触控板手势或鼠标滚轮平移与缩放
- 物理绳索连线动画（悬链线算法，21 个控制点）
- 小地图快速定位与跳转

</details>

<details>
<summary><strong>终端与 Agent 节点</strong></summary>

- 基于 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 的完整 VT100/xterm-256color 交互式 PTY
- 内置 Agent 预设：Claude Code、Codex CLI、Gemini CLI、OpenCode、Shell
- Agent 运行/空闲状态指示器
- Scrollback 历史跨重启持久化

<img src="docs/images/create-terminal.png" alt="Create terminal node" width="760">

</details>

<details>
<summary><strong>Agent 间通信</strong></summary>

终端连接时自动注入 `omaestri` CLI，Agent 之间直接通信：

```bash
omaestri list                             # 列出已连接的 agents/notes/portals
omaestri ask "Reviewer" "帮我审查这个PR"   # 发送消息并等待响应
omaestri check "Builder"                  # 读取目标 Agent 当前终端输出
omaestri note read "Spec"                 # 读取连接的 Note
omaestri note write "Spec" "内容"         # 向 Note 写入内容
```

<img src="docs/images/agents.png" alt="Agent communication" width="760">

</details>

<details>
<summary><strong>Maestro 编排模式</strong></summary>

一个 Agent 作为团队 Lead，通过指令招募、连接、解散其他 Agent：

```bash
omaestri recruit "Builder" --preset claude-code --role coder
omaestri connect "Builder" "Spec"
omaestri dismiss "Builder"
```

</details>

<details>
<summary><strong>Note 节点</strong></summary>

- Raw（纯文本 Markdown 编辑）和 Formatted（实时渲染预览）双视图切换
- 直接粘贴图片到 Note
- Note Chain：Note 连接 Note，Agent 可遍历整个链路
- 从 Finder 拖入 `.md` / `.txt` 文件即可创建 Note

</details>

<details>
<summary><strong>Portal（内嵌浏览器）</strong></summary>

- 画布中的 WKWebView 节点
- Agent 通过 `omaestri portal` 命令集控制浏览器：

```bash
omaestri portal navigate "Browser" "http://localhost:3000"
omaestri portal snapshot "Browser"   # 获取可访问性树
omaestri portal click "Browser" @e3
omaestri portal fill "Browser" @e1 "admin"
```

</details>

<details>
<summary><strong>工作区持久化</strong></summary>

- 应用重启后画布布局（节点位置、大小、连接）完全恢复
- 每 30 秒自动保存（后台线程，不阻塞 UI）
- 通过 `cleanShutdown` 标记实现崩溃恢复
- 完全兼容 **Maestri v0.25.4** 的 `workspace.json` 格式

</details>

## 截图

| | |
|:---:|:---:|
| <img src="docs/images/home.png" alt="Canvas overview" width="360"> | <img src="docs/images/agents.png" alt="Agent nodes" width="360"> |
| <img src="docs/images/create-terminal.png" alt="Create terminal" width="360"> | <img src="docs/images/file.png" alt="File tree node" width="360"> |

## omaestri CLI

`omaestri` 脚本在终端连接时自动注入，通过本地 HTTP 服务（仅 `127.0.0.1`）与应用通信。

| 命令 | 说明 |
|------|------|
| `omaestri list` | 列出已连接的 agents/notes/portals |
| `omaestri ask "Name" "prompt"` | 向 Agent 发送消息并等待响应 |
| `omaestri check "Name"` | 读取目标 Agent 当前终端输出 |
| `omaestri note create "Name"` | 创建新 Note |
| `omaestri note read "Name" [--offset N] [--limit N]` | 读取 Note 内容 |
| `omaestri note write "Name" "content"` | 向 Note 写入内容 |
| `omaestri recruit "Name" [--preset P] [--role R]` | 在画布招募新 Agent（仅 Maestro） |
| `omaestri dismiss "Name"` | 关闭并移除 Agent（仅 Maestro） |
| `omaestri connect "From" "To"` | 连接两个节点（仅 Maestro） |
| `omaestri portal navigate "Name" "url"` | 控制 Portal 导航到指定 URL |
| `omaestri portal snapshot "Name"` | 获取页面可访问性树 |
| `omaestri portal click "Name" @ref` | 点击指定元素 |
| `omaestri portal fill "Name" @ref "value"` | 填写输入框 |

## 兼容性说明

open-maestri 与 Maestri v0.25.4 保持完整兼容：

- **workspace.json**（`schemaVersion: 2`）：可双向读写
- **omaestri CLI**：命令接口与 `maestri` CLI 完全一致
- **Agent Skill 脚本**：现有 Maestri Skill 脚本无需修改即可使用

## 参与贡献

欢迎贡献代码。提交 PR 前请阅读贡献指南（[CONTRIBUTING.md](CONTRIBUTING.md)）。

```bash
swift test
```

**当前重点征集贡献的领域：**

- Portal 浏览器自动化命令
- File Tree git 操作
- Floors（git worktree 集成）
- Routines（定时任务调度器）
- 远程 SSH 支持
- Linux / Windows 移植（长期目标）

## 通过 Code Agent 提交 Bug

将以下提示词复制到你的 Agent（Claude Code、Codex 等）中，自动生成结构化的 GitHub Issue：

<details>
<summary>点击展开</summary>

```
我遇到了 open-maestri (https://github.com/zlh-428/open-maestri) 的问题。

请帮我提交一个 GitHub Issue。执行以下步骤：

1. 收集我的环境信息：
   - 运行 `sw_vers` 获取 macOS 版本
   - 运行 `swift --version` 获取 Swift 版本
   - 运行 `open-maestri --version` 获取应用版本（如可用）
   - 检查 open-maestri 是否在运行：`ps aux | grep -i "open-maestri\|OpenMaestriApp" | grep -v grep`

2. 让我描述：
   - 期望发生什么
   - 实际发生了什么
   - 复现步骤

3. 使用 `gh issue create` 在 GitHub 上创建 Issue，格式如下：
   - 标题：简明扼要的摘要
   - 正文包含以下分区：**环境信息**、**问题描述**、**复现步骤**、**期望行为 vs 实际行为**
   - 如适用，添加 "bug" 标签

仓库：zlh-428/open-maestri
```

</details>

---

## Star History

<a href="https://www.star-history.com/?type=date&repos=zlh-428%2Fopen-maestri">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=zlh-428/open-maestri&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=zlh-428/open-maestri&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=zlh-428/open-maestri&type=date&legend=top-left" />
 </picture>
</a>

## 致谢

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — 终端模拟库
- [Sparkle](https://github.com/sparkle-project/Sparkle) — 自动更新框架
- [Maestri](https://maestriapp.com) — 启发本项目的原始产品

---

## Agent 读取区

本章节面向代码 Agent 编写。

面向 macOS 的开源多智能体编排画布。

`open-maestri` 提供一个无限空间画布，AI 编码 Agent、终端、笔记、文件浏览器和内嵌浏览器作为可连接节点共存。Agent 通过 `omaestri` CLI 直接通信，无需人工路由。

### 产品定位

同时运行多个 AI 编码 Agent 时，开发者需要在终端窗口间来回切换、手动复制上下文。`open-maestri` 提供统一的可视化工作区来消除这种摩擦：

- **画布式** — 空间布局而非标签页，一目了然
- **Agent 间 IPC** — Agent 通过 `omaestri ask`/`check` 命令互发消息，可实时读取其他 Agent 的终端输出
- **Maestro 模式** — 指定的 Lead Agent 可编程式招募、连接、解散其他 Agent
- **Maestri 兼容** — 可读写 Maestri v0.25.4 的 `workspace.json` 文件，现有 `maestri` CLI 命令作为 `omaestri` 可用

### 适用人群

在 macOS 上同时运行多个 AI 编码 Agent（Claude Code、Codex CLI、Gemini CLI、OpenCode 等）的开发者，希望通过可视化工作区进行编排。

### 节点类型

- **Terminal** — 基于 SwiftTerm 的完整 PTY 终端。支持 Agent 预设（Claude Code、Codex CLI、Gemini CLI、OpenCode、Shell）。连接时自动注入 `omaestri` CLI。
- **Note** — Markdown 编辑器，支持 Raw/Formatted 双视图。支持图片和 Note Chain（Note 到 Note 的连接，Agent 可遍历整个链路）。
- **File Tree** — 本地目录文件浏览器。
- **Portal** — 内嵌 WKWebView 浏览器。Agent 可通过 `omaestri portal navigate/snapshot/click/fill` 自动化操控。

### Agent 间通信

```bash
omaestri list                          # 列出所有已连接节点
omaestri ask "Name" "prompt"           # 发送 prompt，等待响应
omaestri check "Name"                  # 读取目标 Agent 的终端输出
omaestri note read "Name"              # 读取 Note
omaestri note write "Name" "content"   # 写入 Note
```

### Maestro 模式

一个 Agent 作为编排者：

```bash
omaestri recruit "Builder" --preset claude-code --role coder
omaestri connect "Builder" "Spec"
omaestri dismiss "Builder"
```

### 架构

三个 Swift Package target：

| Target | 职责 |
|---|---|
| **open-maestri** | SwiftUI + AppKit 主应用 — 无限画布（NSView）、持久化、IPC HTTP 服务 |
| **omaestri** | CLI 二进制，在终端节点内被 Agent 调用，通过 HTTP POST /cli 转发命令 |
| **OpenMaestriTests** | 单元测试与集成测试 |

数据流：`AppState` → `WorkspaceManager` → `WorkspaceDocument` → `[CanvasNode]` + `[Connection]`。画布使用 NSView，5 层子视图渲染。持久化使用原子文件写入（`FileManager.replaceItem`）。

### 快速开始（Agent）

本地构建运行：

```bash
open Package.swift
```

构建 Release 二进制：

```bash
swift build -c release
```

运行测试：

```bash
swift test
```

### 仓库地图

- 从 [CLAUDE.md](CLAUDE.md) 开始阅读完整开发指南（架构、并发模型、画布性能约束、序列化格式、CLI 协议）。
- 阅读 [docs/reference/maestri-reference-index.md](docs/reference/maestri-reference-index.md) 了解 Maestri 产品 UI/交互参考。
- 阅读 [docs/roadmap.md](docs/roadmap.md) 了解功能路线图。

### 系统要求

- macOS 14.0+
- Swift 5.9+
- Xcode 16+（用于构建应用 target）

---

## 许可证

[GPL v3](LICENSE)
