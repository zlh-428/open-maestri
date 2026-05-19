# Canvas Interaction Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将画布交互状态机从节点视图层上移至 `CanvasViewportView`，消除三套状态机竞争，使所有节点类型行为完全一致。

**Architecture:** 新建 `CanvasInteractionHandler.swift` 作为唯一 `mouseDown/Dragged/Up` 处理者，用 `CanvasInteraction` 枚举取代散落在 `CanvasViewportView`、`BaseNodeView`、`ContentEventRouterView` 中的状态变量。`BaseNodeView` 瘦身为纯展示容器，删除所有鼠标事件处理和 `ContentEventRouterView`。

**Tech Stack:** Swift 5.9, AppKit NSView, macOS 14+, `NSEvent.addLocalMonitorForEvents`

---

## 文件改动清单

| 文件 | 类型 | 职责 |
|------|------|------|
| `Sources/Canvas/CanvasInteractionHandler.swift` | **新建** | `CanvasInteraction` 枚举 + `CanvasHitTestResult` 枚举 + 统一 `mouseDown/Dragged/Up` extension |
| `Sources/Canvas/NodeLayer/BaseNodeView.swift` | **大幅删减** | 删除 `mouseDown/Dragged/Up/Entered/Exited`、`ContentEventRouterView`、`installDragIntercept`、`isResizing` 等；保留展示、`resizeEdge(at:)`、`isNodeSelected`、回调属性 |
| `Sources/Canvas/CanvasViewportView.swift` | **改造** | 新增 `interaction: CanvasInteraction` 替换散落状态变量；`layout()` 中改用 `interaction` 判断跳过拖动节点；删除 `beginNodeDrag`（公开方法，CanvasDragHandler 内用）；新增 `onNodeResizeEnded` 回调 |
| `Sources/Canvas/CanvasDragHandler.swift` | **删减** | 删除 `beginNodeDrag`；删除旧散落状态变量（已移入 `interaction`）；snap/grid 逻辑保留供 `CanvasInteractionHandler` 调用 |
| `Sources/Canvas/CanvasNodeRenderer.swift` | **小改** | 删除 `onNodeClicked` 注册；将 `onFrameChanged` 改为注册 `onNodeResizeEnded`（画布回调） |
| `Sources/Canvas/NodeLayer/FileTreeNodeView.swift` | **小改** | 删除 `layout()` 中对 `contentEventRouter` 的引用 |

---

### Task 1: 新建 CanvasInteraction 枚举与 CanvasHitTestResult

**Files:**
- Create: `Sources/Canvas/CanvasInteractionHandler.swift`

- [ ] **Step 1: 新建文件，写入枚举定义**

```swift
import AppKit

// MARK: - 画布命中测试结果

/// 语义化命中区域，供 CanvasInteractionHandler 使用
enum CanvasHitTestResult {
    case canvas
    case nodeHeader(UUID)
    case nodeContent(UUID, NSView)
    case nodeResize(UUID, BaseNodeView.ResizeEdge)
}

// MARK: - 画布交互状态机

/// 替换 CanvasViewportView 上的所有散落交互状态变量，
/// 所有状态存储在 associated values 中，避免状态不一致。
enum CanvasInteraction {
    case idle
    /// 鼠标已按下但尚未确定是点击还是拖动；
    /// contentTarget 非 nil 表示已将 mouseDown 透传给该视图（Terminal 等内容区）
    case mayDragNode(UUID, startMouse: CGPoint, startFrame: CGRect, contentTarget: NSView?)
    case draggingNode(UUID, startMouse: CGPoint, startFrame: CGRect)
    case batchDragging([UUID: CGRect], primaryId: UUID, startMouse: CGPoint)
    case resizingNode(UUID, edge: BaseNodeView.ResizeEdge, startFrame: CGRect, startMouse: CGPoint)
    case marquee(start: CGPoint)
    case panCanvas(startOrigin: CGPoint, startMouse: CGPoint)
    case drawing(start: CGPoint)
}
```

- [ ] **Step 2: 编译验证枚举定义无错误**

```bash
cd /Users/zhoulihao/Desktop/maestri/open-maestri && swift build 2>&1 | tail -20
```

期望：枚举本身无错误（可能有 CanvasViewportView 中旧引用的无关错误，暂时忽略）。

- [ ] **Step 3: Commit**

```bash
git add Sources/Canvas/CanvasInteractionHandler.swift
git commit -m "✨ feat(canvas): add CanvasInteraction state machine enum and CanvasHitTestResult"
```

---

### Task 2: CanvasViewportView — 新增 interaction 属性，删除散落状态变量

**Files:**
- Modify: `Sources/Canvas/CanvasViewportView.swift`

- [ ] **Step 1: 在 `CanvasViewportView` 中新增 `interaction` 属性，删除将被替换的散落状态变量**

找到文件中 `// MARK: - 节点拖动状态（由 CanvasDragHandler 扩展使用）` 区块（约第 416 行），将整个区块替换为：

```swift
// MARK: - 统一交互状态机

/// 当前画布交互状态（替换所有散落的拖动/选择/resize 状态变量）
var interaction: CanvasInteraction = .idle

/// 拖动期间用于 drag guideline 绘制
var dragGuidelines: [GuideLine] = [] {
    didSet { needsDisplay = true }
}

// 以下保留（与状态机无关，供外部回调）
var onNodeDragEnded: ((UUID, CGRect) -> Void)?
var onBatchNodeDragEnded: (([UUID: CGRect]) -> Void)?
/// resize 结束时回调（替换 onFrameChanged 的旧机制）
var onNodeResizeEnded: ((UUID, CGRect) -> Void)?

// MARK: - 平移模式状态（由 CanvasInputHandler 扩展使用）

var isPanMode = false
var isSpaceHeld = false

// MARK: - 节点绘制模式状态

var isInDrawingMode: Bool = false
var drawingNodeType: String = "terminal"
var onNodeDrawn: ((String, CGRect) -> Void)?

// MARK: - 文件拖放状态（由 CanvasDragHandler 扩展使用）

var onFilesDropped: (([String], CGPoint) -> Void)?
var onFilesDroppedOnNode: (([String], UUID) -> Void)?
var dropTargetNodeId: UUID?

// MARK: - 动画定时器（由 CanvasInputHandler 扩展使用）

var animationTimer: Timer?
```

- [ ] **Step 2: 更新 `layout()` 方法，改用 `interaction` 判断跳过拖动/resize 节点**

