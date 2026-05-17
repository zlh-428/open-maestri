# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## SwiftUI / AppKit 开发规范

本项目使用 **swiftui-expert-skill** 作为 Swift 开发指导，在每次涉及 SwiftUI/AppKit 代码的任务前应调用该 skill。

核心约束：
- 目标平台：macOS 14.0+，Swift 5.9，使用 `@Observable`（非 `ObservableObject`）
- 画布层使用原生 AppKit（`NSView`）；UI 层用 SwiftUI，通过 `NSViewRepresentable` 桥接
- 所有 `@State` 属性必须是 `private`；画布状态修改强制在 `@MainActor`
- 无 iOS 代码，`#available` 仅用于 macOS 版本分支

## 构建与测试命令

```bash
# 开发构建
swift build

# Release 构建
swift build -c release

# Xcode CI 构建（无需签名）
xcodebuild -scheme open-maestri -destination 'platform=macOS' build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

# 运行所有测试
swift test

# 运行单个测试
swift test --filter OpenMaestriTests.WorkspaceManagerTests/testCreateWorkspace
```

## 架构概览

### 数据流

```
AppState (@Observable)
  └─ WorkspaceManager（每工作区一个实例）
       └─ WorkspaceDocument（序列化根）
            ├─ [CanvasNode]       ← 节点列表（frame 以 [[x,y],[w,h]] 格式存储，兼容 Maestri）
            ├─ [TerminalConnection]
            ├─ CanvasState        ← origin + zoom（仅运行时，不持久化）
            └─ [NoteConnection / PortalConnection]
```

### 关键模块

| 模块 | 路径 | 说明 |
|------|------|------|
| 画布引擎 | `Sources/Canvas/` | `CanvasViewportView`（NSView）为核心，坐标原点约 `(9800, 8500)` |
| 节点模型 | `Sources/Workspace/Models/` | `CanvasNode` + `NodeContent` 枚举驱动所有节点类型 |
| 持久化 | `Sources/Workspace/PersistenceManager.swift` | 原子写入，单例，所有文件 I/O 必须经此类 |
| IPC 服务 | `Sources/InterAgent/InterAgentServer.swift` | 绑定 `127.0.0.1` 动态端口，HTTP `POST /cli`，处理所有 `omaestri` 命令 |
| CLI 路由 | `Sources/InterAgent/CLIRouter.swift` | 将 args 分发给各 Handler |
| 连接管理 | `Sources/Connection/ConnectionManager.swift` | `@MainActor` 单例，建立连接时自动调用 `SkillInjector` |
| 终端 | `Sources/Terminal/` | SwiftTerm PTY 封装，`SwiftTermProvider` 管理 PTY 生命周期 |
| 应用状态 | `Sources/App/AppState.swift` | 冷启动 < 1.5s，自动保存间隔 30s（后台线程，不阻塞 UI） |

### `NodeContent` 序列化格式（与 Maestri 兼容）

```json
{ "terminal": { "_0": { ... } } }
```
新增节点类型时必须遵循此 `{ "type": { "_0": ... } }` 包装结构。

### `CanvasNode.frame` 格式

画布坐标以 `[[x, y], [w, h]]` 二维数组存储（非标准 CGRect），通过 `CGRect+Frame.swift` 扩展互转。

## 数据存储路径

```
~/.open-maestri/
├── manifest.json                      # 工作区索引（schemaVersion: 1）
├── preferences.json
├── app-state.json                     # 含 cleanShutdown 标志（崩溃恢复用）
└── workspaces/{UUID}/
    ├── workspace.json                 # schemaVersion: 2，节点 + 连接
    ├── notes/{name}.md
    └── terminals/{UUID}.scrollback
```

数据格式与 **Maestri v0.25.4** 的 `workspace.json`（`schemaVersion: 2`）完全兼容。

## 产品参考文档

`docs/reference/` 目录包含对标 Maestri 产品的 UI/交互规范，实现新功能前必须查阅：

- `docs/reference/maestri-reference-index.md` — 主索引，含画布、节点、连接、Maestro 模式等所有模块的 UI 结构和快捷键规范

## 功能实现范围

以下功能已实现或规划中，**Ombro 伴侣**（需 Apple Foundation Models + macOS 26+）暂不实现：

| 功能 | 状态 |
|------|------|
| 工作区管理 + 无限画布 | 已实现 |
| Terminal 节点（PTY） | 已实现 |
| Note 节点（Markdown） | 已实现 |
| Connection + SkillInjector | 已实现 |
| File Tree + Git 操作 | 已实现（部分） |
| Portal（WKWebView 浏览器节点） | 已实现 |
| Floors（git worktree 隔离） | 部分实现 |
| Routines（定时任务） | 部分实现 |
| Remote SSH | 部分实现 |
| Ombro | **不实现** |

## `omaestri` CLI 协议

终端连接后自动注入 `omaestri` 脚本，通过 HTTP 与 `InterAgentServer` 通信：

- `POST /cli`，请求体：`{ "args": ["ask", "Name", "prompt"] }`
- Header：`X-Terminal-ID: <UUID>`（用于权限范围控制）
- 响应：纯文本（`text/plain`），CLI 直接打印输出

新增 CLI 命令需在 `CLIRouter.swift` 注册，并在 `Sources/InterAgent/Handlers/` 新建 Handler 文件。
