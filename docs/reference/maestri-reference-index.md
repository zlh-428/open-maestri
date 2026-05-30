# Maestri 产品参考索引

> 本文档为 open-maestri 开发参照物，综合官方文档与产品截图，按功能模块整理 UI 描述、交互行为与实现要点。

---

## 目录

1. [整体布局（主界面）](#1-整体布局主界面)
2. [工作区（Workspace）](#2-工作区workspace)
3. [画布（Canvas）](#3-画布canvas)
4. [终端节点（Terminal）](#4-终端节点terminal)
5. [笔记节点（Note）](#5-笔记节点note)
6. [连接（Connection）](#6-连接connection)
7. [文件树节点（File Tree）](#7-文件树节点file-tree)
8. [Maestro 模式](#8-maestro-模式)
9. [楼层（Floors）](#9-楼层floors)
10. [门户节点（Portal）](#10-门户节点portal)
11. [例程（Routines）](#11-例程routines)
12. [远程 SSH](#12-远程-ssh)
13. [Ombro 伴侣](#13-ombro-伴侣)
14. [工具栏与快捷键速查](#14-工具栏与快捷键速查)

---

## 1. 整体布局（主界面）

### 截图参考
`docs/image/home.png`

### UI 结构描述

```
┌─────────────────────────────────────────────────────────────┐
│  左侧侧边栏         顶部工具栏           右上角操作区          │
│  [工作区列表]   [Select][Terminal][Note][Text][Drawing][File]  [在编辑器中打开]
│  ─────────────────────────────────────────────────────────── │
│  │            │                                              │
│  │ 工作区1    │                                              │
│  │ 工作区2    │              无限画布区域                     │
│  │ ─────────  │         (Pixi.js 渲染层)                     │
│  │ 工作区3    │                                              │
│  │            │                                              │
│  │            │   ┌──────────┐    ┌──────────┐              │
│  │            │   │ Terminal │────│ Terminal │              │
│  │            │   │  (Agent) │    │  (Agent) │              │
│  │            │   └──────────┘    └──────────┘              │
│  │            │         │                                    │
│  │            │   ┌─────┴────┐                               │
│  │            │   │  Note    │                               │
│  │            │   └──────────┘                               │
│  └────────────┤──────────────────────────────────────────── │
│               │  底部右侧: 缩放控件 + 迷你地图                │
└─────────────────────────────────────────────────────────────┘
```

### 关键 UI 元素

| 区域 | 描述 | 实现要点 |
|------|------|----------|
| 左侧侧边栏 | 工作区列表，图标+名称，支持文件夹/分组 | 固定宽度面板，可折叠 |
| 顶部工具栏 | 节点类型选择器（Select / Terminal / Note / Text / Drawing / File / Connection） | 水平排列 icon buttons |
| 画布区域 | Pixi.js `<canvas>`，节点为绝对定位浮层 | 占满剩余空间 |
| 底部右侧 | 缩放百分比控件 + 迷你地图 | fixed 定位，z-index 高于画布 |
| 右上角 | "在编辑器中打开"按钮 | 调用系统打开工作区目录 |

---

## 2. 工作区（Workspace）

### 截图参考
`docs/image/home.png`（侧边栏区域）

### 核心概念

工作区是项目容器，记忆画布布局、终端位置、代理分配和设置。

### UI 交互

**创建工作区：**
- 侧边栏顶部 `+` 按钮 → 弹出 Modal
- 填写：工作目录路径（必填）、图标（选填）
- 创建后自动出现在侧边栏并打开

**编辑工作区：**
- 右键侧边栏条目 → "Edit" → 编辑名称、图标、工作目录、代理指令
- 从编辑界面管理 `CLAUDE.md` / `AGENTS.md`（可开启自动同步两个文件）

**组织工作区：**
- **文件夹（Folders）**：将相关工作区归组（同项目不同目录）
- **分组（Groups）**：侧边栏中的分隔标签（区分个人/工作项目）

### 快捷键

| 操作 | 快捷键 |
|------|--------|
| 切换到上/下工作区 | `⌘↑` / `⌘↓` |
| 按编号跳转 | 双击 `⌘` 后按数字 |
| 滑动切换（触控板） | 按住 `⌘` + 双指上下滑动 |

### 持久化数据结构

```
~/.open-maestri/
├── manifest.json          # schemaVersion: 1，工作区索引
├── preferences.json       # 全局偏好（语言/主题）
└── workspaces/{UUID}/workspace.json  # schemaVersion: 2
```

---

## 3. 画布（Canvas）

### 截图参考
`docs/image/home.png`、`docs/image/create-terminal.png`

### 画布引擎

- **渲染**：Pixi.js v8，无限 2D 空间
- **节点覆盖层**：React 组件以绝对定位浮层叠加在 Pixi `<canvas>` 上方
- **坐标转换**：`CanvasCoordinateSystem` 负责 Pixi 世界坐标 ↔ 屏幕坐标

### 节点插入

1. 从顶部工具栏选择节点类型
2. 在画布上**点击拖拽**画出矩形
3. 节点以绘制的尺寸和位置出现
4. 如是 Terminal，随即弹出代理选择 Modal

### 节点操作

| 操作 | 方法 |
|------|------|
| 移动 | 从节点内部空区域（通常是顶部 header）拖拽 |
| 缩放 | 拖拽节点角落或边缘 |
| 复制 | 按住 `⌥` 拖拽，或右键 → Duplicate |
| 删除 | `⌘W`，或右键 → Delete |
| 聚焦到视口 | 选中节点后按 `\` |

### 画布导航

**触控板：**
- 平移：双指滑动
- 缩放：捏合

**鼠标：**
- 平移：按住滚轮拖拽
- 平移+缩放：按住滚轮并滚动
- 缩放：`⌘` + 滚轮
- 备选平移：按住 Space + 点击拖拽

**键盘：**
- 放大/缩小：`⌘+` / `⌘-`

### 磁力瓦片对齐（Magnetic Tile Snapping）

按住 `⌘` 拖拽节点时激活：
- **贴墙对齐**：节点对齐到相邻节点的最近边缘
- **填隙**：拖入空隙时自动定位以填满间隙
- **无网格**：基于实际布局自适应，不锁定到固定尺寸

### 迷你地图

位于**右下角**，显示当前画布中的位置全貌。

### 节点选中态

选中节点时显示**虚线边框**；点击画布空白区域取消选中。

---

## 4. 终端节点（Terminal）

### 截图参考
`docs/image/create-terminal.png`、`docs/image/agents.png`

### 创建流程

```
选择 Terminal 工具 → 画布拖拽 → 弹出 Modal
                                    ↓
                           选择 Coding Agent
                           （Claude Code / Codex / OpenCode / Shell...）
                                    ↓
                           可选：设置名称 + 图标
                                    ↓
                           Terminal 节点出现在画布
```

### 节点 UI 结构

```
┌─────────────────────────────┐
│  [图标] 名称     [⌘数字角标] │  ← Header（拖拽区域）
├─────────────────────────────┤
│                             │
│   xterm.js 终端输出区域      │
│                             │
└─────────────────────────────┘
```

### 角色（Roles）

每个 Terminal 可分配角色，代理启动时自动注入对应角色指令：

| 角色示例 | 说明 |
|---------|------|
| Lead | 协调者，将任务分发给其他代理 |
| Coder | 专注代码实现 |
| Reviewer | 代码审查与批评 |
| Tester | 编写和执行测试 |

- 角色通过在项目子目录写入各自的 `CLAUDE.md` / `AGENTS.md` 实现
- 管理入口：**Settings → Agents**（创建、编辑、组织角色）
- 右键已有 Terminal → 可重新分配角色

### 终端间跳转

- 按住 `⌘` → 每个终端 Header 显示数字徽章
- 保持按住 `⌘` 的同时按数字 → 立即聚焦对应终端（支持最多 9 个）

### 数据流

```
PTY 进程（Main Process）
    ↓ pty:data:{id}  （动态 IPC channel）
xterm.js（Renderer，直接写入，不经 Zustand）
```

### 删除

选中 Terminal → `⌘W`（关闭进程并从画布移除）

---

## 5. 笔记节点（Note）

### 截图参考
`docs/image/home.png`（画布右侧贴纸节点）

### 本质

看起来是便签，实际是保存到磁盘的真实 `.md` 文件。

### 创建

工具栏选 **Note** → 画布拖拽 → 在 Maestri 存储目录创建新 `.md` 文件

### 节点 UI 结构

```
┌─────────────────────────────┐
│  [Raw|Formatted] 文件名  [⋯] │  ← 上下文工具栏（含 Move to...）
├─────────────────────────────┤
│                             │
│  Raw 模式：纯文本 Markdown   │
│  Formatted 模式：实时渲染    │
│  （支持表格/标题/代码块）     │
│                             │
└─────────────────────────────┘
```

### 功能特性

| 功能 | 描述 |
|------|------|
| 双视图 | Raw（编辑）/ Formatted（渲染预览），从上下文工具栏切换 |
| 内联图片 | 直接粘贴图片；Formatted 视图渲染预览，Raw 视图显示语法 |
| 自定义名称 | 默认取第一行文字；双击 header 或右键 → Rename 设置固定名称 |
| 自定义路径 | 上下文工具栏 → **Move to...** 将文件移到项目指定目录 |
| 拖入支持 | 从 Finder 拖入 `.md`/`.markdown`/`.txt` 直接作为 Note 使用 |

### 笔记链（Note Chaining）

Notes 可与其他 Notes 连接，形成层级结构：
- 代理只需连接入口 Note，即可遍历整条链
- 适合组织大量上下文为思维导图结构

### 删除

`⌘W` → Note 及其底层文件被删除

---

## 6. 连接（Connection）

### 截图参考
`docs/image/home.png`（画布节点间的连线）

### 核心作用

连接两个节点后，Maestri 在各终端中安装 **Maestri Agent Skill**，使代理具备跨进程通信能力（agent-agnostic，任意 CLI 工具之间均可通信）。

### 创建连接

**方法 1（工具栏）：**
- 选中 Terminal → 点击工具栏 **Connection** 工具 → 光标变为连线追踪状态 → 点击目标节点完成

**方法 2（快捷键）：**
- 选中 Terminal → 按 `L` → 同上

### 视觉效果

物理动画绳索（rope-like cable with physics animation），一个节点可有多条连接。

### 连接类型

| 类型 | 说明 |
|------|------|
| Terminal ↔ Terminal | 代理间相互发送 Prompt / 接收响应 |
| Terminal ↔ Note | 代理可读写该 Note 内容 |
| Terminal ↔ Portal | 代理可控制浏览器（点击/输入/截图/读取 DOM） |
| Note ↔ Note | 笔记链，代理从入口 Note 遍历整条链 |
| Portal ↔ Portal | 共享存储 Session（Cookie / 登录态） |

### 重要行为

**接收方代理须保持未选中状态**：
- Maestri 只监控未被聚焦的终端
- 若用户选中接收方，Maestri 认为用户要手动控制，停止监控 → 等待方将收不到响应

---

## 7. 文件树节点（File Tree）

### 截图参考
`docs/image/file.png`

### 节点 UI 结构

```
┌─────────────────────────────────────┐
│  [<][>] 路径   [List|Grid]  [Branch]│  ← 顶部工具栏
├─────────────────────────────────────┤
│                                     │
│  List 模式：层级文件列表             │
│  Grid 模式：缩略图网格               │
│  （图片/PDF/视频显示 Quick Look）    │
│                                     │
│  ──── Diff 视图 ────                │
│  未提交变更差异 + 代理协作聊天入口   │
│                                     │
└─────────────────────────────────────┘
```

### 功能特性

| 功能 | 描述 |
|------|------|
| 多实例 | 同一画布可放多个 File Tree，各自独立记忆状态 |
| 视图切换 | List（层级大纲）/ Icon Grid（缩略图） |
| 导航 | 工具栏可动态切换根目录；右键菜单支持创建/重命名/移动/删除 |
| 文件拖拽 | 拖到 Terminal → 作为上下文共享给代理；拖到画布 → 创建预览节点 |
| Git 集成 | 顶部分支指示器 → 点击展开 Git 操作菜单 |
| Diff 视图 | 内置差异视图；选中代码块 → 弹出聊天图标 → 可向代理提问 |

### Git 操作菜单

Commit / Pull / Push / Checkout / New Branch / Merge / Fetch / Stash

---

## 8. Maestro 模式

### 概念

将 Terminal 从普通代理升级为**管理者**，可在画布上自主招募代理、分配角色、接线 Note、完成后解雇。

### 启用方式

Terminal 创建表单 → 或右键已有 Terminal → **Edit Terminal** → **Details** Tab → 勾选 **Maestro** → 保存

### Maestro 能力

| 能力 | 描述 |
|------|------|
| 招募（Recruit） | 在自身下方 spawn 新 Terminal，指定代理和角色 |
| 接线（Connect） | 将新成员接入现有 Note，共享信息源 |
| 重分配角色 | 换角色或修改角色指令（保留坐标/名称/连接，仅重启代理进程） |
| 解雇（Dismiss） | 关闭成员 Terminal，保持画布整洁 |

### 布局

Maestro 自动将招募的成员**均匀排布在自身下方**（可手动拖动调整）。

### 混合代理团队

可在 Prompt 中指定不同成员使用不同代理工具：

```
"让 Codex 担任 Reviewer，Claude 担任 Builder，OpenCode 担任 Writer"
```

---

## 9. 楼层（Floors）

### 概念

隔离的分支工作环境，基于 APFS copy-on-write 克隆，创建极快且几乎不额外占空间。

### 使用场景

需要上下文切换时（修 bug、审 PR、试验性功能），无需 stash/切换，保持原工作区不变。

### 楼层 UI 入口

**右下角楼层按钮**（位于迷你地图旁）：
- 点击 → 画布进入 3D 空间视图
- 点击新楼层按钮 → 填写名称、分支、是否复制 Ground 布局 → 创建

### 楼层面板信息

- 文件变更列表及 diff 统计
- 合并冲突检测
- **Land** 按钮（着陆：将 commits 合并回原仓库）

### Hooks 系统

右键楼层按钮 → **Configure Hooks...**

| Hook 类型 | 时机 | 用途示例 |
|-----------|------|----------|
| Setup | 楼层创建时（可自动运行） | 安装依赖、链接服务 |
| Run | 点击播放按钮时 | 启动 dev server、运行测试 |
| Teardown | 楼层删除时 | 清理资源、移除临时文件 |

**Hook 环境变量：**
`$MAESTRI_FLOOR_NAME` / `$MAESTRI_BRANCH_NAME` / `$MAESTRI_FLOOR_PATH` / `$MAESTRI_ROOT_PATH` / `$MAESTRI_PROJECT_NAME`

### 要求

- APFS 磁盘卷（现代 Mac 默认）
- 已初始化 Git 仓库

---

## 10. 门户节点（Portal）

### 概念

画布上的嵌入式浏览器窗口，支持网页浏览、本地文件预览、代理自动化操控。

### 创建

工具栏点击 **Portal**（地球图标）或按 `P` → 输入 URL

### 每个 Portal 独立运行一个 WebKit（Safari）实例，含独立存储。

### 代理自动化能力

连接 Terminal 后，代理通过 `maestri` CLI 控制 Portal：

| 能力 | 描述 |
|------|------|
| 交互 | 点击、输入、滚动 |
| 导航 | 跳转 URL、后退、刷新 |
| 截图 | 截取页面视图 |
| JavaScript | 在页面上下文执行自定义脚本 |
| DOM 读取 | 检查页面结构 |
| 控制台 | 查看浏览器控制台输出 |

代理也可**自主创建新 Portal**，无需用户手动放置。

---

## 11. 例程（Routines）

### 概念

定时向代理发送 Prompt 的自动化任务，用于自动化重复性开发工作流。

### 创建入口

**File → Routines → New Routine**

### 配置项

- **Prompt**：要发送给代理的指令
- **Interval**：执行间隔（如每 5 分钟、每小时）
- **Target Agent**：指定接收 Prompt 的 Terminal

### 链式命令

用 `&&`（独立成行）分隔多条指令，前一条完成后才发送下一条：

```
pull the latest changes
&&
run the test suite
&&
summarize the results
```

### 管理

暂停/恢复 / 编辑 / 删除；活跃的 Routine 显示实时运行指示器。

---

## 12. 远程 SSH

### 启用入口

**Settings > General > Remote SSH > Configure > 开启 Enable SSH workspaces**

### 工作原理

连接后 Maestri 在远程服务器安装脚本，开启反向隧道（默认端口 7433），实现跨机代理通信。

### 配置项

Host / User / Port（默认 22）/ Script Path / Add to PATH

---

## 13. Ombro 伴侣

### 概念

设备端 AI 伴侣，监控代理运行状态，浮窗形式常驻于应用外部（Apple Silicon + macOS Tahoe 26+）。

### 打开方式

`⇧O` 打开/关闭 Ombro 浮窗

### 功能

| 功能 | 描述 |
|------|------|
| 代理监控 | 被动监控所有运行中的代理；代理完成任务时推送通知（摘要 + 终端快照 + 建议操作） |
| 状态查询 | 直接向 Ombro 提问代理状态 |
| 添加笔记 | 自然语言追加条目到工作区的 "Ombro Notes" 笔记 |
| 汇总笔记 | 遍历工作区所有 Note 生成概览 |

### 技术

完全本地运行（Apple Foundation Models），不发起任何 API 调用。

---

## 14. 工具栏与快捷键速查

### 顶部工具栏节点类型

| 工具 | 说明 | 快捷键 |
|------|------|--------|
| Select | 选择/移动模式 | `Esc` |
| Terminal | 创建终端节点 | — |
| Note | 创建笔记节点 | — |
| Text | 创建文本标签 | — |
| Drawing | 创建手绘区域 | — |
| File Tree | 创建文件树节点 | — |
| Connection | 创建连接 | `L`（选中节点后） |
| Portal | 创建门户节点 | `P` |

### 全局快捷键

| 操作 | 快捷键 |
|------|--------|
| 删除节点 | `⌘W` |
| 复制节点 | `⌥` + 拖拽 |
| 聚焦节点到视口 | `\`（节点选中时） |
| 放大 / 缩小 | `⌘+` / `⌘-` |
| 磁力对齐 | `⌘` + 拖拽 |
| 跳转到终端（按编号） | `⌘` 按住 + 数字键 |
| 切换工作区 | `⌘↑` / `⌘↓` |
| 按编号切换工作区 | 双击 `⌘` + 数字 |
| 开始连接（选中 Terminal 后） | `L` |
| 打开 Ombro | `⇧O` |

---

## 15. 右键上下文菜单（Context Menu）

### 截图参考
`docs/image/manue.png`

### 节点右键菜单

右键点击画布上的节点后弹出上下文菜单，背景为深色半透明浮层，菜单项之间有分隔线区分功能分组。

### 菜单结构（从截图推断）

```
┌─────────────────────────┐
│  Duplicate              │  ← 复制节点
│  Edit Terminal / Rename │  ← 编辑节点（Terminal 改名/配置）
├─────────────────────────┤
│  Assign Role            │  ← 分配角色（Terminal 节点专属）
│  Enable Maestro         │  ← 切换 Maestro 模式
├─────────────────────────┤
│  Connect                │  ← 开始创建连接
├─────────────────────────┤
│  Delete                 │  ← 删除节点（红色高亮/危险操作）
└─────────────────────────┘
```

### 视觉设计规范

| 属性 | 描述 |
|------|------|
| 背景 | 深色半透明（`--color-bg-floating` 或类似 token） |
| 圆角 | 中等圆角（约 8px） |
| 内边距 | 菜单项上下各约 6px，左右约 12px |
| 分隔线 | 细线，颜色为 `--color-border-subtle` |
| 危险操作 | Delete 等破坏性操作用红色文字（`--color-danger`）高亮 |
| 宽度 | 约 180–220px，内容自适应 |
| 阴影 | 有 drop-shadow，浮于画布之上 |

### 菜单触发规则

- **触发方式**：右键单击节点
- **关闭方式**：点击菜单外任意区域 / 按 `Esc`
- **定位**：跟随鼠标光标位置，边界检测防止超出视口

### 不同节点类型的差异项

| 节点类型 | 专属菜单项 |
|---------|-----------|
| Terminal | Edit Terminal、Assign Role、Enable Maestro |
| Note | Rename、Move to...、Raw/Formatted 切换 |
| File Tree | —（使用节点内部工具栏） |
| Connection | Delete（删除连线） |
| Portal | — |

### 实现要点

- 使用 Radix UI `DropdownMenu` 或 `ContextMenu` 组件（项目已集成 Radix UI）
- 通过 `react-context-menu` 或 Pixi.js 的 `rightclick` 事件触发
- 菜单内容根据节点类型动态渲染（策略模式：`getContextMenuItems(nodeType)`）
- 危险操作（Delete）需二次确认或明显视觉区分

---

## 附录：open-maestri 实现范围说明

基于 open-maestri 当前架构，各功能对应实现状态：

| 功能 | 当前 Epic | 说明 |
|------|-----------|------|
| 工作区管理 | Epic 1 | 已规划（backlog） |
| 无限画布 + 节点 CRUD | Epic 2 | 已规划 |
| Terminal 节点 + PTY | Epic 3 | 已规划 |
| Note 节点 + Markdown | Epic 4 | backlog |
| Connection + 代理通信 | Epic 5 | backlog |
| File Tree 节点 | Epic 6 | backlog |
| Floors / Portal / Routines / SSH / Ombro | Epic 7+ | 高级特性，暂为 backlog |

> 参考截图路径：`docs/image/home.png`、`docs/image/agents.png`、`docs/image/create-terminal.png`、`docs/image/tool.png`、`docs/image/file.png`