找到 `layout()` 方法（约第 323 行），替换其中的跳过逻辑：

```swift
override func layout() {
    super.layout()
    // 跳过正在被交互的节点（其 frame 由 CanvasInteractionHandler 直接维护）
    let skipIds: Set<UUID>
    switch interaction {
    case .draggingNode(let id, _, _):
        skipIds = [id]
    case .batchDragging(let frames, _, _):
        skipIds = Set(frames.keys)
    case .resizingNode(let id, _, _, _):
        skipIds = [id]
    case .mayDragNode(let id, _, _, _):
        skipIds = [id]
    default:
        skipIds = []
    }
    for (id, view) in nodeViews {
        if skipIds.contains(id) { continue }
        if let canvasFrame = nodeCanvasFrames[id] {
            view.frame = canvasRectToScreen(canvasFrame)
            view.setBoundsSize(canvasFrame.size)
        }
    }
}
```

- [ ] **Step 3: 删除 `CanvasViewportView` 的旧 `selectionRect` computed property（移入 CanvasInteractionHandler）**

删除以下 computed property（约第 451 行）：
```swift
var selectionRect: CGRect? {
    guard let start = selectionStartPoint, let current = selectionCurrentPoint else { return nil }
    return CGRect(
        x: min(start.x, current.x),
        y: min(start.y, current.y),
        width: abs(current.x - start.x),
        height: abs(current.y - start.y)
    )
}
```

并在 `CanvasInteractionHandler.swift` 末尾添加同名计算属性（在 extension 内）：

```swift
extension CanvasViewportView {
    /// 当前框选矩形（从 interaction.marquee 状态读取）
    var selectionRect: CGRect? {
        guard case .marquee(let start) = interaction,
              let current = marqueeCurrentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }
}
```

并在 `CanvasViewportView.swift` 中新增一个辅助变量（用于框选实时绘制）：

```swift
// 框选当前鼠标位置（仅在 interaction == .marquee 时有效）
var marqueeCurrentPoint: CGPoint?
// 节点绘制模式当前鼠标位置
var drawingCurrentPoint: CGPoint?
// 磁吸/网格 snap 辅助状态（由 CanvasInteractionHandler 维护）
var lastSnapActive: Bool = false
var lastSnappedGridOrigin: CGPoint? = nil
```

> **注意**：Swift 不允许在 extension 中声明 stored property，所有辅助状态变量必须在 `CanvasViewportView` 主体中声明。Task 8 的 extension 代码不包含 stored property 声明（已移至此处）。

- [ ] **Step 4: 编译，确认无 undeclared identifier 错误（旧变量引用会在后续 Task 中逐步修复）**

```bash
cd /Users/zhoulihao/Desktop/maestri/open-maestri && swift build 2>&1 | grep "error:" | head -20
```

- [ ] **Step 5: Commit**

```bash
git add Sources/Canvas/CanvasViewportView.swift Sources/Canvas/CanvasInteractionHandler.swift
git commit -m "♻️ refactor(canvas): replace scattered drag/resize state vars with CanvasInteraction enum"
```

---

### Task 3: BaseNodeView 瘦身 — 删除鼠标事件处理与 ContentEventRouterView

**Files:**
- Modify: `Sources/Canvas/NodeLayer/BaseNodeView.swift`

> **重要**：这是本次重构改动量最大的单步，必须一次性完成以避免编译中间态。

- [ ] **Step 1: 删除 `contentEventRouter` 懒加载属性和相关引用**

在 `BaseNodeView` 类定义中，删除以下内容：
```swift
// 删除这整个 lazy var：
lazy var contentEventRouter: ContentEventRouterView = {
    let v = ContentEventRouterView()
    v.autoresizingMask = [.width, .height]
    return v
}()
```

- [ ] **Step 2: 删除 `setup()` 中 contentEventRouter 相关代码**

在 `setup()` 方法中，删除以下代码块：
```swift
// 内容区事件路由层（常驻 contentView 之上）
contentEventRouter.baseNodeView = self
addSubview(contentEventRouter, positioned: .above, relativeTo: contentView)
```

- [ ] **Step 3: 删除 resize 状态变量（移入 CanvasInteraction 枚举）**

删除以下属性：
```swift
var isResizing = false
fileprivate var resizeEdge: ResizeEdge?
fileprivate var resizeStartLocation: CGPoint?
fileprivate var resizeStartFrame: CGRect?
```

- [ ] **Step 4: 删除鼠标事件处理方法**

删除以下全部方法（`BaseNodeView` 类内）：
- `override func mouseDown(with event: NSEvent)`（约第 202 行）
- `override func mouseDragged(with event: NSEvent)`（约第 227 行）
- `override func mouseUp(with event: NSEvent)`（约第 248 行）
- `override func mouseMoved(with event: NSEvent)`（约第 261 行）
- `override func mouseExited(with event: NSEvent)`（约第 284 行）

- [ ] **Step 5: 删除拖动拦截方法**

删除：
```swift
// 删除整个 // MARK: - 拖动拦截 区块：
fileprivate func installDragIntercept() { ... }
private func removeDragIntercept() { ... }
```

- [ ] **Step 6: 删除 onOptionDragDuplicate、onNodeClicked、hasTriggeredDuplicate**

删除以下属性：
```swift
var onOptionDragDuplicate: (() -> Void)?
fileprivate var hasTriggeredDuplicate = false
var onNodeClicked: ((NSEvent) -> Void)?
```

- [ ] **Step 7: 更新 `layout()` 方法，删除 contentEventRouter 的 frame 更新**

将 `layout()` 方法中的：
```swift
contentView.frame = CGRect(x: ew, y: ew, width: w - ew * 2, height: bh - h - ew)
contentEventRouter.frame = contentView.frame
```
改为：
```swift
contentView.frame = CGRect(x: ew, y: ew, width: w - ew * 2, height: bh - h - ew)
```

- [ ] **Step 8: 更新 `isNodeSelected` didSet，删除 contentEventRouter 相关操作**

将 `isNodeSelected` didSet 中的：
```swift
contentEventRouter.isNodeSelected = isNodeSelected
if contentEventRouter.superview == nil {
    addSubview(contentEventRouter, positioned: .above, relativeTo: contentView)
}
contentEventRouter.frame = contentView.frame
```
全部删除，只保留：
```swift
var isNodeSelected: Bool = false {
    didSet {
        guard oldValue != isNodeSelected else { return }
        updateSelectionOverlay()
        if !isNodeSelected {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                resizeHandle.animator().alphaValue = 0
            }
        }
    }
}
```

