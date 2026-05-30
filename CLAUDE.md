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

# 打包 .app（ad-hoc 签名）
bash scripts/build-maestri.sh
```

Package.swift 包含 3 个 target：`open-maestri`（主应用）、`omaestri`（CLI 工具）、`OpenMaestriTests`（测试）。

## 架构概览

### 数据流

```
AppState (@Observable, 全局)
  └─ [WorkspaceManager]（每工作区一个实例，@Observable）
       └─ WorkspaceDocument（序列化根）
            ├─ [CanvasNode]       ← 节点列表（frame 以 [[x,y],[w,h]] 格式存储，兼容 Maestri）
            ├─ [TerminalConnection]
            ├─ CanvasState        ← origin + zoom（仅运行时，不持久化）
            └─ [NoteConnection / PortalConnection]
```

### 关键模块

| 模块 | 路径 | 说明 |
|------|------|------|
| 画布引擎 | `Sources/Canvas/` | `CanvasViewportView`（NSView）为核心，坐标原点约 `(9800, 8500)`，5 层子视图叠加渲染 |
| 节点模型 | `Sources/Workspace/Models/` | `CanvasNode` + `NodeContent` 枚举驱动所有节点类型 |
| 持久化 | `Sources/Workspace/PersistenceManager.swift` | 单例，原子写入，所有文件 I/O 必须经此类 |
| IPC 服务 | `Sources/InterAgent/InterAgentServer.swift` | 双通道：TCP `127.0.0.1:动态端口` + Unix Socket，HTTP `POST /cli` |
| CLI 路由 | `Sources/InterAgent/CLIRouter.swift` | 将 args 分发给各 Handler（`Sources/InterAgent/Handlers/`） |
| 连接管理 | `Sources/Connection/ConnectionManager.swift` | `@MainActor` 单例，建立连接时自动调用 `SkillInjector` |
| 终端 | `Sources/Terminal/` | SwiftTerm PTY 封装，`SwiftTermProvider` 管理 PTY 生命周期 |
| 应用状态 | `Sources/App/AppState.swift` | 冷启动 < 1.5s，自动保存 30s（后台线程），崩溃恢复 |

### 启动时序（关键）

`AppDelegate.applicationDidFinishLaunching` 中的执行顺序不可变：

1. **InterAgentServer 启动** — 必须在 UI 加载前完成，确保端口可用
2. **Skill 安装** — 注入到 `~/.claude/skills/`（幂等，每次启动执行）
3. **AppState 初始化** — 加载 manifest、恢复崩溃标记
4. **UI 渲染** — SwiftUI Scene 生命周期

## 并发模型（重要）

项目严格使用 `@Observable`（Swift 5.9+），禁止使用 `ObservableObject`。

### 后台 I/O 的快照模式

读写 `@Observable` 状态时，必须先在 MainActor 上创建不可变快照，再在后台线程执行 I/O：

```swift
// 正确：先快照，后 I/O
let snapshot = await MainActor.run { workspace.snapshotPayload() }
try await save(snapshot)

// 错误：直接访问 @Observable 属性导致数据竞争
try await save(workspace.buildPayload())
```

Autosave 遵循此模式：先快照所有脏工作区（`isDirty` 过滤），后台线程纯 I/O，完成后重置脏标记。

### 脏标记追踪

只有 `isDirty = true` 的工作区才会在 30s 自动保存周期中被持久化，最小化 I/O。节点/连接的任何修改都会设置脏标记。

## 画布性能约束

`CanvasViewportView` 是高频渲染热点，以下优化不可回退：

- **视口裁剪**：仅渲染视口内 + 200px 边距的节点，消除进入视口时的闪烁
- **Z-Index 双缓存**：升序（渲染）和降序（命中测试）预排序列表，避免每帧 O(n log n) 排序
- **命中测试缓存**：2px 阈值的空间缓存，避免 60fps 冗余计算
- **拖拽就地更新**：拖拽/缩放期间直接更新坐标，跳过完整排序
- **Root View 节流**：Pan/Zoom 期间 SwiftUI 树更新限制在 60fps，避免终端刷新风暴

### 交互状态机

```swift
enum CanvasInteraction {
    case idle
    case draggingNode(UUID, CGPoint, CGRect)
    case batchDragging([UUID: CGRect], CGPoint, CGRect)
    case resizingNode(UUID, CGRect, ResizeEdge, CGRect)
    case mayDragNode(UUID, CGPoint, CGRect, Date)
    case panningViewport(CGPoint)
    case marqueeSelection(CGPoint, Set<UUID>)
    case drawingNode(String, CGPoint, CGRect?)
}
```

## Maestri 兼容性格式（不可变）

### `NodeContent` 序列化

```json
{ "terminal": { "_0": { ... } } }
```

新增节点类型时**必须**遵循此 `{ "type": { "_0": ... } }` 包装结构，否则 Maestri 无法读取。

### `CanvasNode.frame` 格式

画布坐标以 `[[x, y], [w, h]]` 二维数组存储（非标准 CGRect），通过 `CGRect+Frame.swift` 扩展互转。

## 数据存储路径

```
~/.open-maestri/
├── manifest.json                      # 工作区索引（schemaVersion: 1）
├── preferences.json
├── app-state.json                     # 含 cleanShutdown 标志（崩溃恢复用）
├── run/agent.sock                     # Unix Socket（固定路径，非工作区相关）
└── workspaces/{UUID}/
    ├── workspace.json                 # schemaVersion: 2，节点 + 连接
    ├── notes/{name}.md
    └── terminals/{UUID}.scrollback
```

### 崩溃恢复机制

- 运行时 `app-state.json` 中 `cleanShutdown` 设为 `false`
- 正常退出时设为 `true`
- 启动时检测：若为 `false` 则触发恢复 UI

### 原子写入策略

`PersistenceManager` 使用 `FileManager.replaceItem` 实现崩溃安全的原子替换：先写 `.tmp` 文件，再原子交换。

## `omaestri` CLI 协议

终端连接后自动注入 `omaestri` 脚本（`SwiftTermProvider` 通过 `MAESTRI_SERVER_PORT` 环境变量传递端口）：

- `POST /cli`，请求体：`{ "args": ["ask", "Name", "prompt"] }`
- Header：`X-Terminal-ID: <UUID>`（用于权限范围控制，跨工作区持久）
- 响应：纯文本（`text/plain`），CLI 直接打印输出

新增 CLI 命令需在 `CLIRouter.swift` 注册，并在 `Sources/InterAgent/Handlers/` 新建 Handler 文件。

## 产品参考文档

`docs/reference/` 目录包含对标 Maestri 产品的 UI/交互规范，实现新功能前必须查阅：

- `docs/reference/maestri-reference-index.md` — 主索引，含画布、节点、连接、Maestro 模式等所有模块的 UI 结构和快捷键规范

## 功能实现范围

**Ombro 伴侣**（需 Apple Foundation Models + macOS 26+）明确不在实现范围内。

已实现：工作区管理 + 无限画布、Terminal/Note/Portal 节点、Connection + SkillInjector、File Tree + Git（部分）
部分实现：Floors（git worktree）、Routines（定时任务）、Remote SSH
