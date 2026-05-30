# 为 open-maestri 贡献代码

<strong>中文</strong> | <a href="CONTRIBUTING.md">English</a>

---

## 写给人类的部分

*本节内容面向人类贡献者。*

open-maestri 是一款以 AI 为核心的画布应用，核心理念是：AI Agent 应当是一等协作者，而不只是工具。我们相信，最好的贡献方式，就是按照它本来的用途来使用它——让 Agent 陪在你身边。无论是修 Bug、提需求还是重构代码，让 Agent 来做繁重的工作不是取巧，这正是它的意义所在。

你不需要会 Swift 才能贡献。你只需要清晰描述出哪里出了问题、你想要什么，然后让 Agent 把它变成一个 Pull Request。

### 快速上手

克隆仓库后，将以下 Prompt 粘贴给你的代码 Agent（Claude Code、Cursor、Copilot 等），让它快速了解项目上下文：

```
我正在为 open-maestri 贡献代码，这是一个面向 macOS 的 AI 原生无限画布应用。
请先读取 CLAUDE.md，了解完整的架构概览、编码规范和构建命令，
然后读取 CONTRIBUTING.md 了解贡献流程。
读完后告诉我你准备好了，以及你有哪些问题。
```

Agent 会读取 `CLAUDE.md`，理解项目结构，引导你完成修改。

---

### 通过 Agent 报告 Bug

发现问题了？把下面的 Prompt 粘贴给 Agent，填写你的情况，让它帮你起草 Issue。

<details>
<summary>Bug 报告 Agent Prompt</summary>

```
我想为 open-maestri 提交一个 Bug 报告，请帮我写一份清晰、完整的报告。

我遇到的问题：
[描述你看到的现象]

我预期应该发生的事情：
[描述期望行为]

复现步骤：
[尽可能精确地列出步骤]

在我们写报告之前，请先问我以下几个诊断问题，以便在报告中包含正确的环境信息：

1. 你运行的 macOS 版本是什么？
   （系统设置 → 通用 → 关于本机 → macOS 版本）

2. 你安装的 Xcode 版本是什么？
   （Xcode → 关于 Xcode）

3. 在终端运行 `swift --version`，粘贴输出结果。

4. Bug 发生时 open-maestri 处于什么状态？
   （正常运行中 / 启动过程中 / 关闭过程中）

5. 有没有崩溃日志？
   （打开"控制台"App → 崩溃报告，按"open-maestri"过滤）

6. 这个问题是最近更新后出现的，还是一直存在？

等我回答完这些问题后，请将所有内容格式化为一个 GitHub Issue，包含：
- 简短、描述性的标题
- 环境信息（macOS、Xcode、Swift 版本）
- 复现步骤
- 预期行为
- 实际行为
- 相关日志或截图占位符

最后展示格式化好的 Issue 文本，方便我复制到 GitHub。
```

</details>

---

### 通过 Agent 请求新功能

有想法？粘贴这个 Prompt，让 Agent 帮你把想法整理成一份合格的功能请求。

<details>
<summary>功能请求 Agent Prompt</summary>

```
我想为 open-maestri 请求一个新功能，请帮我写一份清晰、范围明确的功能请求。

我的想法：
[描述你想要的功能]

在写请求之前，请先问我：

1. 这个功能解决了什么问题，或者改善了哪个工作流？
2. 用户会如何触发这个功能？（快捷键、菜单项、画布手势、omaestri CLI 命令？）
3. 这个功能需要跨 Agent 会话保持状态，还是只在当前会话内有效？
4. 现有代码库中有没有类似功能可以参考？
   （你可以查阅 CLAUDE.md 和 Sources/ 目录寻找线索。）
5. 这是纯新增功能，还是会改变现有行为？

我回答后，请：
- 读取 CLAUDE.md，检查这个功能是否与现有约束冲突
  （特别注意"不实现 Ombro"的说明和目标平台限制）
- 起草一份 GitHub 功能请求 Issue，包含：标题、动机、建议的交互方式、
  范围说明、以及待解决的开放问题
- 标注出任何看起来超出范围或技术风险较高的部分
```

</details>

---

## 写给 Agent 的部分

*本节内容面向 AI Agent。*

### 项目简介

open-maestri 是一款 macOS 应用，提供无限画布，AI Agent 终端、浏览器 Portal、Markdown 笔记和文件树作为可拖拽节点共存其中。节点之间通过 `omaestri` CLI 通信——这是一个内嵌在 App 中的本地 HTTP 服务，允许终端之间以及终端与画布之间相互发送消息。数据格式与 Maestri v0.25.4 兼容。

画布引擎使用 AppKit（`NSView`）。画布以外的所有 UI 使用 SwiftUI，通过 `NSViewRepresentable` 桥接。状态管理使用 `@Observable`（Swift 5.9+，非 `ObservableObject`）。项目中没有 iOS 代码。

### 环境要求

| 工具 | 最低版本 |
|------|---------|
| macOS | 14.0（Sonoma） |
| Xcode | 16.0 |
| Swift | 5.9（随 Xcode 附带） |

验证环境：

```bash
swift --version
xcodebuild -version
```

克隆后 SPM 会自动解析依赖（SwiftTerm、Sparkle）：

```bash
git clone https://github.com/zlh-428/open-maestri.git
cd open-maestri
```

### 构建与测试

```bash
# 开发构建
swift build

# 在 Xcode 中打开（UI 开发推荐）
open Package.swift

# 运行所有测试
swift test

# 运行指定测试
swift test --filter OpenMaestriTests.WorkspaceManagerTests/testCreateWorkspace

# 等效 CI 构建（无需代码签名）
xcodebuild -scheme open-maestri \
  -destination 'platform=macOS' \
  test \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO
```

Commit 规范：`<type>: <简短描述>` — 类型为 `feat`、`fix`、`refactor`、`docs`、`test`、`chore`、`perf`。

### 下一步参考资料

| 文档 | 内容 |
|------|------|
| `CLAUDE.md` | 架构概览、编码约束、数据格式、IPC 协议 |
| `docs/reference/maestri-reference-index.md` | 画布 UI 规范、节点类型、快捷键 |
| `Sources/InterAgent/` | `omaestri` CLI 服务与命令路由——新增 CLI 命令从这里开始 |
| `Sources/Canvas/` | 画布视口、节点渲染、拖拽与缩放 |
| `Sources/Workspace/` | 持久化、序列化、`workspace.json` 格式 |