- [ ] **Step 9: 删除文件末尾整个 `ContentEventRouterView` 类（约第 519 行到文件结尾）**

删除 `// MARK: - Header 事件转发视图` 下方的 `HeaderForwardingView` 中的转发方法，只保留空转发（右键菜单仍需要）：

```swift
final class HeaderForwardingView: NSView {
    // 鼠标事件不再需要转发：画布层通过 hitTestCanvas 直接处理
    // 保留 rightMouseDown 自然传递给 BaseNodeView（继承链）
}
```

并完全删除 `ContentEventRouterView` 类（从 `// MARK: - 内容区事件路由视图` 到文件末尾）。

- [ ] **Step 10: 编译确认**

```bash
cd /Users/zhoulihao/Desktop/maestri/open-maestri && swift build 2>&1 | grep "error:" | head -30
```

期望：错误集中在引用了已删除符号的地方（`CanvasDragHandler`、`FileTreeNodeView` 等），这些在后续 Task 中修复。

- [ ] **Step 11: Commit**

```bash
git add Sources/Canvas/NodeLayer/BaseNodeView.swift
git commit -m "♻️ refactor(canvas): slim down BaseNodeView — remove mouse event handling and ContentEventRouterView"
```

---

### Task 4: FileTreeNodeView — 删除 contentEventRouter 引用

**Files:**
- Modify: `Sources/Canvas/NodeLayer/FileTreeNodeView.swift`

- [ ] **Step 1: 删除 `layout()` 中对 `contentEventRouter` 的引用**

找到 `FileTreeNodeView.layout()` 末尾，删除：
```swift
contentEventRouter.frame = contentView.frame
```

该行是 `super.layout()` 之后手动同步 contentEventRouter 的代码，已不再需要。

- [ ] **Step 2: 编译确认 FileTreeNodeView 无错误**

```bash
cd /Users/zhoulihao/Desktop/maestri/open-maestri && swift build 2>&1 | grep "FileTree\|error:" | head -20
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Canvas/NodeLayer/FileTreeNodeView.swift
git commit -m "♻️ refactor(canvas): remove contentEventRouter reference from FileTreeNodeView layout"
```

---

### Task 5: CanvasDragHandler — 删除旧状态变量引用，保留 snap 逻辑

**Files:**
- Modify: `Sources/Canvas/CanvasDragHandler.swift`

- [ ] **Step 1: 删除 `beginNodeDrag` 方法（整个方法，约第 8–31 行）**

删除：
```swift
func beginNodeDrag(nodeId: UUID?, screenLoc: CGPoint) {
    // ... 整个方法
}
```

- [ ] **Step 2: 删除 `mouseDown` override（约第 36–91 行）**

整个 `override func mouseDown(with event: NSEvent)` 方法删除。新的 mouseDown 在 `CanvasInteractionHandler` 中实现。

- [ ] **Step 3: 删除 `mouseMoved` override（约第 93–98 行）**

删除：
```swift
override func mouseMoved(with event: NSEvent) {
    if connectingFromNodeId != nil {
        connectionDragPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }
}
```
（此逻辑移入 CanvasInteractionHandler）

- [ ] **Step 4: 删除 `mouseDragged` override（约第 100–228 行）**

删除整个 `override func mouseDragged(with event: NSEvent)` 方法。拖动逻辑在 `CanvasInteractionHandler` 中重新实现。

- [ ] **Step 5: 删除 `mouseUp` override（约第 255–344 行）**

删除整个 `override func mouseUp(with event: NSEvent)` 方法。mouseUp 在 `CanvasInteractionHandler` 中重新实现。

- [ ] **Step 6: 保留以下辅助方法（供 CanvasInteractionHandler 调用）**

确认以下方法**保留不变**（只删上面几个 override，不动这些）：
- `func snapToGrid(_ origin: CGPoint, size: CGSize) -> CGPoint`（约第 232 行）
- `func drawSnapGuidelines()`
- `func drawDrawingRect()`
- `func drawSelectionRect()`
- `func drawTemporaryConnection()`
- `func registerDragTypes()` 及 `draggingEntered/Updated/Exited/performDragOperation`
- `func nodeId(for view: NSView?) -> UUID?`
- `func nodeId(at screenPoint: CGPoint) -> UUID?`
- `func handleConnectionClick(nodeId: UUID)`
- `func makeTrackingArea()`
- `func defaultNodeSize(for nodeType: String) -> CGSize`

- [ ] **Step 7: 编译确认**

```bash
cd /Users/zhoulihao/Desktop/maestri/open-maestri && swift build 2>&1 | grep "error:" | head -30
```

- [ ] **Step 8: Commit**

```bash
git add Sources/Canvas/CanvasDragHandler.swift
git commit -m "♻️ refactor(canvas): remove overridden mouse methods from CanvasDragHandler, keep snap helpers"
```

---

### Task 6: 实现 CanvasInteractionHandler — hitTestCanvas

**Files:**
- Modify: `Sources/Canvas/CanvasInteractionHandler.swift`

- [ ] **Step 1: 在 `CanvasInteractionHandler.swift` 中新增 extension，实现 `hitTestCanvas(at:)`**

在文件末尾追加：

