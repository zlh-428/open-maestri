<p align="center">
  <img src="docs/images/home.png" alt="open-maestri canvas" width="760">
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
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?style=flat-square" alt="Platform: macOS 14+">
  <a href="https://img.shields.io/badge/swift-5.9-orange?style=flat-square" alt="Swift 5.9"><img src="https://img.shields.io/badge/swift-5.9-orange?style=flat-square" alt="Swift"></a>
  <a href="https://github.com/zlh-428/open-maestri/actions"><img src="https://img.shields.io/github/actions/workflow/status/zlh-428/open-maestri/ci.yml?style=flat-square&label=CI" alt="CI"></a>
</p>

<p align="center">
  <a href="#installation">下载</a> &middot;
  <a href="#quick-start">快速开始</a> &middot;
  <a href="#omaestri-cli">CLI 参考</a> &middot;
  <a href="docs/roadmap.zh-CN.md">路线图</a> &middot;
  <a href="CONTRIBUTING.md">参与贡献</a>
</p>

<p align="center">
  <img src="docs/images/demo.gif" alt="Open-Maestri in action" width="720">
</p>

---

## open-maestri 是什么？

open-maestri 是专为 Agentic AI 时代打造的**画布式编排层**。它不是 AI Agent，而是围绕 Agent 的工作台与调度平台。

将终端、AI Agent、Markdown 笔记、文件浏览器、内嵌浏览器统一放置在无限空间画布上，通过物理绳索动画将它们相互连接，让 Agent 通过 `omaestri` CLI 直接通信，无需你充当人肉路由。

**核心痛点：** 同时运行多个 AI 编码 Agent（Claude Code、Codex CLI、Gemini CLI 等）时，开发者被迫在多个终端窗口间手动传递上下文。open-maestri 消除了这种摩擦。

## 为什么选择 open-maestri？

| | open-maestri | Maestri |
|---|---|---|
| 许可证 | **GPL v3**（永久免费、开源） | 专有软件（SetApp 订阅） |
| macOS 要求 | **14.0+（Sonoma）** | macOS 26.2+ |
| 源码开放 | 是 | 否 |
| 数据格式 | 完全兼容 | Maestri 私有格式 |
| CLI 兼容 | 是（`omaestri` = `maestri`） | 是 |
| Skill 生态 | 开放，可扩展 | 封闭 |

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

---

## Installation

### 下载安装包（推荐）

从 [GitHub Releases](https://github.com/zlh-428/open-maestri/releases) 下载最新签名 `.dmg`。

### Quick Start（从源码构建）

```bash
git clone https://github.com/zlh-428/open-maestri.git
cd open-maestri
open Package.swift   # 在 Xcode 中打开 — 点击 Run
```

### 使用 Swift Package Manager 构建

```bash
swift build -c release
```

### 使用 Xcode 构建（CI 兼容）

```bash
xcodebuild \
  -scheme open-maestri \
  -destination 'platform=macOS' \
  build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO
```

> **系统要求**：macOS 14.0+（Sonoma）、Xcode 16+、Swift 5.9+

## How It Works

```
Canvas (NSView infinite viewport)
  ├─ Terminal Node (SwiftTerm PTY) ← omaestri CLI injected
  ├─ Note Node (Markdown)
  ├─ File Tree Node
  ├─ Portal Node (WKWebView)
  └─ Connection (physics-based rope)
        ↕ IPC
InterAgentServer (127.0.0.1, HTTP POST /cli)
        ↕ omaestri CLI
Agents talk to each other directly — you stay in the flow
```

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

## 项目结构

```
open-maestri/
├── Sources/                    # Swift 源代码
│   ├── App/                    # 应用生命周期、窗口管理
│   ├── Canvas/                 # 无限画布渲染（NSView）
│   ├── Connection/             # 绳索物理与连接逻辑
│   ├── Terminal/               # PTY 终端节点（SwiftTerm）
│   ├── Note/                   # Markdown 笔记节点
│   ├── InterAgent/             # omaestri CLI HTTP 服务
│   ├── Workspace/              # 持久化与序列化
│   ├── Settings/               # 设置 UI
│   ├── Portal/                 # WKWebView 浏览器节点
│   ├── FileTree/               # 文件浏览器节点
│   ├── Floor/                  # git worktree 分支隔离
│   ├── Routine/                # 定时任务调度
│   ├── SSH/                    # 远程 SSH 隧道支持
│   ├── Maestro/                # Maestro 编排模式
│   ├── Roles/                  # Agent 角色系统
│   ├── Spotlight/              # macOS CoreSpotlight 集成
│   ├── Shared/                 # 共享工具与数据模型
│   └── OpenMaestriApp.swift    # 应用入口
├── Tests/                      # 单元测试与集成测试
├── Package.swift               # Swift Package Manager 配置
├── .github/workflows/          # GitHub Actions CI
└── LICENSE                     # GPL v3.0
```

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

---

## Star History

<a href="https://star-history.com/#zlh-428/open-maestri&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=zlh-428/open-maestri&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=zlh-428/open-maestri&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=zlh-428/open-maestri&type=Date" />
 </picture>
</a>

## Contributors

<a href="https://github.com/zlh-428/open-maestri/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=zlh-428/open-maestri" />
</a>

---

## 致谢

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — 终端模拟库
- [Sparkle](https://github.com/sparkle-project/Sparkle) — 自动更新框架
- [Maestri](https://maestriapp.com) — 启发本项目的原始产品

## 许可证

[GPL v3](LICENSE)
