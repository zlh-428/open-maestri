# 路线图

<strong>中文</strong> | <a href="roadmap.md">English</a>

open-maestri 是一个社区驱动的项目。核心团队负责维护画布引擎和 Agent 通信协议，但最有意思的工作发生在边缘地带——更丰富的节点类型、更完整的 CLI 命令、更深入的 Git 集成，以及长期的跨平台支持。如果下面某个方向对你重要，欢迎提 Issue 或直接发 PR。

## 重点方向

| # | 方向 | 描述 | 状态 | 链接 |
|---|------|------|------|------|
| 1 | **画布引擎** | 无限画布渲染、平移/缩放、小地图、节点拖拽与缩放 | Active（进行中） | — |
| 2 | **终端节点（PTY）** | 基于 SwiftTerm 的完整 VT100/xterm-256color 交互终端、Agent 预设、滚动历史持久化 | Active（进行中） | — |
| 3 | **Note 节点** | Markdown 编辑 + 实时预览双视图、图片粘贴、Note 链、从 Finder 拖入导入 | Active（进行中） | — |
| 4 | **Agent 间通信** | 连接时自动注入 `omaestri` CLI —— `ask`、`check`、`note read/write` | Active（进行中） | — |
| 5 | **Portal（内嵌浏览器）** | WKWebView 画布节点，支持 Agent 驱动的浏览器自动化：`navigate`、`snapshot`、`click`、`fill` | Active（进行中） | — |
| 6 | **Connection & SkillInjector** | 物理绳索连接动画、终端连接时自动注入技能脚本 | Active（进行中） | — |
| 7 | **文件树与 Git 操作** | 文件浏览器节点，含目录树；git status、diff 和暂存区操作——部分已实现 | In Progress（开发中） | — |
| 8 | **Maestro 编排模式** | 一个 Agent 担任 Team Lead：`recruit`、`connect`、`dismiss`——核心命令已通，需要更完整的生命周期管理 | In Progress（开发中） | — |
| 9 | **Floors（Git Worktree 隔离）** | 每个 Floor 映射一个 git worktree 分支，让多个 Agent 在同一画布上拥有隔离的工作副本 | Planned（计划中） | — |
| 10 | **Routines（定时任务）** | 定义由时间或画布事件触发的周期性自动化任务 | Planned（计划中） | — |
| 11 | **Remote SSH** | SSH 隧道支持，让 Agent 节点可以连接远程机器 | Planned（计划中） | — |
| 12 | **omaestri CLI 完整性** | 审计并填补 `omaestri` 与 Maestri 完整 CLI 之间的差距 | Open（社区驱动） | — |
| 13 | **Agent 角色系统** | 为 Maestro 生成的 Agent 提供更丰富的角色定义和能力范围控制 | Open（社区驱动） | — |
| 14 | **macOS Spotlight 集成** | 通过 CoreSpotlight 索引工作区内容，实现快速搜索 | Open（社区驱动） | — |
| 15 | **架构与代码质量** | 降低画布、终端和持久化层之间的耦合；提高测试覆盖率 | Open（社区驱动） | — |
| 16 | **Linux / Windows 移植** | 长期目标：将画布带到非 Apple 平台 | Open（社区驱动） | — |

**状态说明**：`Active` = 核心团队重点投入 · `In Progress` = 已开始开发 · `Planned` = 已纳入计划，尚未开始 · `Open` = 社区驱动，建议先开 Issue

---

## 不在路线图中的内容

**Ombro**（Maestri 中依赖 Apple Foundation Models 和 macOS 26+ 的本地 AI 伴侣功能）明确不在本项目的实现范围内。open-maestri 以 macOS 14.0+（Sonoma）为基准，不会依赖该版本上不可用的 API。

---

## 如何参与贡献

标记为 `Open` 的方向是新贡献者最好的切入点。在开始较大规模的开发之前：

1. 检查 [现有 Issues](https://github.com/your-org/open-maestri/issues)，避免重复工作。
2. 开一个 Issue，描述你打算构建什么以及原因。
3. 核心团队会给出反馈或放行确认。

对于小的修复和改进，附有清晰描述的 PR 随时欢迎，无需事先开 Issue。

详见 [CONTRIBUTING.md](../CONTRIBUTING.md) 了解开发环境配置、编码规范和 PR 流程。