```swift
// MARK: - CanvasViewportView 交互 extension

extension CanvasViewportView {

    // MARK: - 语义化命中测试

    /// 将画布坐标 point 映射到语义化命中区域
    /// 优先级：resize 热区 > header 区域 > 内容区 > 空白
    func hitTestCanvas(at loc: CGPoint) -> CanvasHitTestResult {
        // 按 zIndex 逆序（最顶层优先）
        let sortedViews = nodeViews.sorted {
            let za = ($0.value as? BaseNodeView).map { _ in nodeCanvasFrames[$0.key]?.minY ?? 0 } ?? 0
            let zb = ($1.value as? BaseNodeView).map { _ in nodeCanvasFrames[$1.key]?.minY ?? 0 } ?? 0
            return za > zb
        }

        for (id, view) in sortedViews {
            guard view.frame.contains(loc) else { continue }
            guard let base = view as? BaseNodeView else { continue }

            // 将画布坐标转换为节点 bounds 坐标
            // view.frame 是缩放后屏幕坐标，bounds 是原始画布尺寸
            let localX = (loc.x - view.frame.minX) / zoom
            let localY = (loc.y - view.frame.minY) / zoom
            let localPoint = CGPoint(x: localX, y: localY)

            // 1. resize 热区优先（豁免 NSScroller 视为空白）
            if let edge = base.resizeEdge(at: localPoint) {
                return .nodeResize(id, edge)
            }

            // 2. header 区域
            let headerH = BaseNodeView.headerHeight
            if localY >= base.bounds.height - headerH {
                return .nodeHeader(id)
            }

            // 3. 内容区：做 deep hitTest 找最深子视图
            // 先检查是否命中 NSScroller，命中则视为画布（让事件自然传递）
            let contentLocal = base.contentView.convert(CGPoint(x: localX, y: localY), from: base)
            if let deepHit = base.contentView.hitTest(contentLocal) {
                if deepHit is NSScroller {
                    // NSScroller 豁免：不拦截，让滚动条自然处理
                    return .canvas
                }
                return .nodeContent(id, deepHit)
            }

            return .nodeContent(id, base.contentView)
        }

        return .canvas
    }

    // MARK: - 选中逻辑

    /// 根据修饰键更新 selectedNodeIds
    func updateSelection(_ id: UUID, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selectedNodeIds.contains(id) {
                selectedNodeIds.remove(id)
            } else {
                selectedNodeIds.insert(id)
            }
        } else {
            if !selectedNodeIds.contains(id) {
                selectedNodeIds = [id]
            }
            // 如果节点已在选中集合内（批量选中状态），mouseUp 时再收窄
        }
    }
}
```

- [ ] **Step 2: 编译确认**

```bash
cd /Users/zhoulihao/Desktop/maestri/open-maestri && swift build 2>&1 | grep "error:" | head -20
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Canvas/CanvasInteractionHandler.swift
git commit -m "✨ feat(canvas): implement hitTestCanvas — semantic hit test returning CanvasHitTestResult"
```

---

### Task 7: 实现 CanvasInteractionHandler — mouseDown

**Files:**
- Modify: `Sources/Canvas/CanvasInteractionHandler.swift`

- [ ] **Step 1: 在 extension 内新增 `mouseDown` override**

在 `updateSelection(_:modifiers:)` 方法后追加：

```swift
override func mouseDown(with event: NSEvent) {
    let loc = convert(event.locationInWindow, from: nil)

    // 1. Space+点击 → 平移模式
    if isSpaceHeld {
        interaction = .panCanvas(startOrigin: canvasOrigin, startMouse: loc)
        NSCursor.closedHand.set()
        return
    }

    // 2. 连线模式：点击节点建立连接，点击空白取消
    if isInConnectingMode {
        let hit = hitTestCanvas(at: loc)
        if case .nodeHeader(let id) = hit {
            handleConnectionClick(nodeId: id)
        } else if case .nodeContent(let id, _) = hit {
            handleConnectionClick(nodeId: id)
        } else {
            deactivateConnectionMode()
        }
        return
    }

    // 兼容：程序触发的连线起点
    if connectingFromNodeId != nil {
        let hit = hitTestCanvas(at: loc)
        if case .nodeHeader(let id) = hit {
            handleConnectionClick(nodeId: id)
            return
        } else if case .nodeContent(let id, _) = hit {
            handleConnectionClick(nodeId: id)
            return
        } else {
            connectingFromNodeId = nil
            connectionDragPoint = nil
            needsDisplay = true
            return
        }
    }

    // 3. 节点绘制模式：空白区域拖拽创建节点
    if isInDrawingMode {
        let hit = hitTestCanvas(at: loc)
        if case .canvas = hit {
            interaction = .drawing(start: loc)
            return
        }
        // 绘制模式下点击节点 → 正常走节点交互
    }

    // 4. 语义化命中测试 → 分发
    let hit = hitTestCanvas(at: loc)
    switch hit {
    case .canvas:
        if !event.modifierFlags.contains(.command) {
            selectedNodeIds.removeAll()
        }
        window?.makeFirstResponder(self)
        interaction = .marquee(start: loc)
        marqueeCurrentPoint = nil

    case .nodeHeader(let id):
        guard let base = nodeViews[id] as? BaseNodeView, !base.isLocked else { return }
        updateSelection(id, modifiers: event.modifierFlags)
        base.onActivated?()
        let startFrame = nodeCanvasFrames[id] ?? .zero
        interaction = .mayDragNode(id, startMouse: loc, startFrame: startFrame, contentTarget: nil)

    case .nodeContent(let id, let deepHit):
        guard let base = nodeViews[id] as? BaseNodeView, !base.isLocked else { return }
        updateSelection(id, modifiers: event.modifierFlags)
        base.onActivated?()
        // 立即将 mouseDown 透传给内容区目标（Terminal 获焦等）
        deepHit.mouseDown(with: event)
        let startFrame = nodeCanvasFrames[id] ?? .zero
        interaction = .mayDragNode(id, startMouse: loc, startFrame: startFrame, contentTarget: deepHit)

    case .nodeResize(let id, let edge):
        guard let base = nodeViews[id] as? BaseNodeView, !base.isLocked else { return }
        updateSelection(id, modifiers: event.modifierFlags)
        base.onActivated?()
        let startFrame = nodeCanvasFrames[id] ?? .zero
        interaction = .resizingNode(id, edge: edge, startFrame: startFrame, startMouse: loc)
        edge.cursor.set()
    }
}
```

- [ ] **Step 2: 编译确认**

```bash
cd /Users/zhoulihao/Desktop/maestri/open-maestri && swift build 2>&1 | grep "error:" | head -20
```

- [ ] **Step 3: Commit**

```bash
git add Sources/Canvas/CanvasInteractionHandler.swift
git commit -m "✨ feat(canvas): implement unified mouseDown in CanvasInteractionHandler"
```

---

### Task 8: 实现 CanvasInteractionHandler — mouseDragged

**Files:**
- Modify: `Sources/Canvas/CanvasInteractionHandler.swift`

- [ ] **Step 1: 在 extension 内新增 `mouseDragged` override**

在 `mouseDown` 方法后追加：

