# 本地开发指南

## 环境要求

| 工具 | 版本要求 |
|------|---------|
| macOS | 14.0（Sonoma）或更高 |
| Xcode | 16.0 或更高 |
| Swift | 5.9 或更高（随 Xcode 附带） |

确认版本：

```bash
swift --version
xcodebuild -version
```

---

## 获取源码

```bash
git clone https://github.com/your-org/open-maestri.git
cd open-maestri
```

首次克隆后，SPM 会自动解析并下载依赖（SwiftTerm、Sparkle），无需额外操作。

---

## 日常开发工作流

### 方式一：Xcode（推荐）

```bash
open Package.swift
```

Xcode 识别 `Package.swift` 后自动配置项目。

- `⌘R` — 构建并运行
- `⌘B` — 仅构建
- `⌘U` — 运行所有测试
- `⌘⇧K` — 清理构建产物

> **提示：** 首次打开时 Xcode 会解析依赖，需等待约 30 秒。进度显示在顶部状态栏。

### 方式二：命令行

```bash
# 构建（Debug）
swift build

# 构建并运行
swift run

# 构建（Release，更接近发布版本性能）
swift build -c release

# 运行编译好的二进制
.build/debug/open-maestri
```

---

## 项目结构速查

```
Sources/
├── App/              # 应用生命周期（AppDelegate、AppState、ContentView）
├── Canvas/           # 无限画布渲染（NSView，手势控制）
├── Connection/       # 绳索物理与连接逻辑
├── Terminal/         # PTY 终端节点（SwiftTerm 封装）
├── Note/             # Markdown 笔记节点
├── InterAgent/       # omaestri CLI 本地 HTTP 服务
├── Workspace/        # 持久化、序列化（workspace.json）
├── Settings/         # 设置面板 UI
├── Portal/           # WKWebView 内嵌浏览器节点
├── FileTree/         # 文件浏览器节点
├── Floor/            # git worktree 分支隔离
├── Routine/          # 定时任务调度
├── SSH/              # 远程 SSH 隧道
├── Maestro/          # Maestro 编排模式
├── Roles/            # Agent 角色系统
├── Spotlight/        # macOS CoreSpotlight 集成
└── Shared/           # 共享工具、数据模型
```

新功能一般对应一个模块目录。修改某个功能时，先找到对应目录，再从 `*State.swift` 或 `*View.swift` 入手。

---

## 运行测试

```bash
# 运行所有测试
swift test

# 运行指定测试目标
swift test --filter OpenMaestriTests.CanvasTests

# 运行指定测试方法
swift test --filter OpenMaestriTests.CanvasTests/testNodePlacement
```

测试文件位于 `Tests/OpenMaestriTests/`，按模块分目录组织，与 `Sources/` 结构对应。

---

## 依赖管理

项目使用 Swift Package Manager，依赖定义在 `Package.swift`：

| 依赖 | 用途 |
|------|------|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | VT100/xterm-256color PTY 终端渲染 |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | 应用内自动更新 |

更新依赖到最新兼容版本：

```bash
swift package update
```

查看当前解析版本：

```bash
cat Package.resolved
```

---

## 代码风格

- Swift 6 严格并发模型（`Sendable`、`@MainActor`）
- SwiftUI 作为 UI 主体，画布渲染使用 `AppKit NSView`
- 数据流：单向，`AppState` 作为全局状态容器，通过 `.environment()` 向下传递
- 文件规模：单文件不超过 400 行；超出时拆分

提交前运行一次构建和测试，确保无编译错误：

```bash
swift build && swift test
```

---

## 常见问题

**Q: 构建报错 `missing package product`**

依赖未完整下载，执行：

```bash
swift package resolve
```

**Q: Xcode 报 `No such module 'SwiftTerm'`**

在 Xcode 中选择 `File → Packages → Resolve Package Versions`。

**Q: 运行时提示权限错误（PTY / 文件访问）**

开发期间直接用 `swift run` 运行，不走沙盒。Xcode 中需确认 Scheme 的 `Signing & Capabilities` 未启用 App Sandbox。

**Q: 改了 `Package.swift` 后 Xcode 没有同步**

关闭 Xcode，重新执行 `open Package.swift`。

---

## 提交规范

```
<type>: <简短描述>

<可选正文>
```

类型：`feat` / `fix` / `refactor` / `docs` / `test` / `chore` / `perf`

示例：

```
feat: add omaestri portal snapshot command
fix: canvas viewport not restoring scroll position on launch
refactor: extract rope physics into standalone CatenaryCalculator
```

---

## CI

Push 到 `main` 或 `develop` 分支，或向 `main` 提 PR 时，GitHub Actions 自动执行构建和测试。

本地模拟 CI 行为：

```bash
xcodebuild \
  -scheme open-maestri \
  -destination 'platform=macOS' \
  test \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO
```