```swift
/// 拖动阈值（像素，屏幕坐标），超过后从 .mayDragNode 切换为真正拖动
private static let dragThreshold: CGFloat = 3.0

override func mouseDragged(with event: NSEvent) {
    let loc = convert(event.locationInWindow, from: nil)

    switch interaction {

    // --- 画布平移 ---
    case .panCanvas(let startOrigin, let startMouse):
        let dx = (loc.x - startMouse.x) / zoom
        let dy = (loc.y - startMouse.y) / zoom
        canvasOrigin = CGPoint(x: startOrigin.x - dx, y: startOrigin.y - dy)
        needsLayout = true
        notifyViewportChanged()

    // --- 等待判断（点击 or 拖动）---
    case .mayDragNode(let id, let startMouse, let startFrame, let contentTarget):
        let dx = loc.x - startMouse.x
        let dy = loc.y - startMouse.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist >= Self.dragThreshold else { return }
        // 安全检查：必须有物理左键按下，防止触控板双指滚动误触
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return }

        // 若已透传 mouseDown 给内容区，发合成 mouseUp 取消其内部状态
        if let target = contentTarget {
            if let cancelEvent = NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: event.locationInWindow,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: event.windowNumber,
                context: nil,
                eventNumber: event.eventNumber,
                clickCount: 1,
                pressure: 0
            ) {
                target.mouseUp(with: cancelEvent)
            }
        }

        // 切换为真正拖动
        let canvasMouse = screenToCanvas(startMouse)
        if selectedNodeIds.count > 1 && selectedNodeIds.contains(id) {
            var startFrames: [UUID: CGRect] = [:]
            for sid in selectedNodeIds {
                startFrames[sid] = nodeCanvasFrames[sid] ?? .zero
            }
            interaction = .batchDragging(startFrames, primaryId: id, startMouse: canvasMouse)
        } else {
            interaction = .draggingNode(id, startMouse: canvasMouse, startFrame: startFrame)
        }
        // fall through：立即处理第一帧拖动
        mouseDragged(with: event)

    // --- 单节点拖动 ---
    case .draggingNode(let id, let startMouse, let startFrame):
        guard let view = nodeViews[id] else { return }
        let currentCanvas = screenToCanvas(loc)
        let rawDX = currentCanvas.x - startMouse.x
        let rawDY = currentCanvas.y - startMouse.y
        var newOrigin = CGPoint(x: startFrame.origin.x + rawDX, y: startFrame.origin.y + rawDY)
        var newFrame = CGRect(origin: newOrigin, size: startFrame.size)

        let otherFrames = nodeCanvasFrames.filter { $0.key != id }.map { $0.value }
        if event.modifierFlags.contains(.command) {
            let (snapped, guidelines) = TileSnapping.snap(draggingFrame: newFrame, against: otherFrames)
            newOrigin = snapped
            newFrame = CGRect(origin: newOrigin, size: startFrame.size)
            dragGuidelines = guidelines
            if snapped != newOrigin && !lastSnapActive {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            lastSnapActive = (snapped != CGPoint(x: startFrame.origin.x + rawDX, y: startFrame.origin.y + rawDY))
        } else {
            let (nodeSnapped, guidelines) = TileSnapping.snap(draggingFrame: newFrame, against: otherFrames)
            let nodeSnapActive = nodeSnapped != newOrigin
            if nodeSnapActive {
                newOrigin = nodeSnapped
                dragGuidelines = guidelines
                if !lastSnapActive {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                lastSnapActive = true
            } else {
                dragGuidelines = []
                let gridSnapped = snapToGrid(newOrigin, size: startFrame.size)
                let gridChanged = gridSnapped != lastSnappedGridOrigin
                newOrigin = gridSnapped
                if gridChanged && lastSnappedGridOrigin != nil {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                }
                lastSnappedGridOrigin = gridSnapped
                lastSnapActive = false
            }
            newFrame = CGRect(origin: newOrigin, size: startFrame.size)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.frame = canvasRectToScreen(newFrame)
        view.setBoundsSize(newFrame.size)
        nodeCanvasFrames[id] = newFrame
        CATransaction.commit()

    // --- 批量拖动 ---
    case .batchDragging(let startFrames, let primaryId, let startMouse):
        let currentCanvas = screenToCanvas(loc)
        let rawDX = currentCanvas.x - startMouse.x
        let rawDY = currentCanvas.y - startMouse.y

        guard let primaryStart = startFrames[primaryId] else { return }
        var primaryNew = CGRect(
            origin: CGPoint(x: primaryStart.origin.x + rawDX, y: primaryStart.origin.y + rawDY),
            size: primaryStart.size
        )
        let otherFrames = nodeCanvasFrames.filter { !startFrames.keys.contains($0.key) }.map { $0.value }
        let (snapped, guidelines) = TileSnapping.snap(draggingFrame: primaryNew, against: otherFrames)
        let finalDX = snapped.x - primaryStart.origin.x
        let finalDY = snapped.y - primaryStart.origin.y
        dragGuidelines = guidelines
        if snapped != primaryNew.origin && !lastSnapActive {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        lastSnapActive = (snapped != primaryNew.origin)
        primaryNew = CGRect(origin: snapped, size: primaryStart.size)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (sid, sFrame) in startFrames {
            guard let sView = nodeViews[sid] else { continue }
            let newOrigin = CGPoint(x: sFrame.origin.x + finalDX, y: sFrame.origin.y + finalDY)
            let newFrame = CGRect(origin: newOrigin, size: sFrame.size)
            sView.frame = canvasRectToScreen(newFrame)
            sView.setBoundsSize(newFrame.size)
            nodeCanvasFrames[sid] = newFrame
        }
        CATransaction.commit()

    // --- Resize ---
    case .resizingNode(let id, let edge, let startFrame, let startMouse):
        guard let view = nodeViews[id] as? BaseNodeView else { return }
        // startMouse、startFrame 均为屏幕坐标（缩放后），dx/dy 亦为屏幕坐标 delta
        let dx = loc.x - startMouse.x
        let dy = loc.y - startMouse.y
        applyResizeOnCanvas(id: id, view: view, edge: edge, dx: dx, dy: dy, startFrame: startFrame)

    // --- 框选 ---
    case .marquee:
        marqueeCurrentPoint = loc
        needsDisplay = true

    // --- 节点绘制模式 ---
    case .drawing:
        drawingCurrentPoint = loc
        needsDisplay = true

    // --- 连线拖动（鼠标在连线 handle 上）---
    case .idle:
        // 连线工具鼠标跟踪
        if connectingFromNodeId != nil {
            connectionDragPoint = loc
            needsDisplay = true
        }
    }
}

/// drawingCurrentPoint 仅在绘制模式下有效，存储当前鼠标屏幕坐标
var drawingCurrentPoint: CGPoint?
/// 磁吸/网格 snap 辅助状态
var lastSnapActive: Bool = false
var lastSnappedGridOrigin: CGPoint? = nil
```

- [ ] **Step 1.5: 从 `mouseDragged` extension 实现中删除末尾的 stored property 声明**

Task 8 的 `mouseDragged` 末尾有以下几行**不能放在 extension 内**，已移至 Task 2 的 `CanvasViewportView.swift` 主体中声明，此处删除：
```swift
// 删除 — 不能在 extension 中声明 stored property：
var drawingCurrentPoint: CGPoint?
var lastSnapActive: Bool = false
var lastSnappedGridOrigin: CGPoint? = nil
```

- [ ] **Step 2: 在同一 extension 中新增 `applyResizeOnCanvas` 方法**

```swift
/// 在画布层执行 Resize，dx/dy 为屏幕坐标 delta（缩放后）
private func applyResizeOnCanvas(id: UUID, view: BaseNodeView,
                                  edge: BaseNodeView.ResizeEdge,
                                  dx: CGFloat, dy: CGFloat,
                                  startFrame: CGRect) {
    let minW = BaseNodeView.minNodeWidth * zoom
    let minH = BaseNodeView.minNodeHeight * zoom

    var x = startFrame.origin.x
    var y = startFrame.origin.y
    var w = startFrame.width
    var h = startFrame.height

    // startFrame 是屏幕坐标（缩放后），dx/dy 亦为屏幕坐标
    // isFlipped = false：y=0 在底部，dy>0 向上
    switch edge {
    case .right:
        w = max(w + dx, minW)
    case .left:
        let newW = max(w - dx, minW)
        x = startFrame.maxX - newW
        w = newW
    case .bottom:
        let top = y + h
        let newH = max(h - dy, minH)
        y = top - newH
        h = newH
    case .top:
        h = max(h + dy, minH)
    case .bottomLeft:
        let newW = max(w - dx, minW)
        x = startFrame.maxX - newW
        w = newW
        let top = y + h
        let newH = max(h - dy, minH)
        y = top - newH
        h = newH
    case .bottomRight:
        w = max(w + dx, minW)
        let top = y + h
        let newH = max(h - dy, minH)
        y = top - newH
        h = newH
    case .topLeft:
        let newW = max(w - dx, minW)
        x = startFrame.maxX - newW
        w = newW
        h = max(h + dy, minH)
    case .topRight:
        w = max(w + dx, minW)
        h = max(h + dy, minH)
    }

    let newScreenFrame = CGRect(x: x, y: y, width: w, height: h)
    // 同步更新屏幕 frame 和画布坐标缓存
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    view.frame = newScreenFrame
    view.setBoundsSize(CGSize(width: w / zoom, height: h / zoom))
    // 回写 nodeCanvasFrames（画布坐标）
    let canvasOriginPt = screenToCanvas(newScreenFrame.origin)
    nodeCanvasFrames[id] = CGRect(x: canvasOriginPt.x, y: canvasOriginPt.y,
                                   width: w / zoom, height: h / zoom)
    CATransaction.commit()

    if view.isNodeSelected { view.needsLayout = true }
}
```

- [ ] **Step 3: 编译确认**

```bash
cd /Users/zhoulihao/Desktop/maestri/open-maestri && swift build 2>&1 | grep "error:" | head -20
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Canvas/CanvasInteractionHandler.swift
git commit -m "✨ feat(canvas): implement unified mouseDragged with all interaction cases"
```

---

### Task 9: 实现 CanvasInteractionHandler — mouseUp + mouseMoved 光标管理

**Files:**
- Modify: `Sources/Canvas/CanvasInteractionHandler.swift`

- [ ] **Step 1: 新增 `mouseUp` override**

在 `mouseDragged` 方法后追加：

```swift
override func mouseUp(with event: NSEvent) {
    defer {
        interaction = .idle
        lastSnapActive = false
        lastSnappedGridOrigin = nil
    }

    switch interaction {

    case .mayDragNode(let id, _, _, let contentTarget):
        // 没有发生拖动 = 点击
        if let target = contentTarget {
            // mouseDown 已透传，现在补发 mouseUp 完成点击序列
            target.mouseUp(with: event)
        }
        // 单击已在多选集合中的节点 → 收窄为单选
        if selectedNodeIds.count > 1 && selectedNodeIds.contains(id) {
            selectedNodeIds = [id]
        }

    case .draggingNode(let id, _, _):
        dragGuidelines = []
        if let finalFrame = nodeCanvasFrames[id] {
            onNodeDragEnded?(id, finalFrame)
        }

    case .batchDragging(let startFrames, _, _):
        dragGuidelines = []
        var finalFrames: [UUID: CGRect] = [:]
        for id in startFrames.keys {
            if let f = nodeCanvasFrames[id] { finalFrames[id] = f }
        }
        onBatchNodeDragEnded?(finalFrames)

    case .resizingNode(let id, _, _, _):
        NSCursor.arrow.set()
        if let finalFrame = nodeCanvasFrames[id] {
            onNodeResizeEnded?(id, finalFrame)
        }

    case .marquee(let start):
        if let current = marqueeCurrentPoint {
            let rect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            if rect.width > 4 || rect.height > 4 {
                var hitIds = Set<UUID>()
                for (id, view) in nodeViews {
                    if view.frame.intersects(rect) { hitIds.insert(id) }
                }
                selectedNodeIds = hitIds
            }
        }
        marqueeCurrentPoint = nil
        needsDisplay = true

    case .drawing(let start):
        let current = drawingCurrentPoint ?? start
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        if rect.width > 20 && rect.height > 20 {
            let canvasRect = CGRect(
                origin: screenToCanvas(rect.origin),
                size: CGSize(width: rect.width / zoom, height: rect.height / zoom)
            )
            onNodeDrawn?(drawingNodeType, canvasRect)
        } else {
            let defaultSize = defaultNodeSize(for: drawingNodeType)
            let canvasPoint = screenToCanvas(start)
            let canvasRect = CGRect(
                x: canvasPoint.x - defaultSize.width / 2,
                y: canvasPoint.y - defaultSize.height / 2,
                width: defaultSize.width,
                height: defaultSize.height
            )
            onNodeDrawn?(drawingNodeType, canvasRect)
        }
        drawingCurrentPoint = nil
        needsDisplay = true

    case .panCanvas:
        if isSpaceHeld { NSCursor.openHand.set() } else { NSCursor.arrow.set() }

    case .idle, .connecting:
        break
    }
}
```

- [ ] **Step 2: 新增 `mouseMoved` override（光标管理 + 连线工具跟踪）**

```swift
override func mouseMoved(with event: NSEvent) {
    let loc = convert(event.locationInWindow, from: nil)

    // 连线工具：跟踪鼠标位置
    if connectingFromNodeId != nil {
        connectionDragPoint = loc
        needsDisplay = true
    }

    // 光标：根据命中区域设置
    if isSpaceHeld {
        NSCursor.openHand.set()
        return
    }
    switch hitTestCanvas(at: loc) {
    case .nodeResize(_, let edge):
        edge.cursor.set()
    case .nodeHeader:
        NSCursor.arrow.set()
    case .nodeContent, .canvas:
        NSCursor.arrow.set()
    }
}
```

- [ ] **Step 3: 编译确认**

```bash
cd /Users/zhoulihao/Desktop/maestri/open-maestri && swift build 2>&1 | grep "error:" | head -20
```

- [ ] **Step 4: Commit**

```bash
git add Sources/Canvas/CanvasInteractionHandler.swift
git commit -m "✨ feat(canvas): implement mouseUp and mouseMoved cursor management"
```

---

### Task 10: CanvasNodeRenderer — 更新 resize 回调注册，删除 onNodeClicked

**Files:**
- Modify: `Sources/Canvas/CanvasNodeRenderer.swift`

- [ ] **Step 1: 在 `setupNodeDragCallback` 中新增 `onNodeResizeEnded` 注册**

找到 `setupNodeDragCallback` 方法（约第 39 行），在现有回调注册后添加：

```swift
private func setupNodeDragCallback(canvas: CanvasViewportView) {
    canvas.onNodeDragEnded = { [weak self] nodeId, canvasFrame in
        guard let self else { return }
        self.currentWorkspace?.updateNodeFrame(id: nodeId, frame: canvasFrame)
        self.saveWorkspace()
    }
    canvas.onBatchNodeDragEnded = { [weak self] finalFrames in
        guard let self else { return }
        for (nodeId, frame) in finalFrames {
            self.currentWorkspace?.updateNodeFrame(id: nodeId, frame: frame)
        }
        self.saveWorkspace()
    }
    // Resize 结束：持久化新 frame（替换旧的 onFrameChanged 机制）
    canvas.onNodeResizeEnded = { [weak self] nodeId, canvasFrame in
        guard let self else { return }
        self.currentWorkspace?.updateNodeFrame(id: nodeId, frame: canvasFrame)
        self.saveWorkspace()
    }
}
```

- [ ] **Step 2: 在 `addNodeView` 中删除旧的 `onFrameChanged` 注册**

找到约第 214 行的 `onFrameChanged` 注册块：
```swift
// Resize 回写：BaseNodeView.onFrameChanged → workspace.updateNodeFrame
if let baseView = view as? BaseNodeView {
    // ... 整个 onFrameChanged 注册
}
```
整块删除（resize 持久化已改由 `onNodeResizeEnded` 画布回调处理）。

- [ ] **Step 3: 在 `setupLockCallback` 中删除 `onNodeClicked` 注册**

找到约第 657 行：
```swift
nodeView.onNodeClicked = { [weak self, weak nodeView] event in
    // ...
}
```
整块删除（选中逻辑已移入 `CanvasInteractionHandler.updateSelection`）。

- [ ] **Step 4: 删除 `onOptionDragDuplicate` 注册，改为从 CanvasInteractionHandler 直接调用**

由于 `onOptionDragDuplicate` 已从 `BaseNodeView` 删除，需要在 `CanvasInteractionHandler.swift` 的 `mouseDragged` 的 `.mayDragNode → draggingNode` 切换处，以及 `.draggingNode` 处理中，直接读取 nodeView 的 `onDuplicate` 回调。

在 `CanvasInteractionHandler.swift` 的 `.mayDragNode` 超阈值切换为 `.draggingNode` 的代码段之前，添加 Option 键检查：

```swift
// 切换为真正拖动之前检查 Option+拖拽复制
if event.modifierFlags.contains(.option),
   let base = nodeViews[id] as? BaseNodeView {
    interaction = .idle
    base.onDuplicate?()
    return
}
```

- [ ] **Step 5: 全量编译，确认无错误**

```bash
cd /Users/zhoulihao/Desktop/maestri/open-maestri && swift build 2>&1 | tail -5
```

期望：`Build complete!`

- [ ] **Step 6: Commit**

```bash
git add Sources/Canvas/CanvasNodeRenderer.swift Sources/Canvas/CanvasInteractionHandler.swift
git commit -m "♻️ refactor(canvas): update CanvasNodeRenderer — wire onNodeResizeEnded, remove onNodeClicked and onFrameChanged"
```

---

### Task 11: 修复编译错误 — 清理所有残留引用

**Files:**
- Modify: 编译报错的文件（预期：`CanvasViewportView.swift`、`CanvasDragHandler.swift`、各 NodeView）

- [ ] **Step 1: 全量编译，收集所有 error**

```bash
cd /Users/zhoulihao/Desktop/maestri/open-maestri && swift build 2>&1 | grep "error:"
```

- [ ] **Step 2: 逐条修复**

常见错误类型和修复方式：

**`use of unresolved identifier 'draggingNodeId'`**（CanvasViewportView.swift layout 或 updateNodeFrame 中）：
- `updateNodeFrame` 中的 `if draggingNodeId != nil` 改为：
```swift
func updateNodeFrame(id: UUID, canvasFrame: CGRect) {
    guard let view = nodeViews[id] else { return }
    // 拖动/resize 期间不允许外部覆盖被交互节点的 frame
    switch interaction {
    case .draggingNode(let did, _, _) where did == id: return
    case .batchDragging(let frames, _, _) where frames.keys.contains(id): return
    case .resizingNode(let rid, _, _, _) where rid == id: return
    case .mayDragNode(let mid, _, _, _) where mid == id: return
    default: break
    }
    nodeCanvasFrames[id] = canvasFrame
    view.frame = canvasRectToScreen(canvasFrame)
    view.setBoundsSize(canvasFrame.size)
}
```

**`use of unresolved identifier 'isBatchDragging'`**：
- `isBatchDragging` 已不存在，直接删除或改为 `if case .batchDragging = interaction`

**`use of unresolved identifier 'selectionStartPoint'`**（drawSelectionRect 中）：
- 在 `CanvasDragHandler.swift` 的 `drawSelectionRect()` 中，将读取 `selectionStartPoint` 改为读取 `selectionRect` computed property：
```swift
func drawSelectionRect() {
    guard let rect = selectionRect, rect.width > 2 || rect.height > 2 else { return }
    let path = NSBezierPath(rect: rect)
    path.lineWidth = 1.0
    NSColor.systemBlue.withAlphaComponent(0.4).setStroke()
    NSColor.systemBlue.withAlphaComponent(0.08).setFill()
    path.stroke()
    path.fill()
}
```

**`value of type 'BaseNodeView' has no member 'contentEventRouter'`**（FileTreeNodeView 已在 Task 4 修复，若漏掉再处理）

**`value of type 'BaseNodeView' has no member 'isResizing'`**（CanvasViewportView.layout 中旧引用）：
- Task 2 已处理 layout()，若还有残留则删除对应 `base.isResizing` 引用

- [ ] **Step 3: 再次编译确认无 error**

```bash
cd /Users/zhoulihao/Desktop/maestri/open-maestri && swift build 2>&1 | tail -5
```

期望：`Build complete!`

- [ ] **Step 4: Commit**

```bash
git add -u
git commit -m "🐛 fix(canvas): fix all residual compilation errors after interaction refactor"
```

---

### Task 12: 验证滚轮路由在新架构下正确工作

**Files:**
- Modify: `Sources/Canvas/CanvasViewportView.swift`（若需要小调整）

- [ ] **Step 1: 确认 `routeScrollEvent` 中对 `BaseNodeView.contentView` 的引用无变化**

```bash
grep -n "contentView\|findScrollTarget\|routeScrollEvent" /Users/zhoulihao/Desktop/maestri/open-maestri/Sources/Canvas/CanvasViewportView.swift | head -20
```

`routeScrollEvent` 通过 `nodeView.contentView` 做 frame 命中和 `findScrollTarget`，`contentView` 在 `BaseNodeView` 中保留，无需修改。

- [ ] **Step 2: 确认 `routeScrollEvent` 中的选中节点迭代正确（selectedNodeIds 不变）**

```bash
grep -n "selectedNodeIds\|contentView.frame\|findScrollTarget" /Users/zhoulihao/Desktop/maestri/open-maestri/Sources/Canvas/CanvasViewportView.swift | head -20
```

- [ ] **Step 3: 编译 + 基础验证**

```bash
cd /Users/zhoulihao/Desktop/maestri/open-maestri && swift build 2>&1 | tail -3
```

期望：`Build complete!`

- [ ] **Step 4: Commit（如有改动）**

```bash
git add Sources/Canvas/CanvasViewportView.swift
git commit -m "✅ verify(canvas): scroll routing unaffected after interaction refactor"
```

---

### Task 13: 手动验收测试矩阵

这是在 Xcode/应用中的手动验收测试，按照设计文档第八节的测试矩阵逐项验证。**无需代码改动**，仅为验证步骤。

- [ ] **基础交互**
  - 点击画布空白区域 → 清除选中
  - 点击任意节点 Header → 节点高亮选中（蓝色虚线边框）
  - ⌘+点击多个节点 → 多选
  - 再次点击已选中的多选节点之一 → 收窄为单选

- [ ] **节点拖动**
  - 拖动 Header 移动节点（Terminal、Note、FileTree、Portal、Text）
  - 多选后拖动 → 所有选中节点同步移动
  - 拖动时出现磁吸参考线
  - 松手后节点位置持久化（重启 app 后位置不变）

- [ ] **Terminal 内容区交互**
  - 选中 Terminal 节点后，点击内容区 → 键盘输入正常（Terminal 获焦）
  - 选中 Terminal 节点后，在内容区按住鼠标拖动 → 节点随鼠标移动（而非 Terminal 文字选择）
  - 未选中 Terminal 节点时，点击任意区域 → 节点选中，不输入到 Terminal

- [ ] **FileTree/Portal 内容区交互**
  - 选中 FileTree 节点后，内容区上下滚动 → 文件列表滚动（不平移画布）
  - 选中 Portal 节点后，点击内容区 → WebView 响应（导航等）

- [ ] **Resize 8方向**
  - 鼠标移到节点四边 → 光标变为对应方向箭头
  - 拖拽四边 + 四角均可 resize
  - Resize 后节点尺寸持久化

- [ ] **框选**
  - 在空白区域按住拖动 → 出现蓝色框选矩形
  - 松手后与矩形相交的节点被选中

- [ ] **连线工具**
  - L 键激活连线 → 光标变十字
  - 点击节点 A 再点击节点 B → 连线生成

- [ ] **触控板**
  - 双指滑动 → 画布平移（不误触节点拖动）
  - 捏合缩放 → 画布缩放（节点不变形）
  - Space+拖拽 → 画布平移

---

## 自检：Spec 覆盖

| Spec 要求 | 覆盖的 Task |
|-----------|------------|
| 三套状态机合并为单一 CanvasInteraction | Task 1, 2 |
| BaseNodeView 瘦身（删除鼠标事件） | Task 3 |
| ContentEventRouterView 删除 | Task 3 |
| hitTestCanvas 语义化命中测试 | Task 6 |
| mouseDown 统一实现 | Task 7 |
| mouseDragged 统一实现（含 resize） | Task 8 |
| mouseUp 统一实现 | Task 9 |
| mouseMoved 光标管理 | Task 9 |
| NSScroller 豁免（不触发节点拖动） | Task 6（hitTestCanvas 返回 .canvas） |
| Terminal mouseDown 立即透传 | Task 7（.nodeContent 分支） |
| 超阈值后取消透传，切换为拖动 | Task 8（.mayDragNode 分支） |
| onNodeResizeEnded 持久化 | Task 10 |
| onNodeClicked 删除（逻辑上移） | Task 10 |
| FileTreeNodeView contentEventRouter 清理 | Task 4 |
| 滚轮路由不受影响 | Task 12 |
| 全量编译通过 | Task 11 |
| 手动验收 | Task 13 |
