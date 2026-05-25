import AppKit

// MARK: - Context Menu

extension CanvasViewportView {

    /// 右键菜单：在 AppKit 层处理，避免 SwiftUI allowsHitTesting(false) 阻断问题
    /// 根据节点类型动态构建菜单项（对标 Maestri 产品行为）：
    /// - Terminal: Duplicate → Edit Terminal → Assign Role / Enable Maestro → Connect → Delete
    /// - Note: Duplicate → Rename → Connect → Delete
    /// - Portal: Duplicate → Connect → Delete
    /// - FileTree: Duplicate → Lock → Delete（使用节点内部工具栏，菜单精简）
    /// - Text/Drawing: Duplicate → Lock → Delete
    override func menu(for event: NSEvent) -> NSMenu? {
        let loc = convert(event.locationInWindow, from: nil)
        let hit = hitTestCanvas(at: loc)

        let nodeId: UUID?
        switch hit {
        case .nodeHeader(let id), .nodeFooter(let id), .nodeContent(let id, _), .nodeResize(let id, _):
            nodeId = id
        case .canvas:
            nodeId = nil
        }

        guard let id = nodeId else {
            // 检查是否右键点击了连接线（连接线层在节点层下方，需在此处手动检测）
            if let overlay = connectionOverlayView {
                let overlayPoint = overlay.convert(event.locationInWindow, from: nil)
                if let connId = overlay.connectionId(at: overlayPoint) {
                    return buildConnectionMenu(connectionId: connId)
                }
            }
            return buildCanvasBlankMenu(at: loc)
        }
        guard let node = currentNodes.first(where: { $0.id == id }) else { return super.menu(for: event) }

        let menu = NSMenu()

        switch node.content {
        case .terminal(let tc):
            // 编辑
            menu.addItem(menuItem("canvas.context.edit_terminal".localized, action: #selector(contextMenuEditTerminal(_:)), id: id, icon: "slider.horizontal.3"))
            menu.addItem(NSMenuItem.separator())
            // 清除缓冲区
            menu.addItem(menuItem("canvas.context.clear_buffer".localized, action: #selector(contextMenuClearBuffer(_:)), id: id, icon: "xmark.circle", keyEquivalent: "k"))
            // 重新加载
            menu.addItem(menuItem("canvas.context.reload_terminal".localized, action: #selector(contextMenuReloadTerminal(_:)), id: id, icon: "arrow.clockwise"))
            menu.addItem(NSMenuItem.separator())
            // 拷贝
            menu.addItem(menuItem("canvas.context.copy_terminal".localized, action: #selector(contextMenuCopyTerminal(_:)), id: id, icon: "doc.on.doc", keyEquivalent: "c"))
            // 监控活动
            let monitorTitle = tc.monitorWithOmbro ? "canvas.context.disable_monitor".localized : "canvas.context.enable_monitor".localized
            menu.addItem(menuItem(monitorTitle, action: #selector(contextMenuToggleMonitor(_:)), id: id, icon: "eye"))
            menu.addItem(NSMenuItem.separator())
            // 复制（节点复制）
            menu.addItem(menuItem("canvas.context.duplicate".localized, action: #selector(contextMenuDuplicate(_:)), id: id, icon: "plus.square.on.square"))
            // 锁定
            let lockTitle = node.isLocked ? "menu.unlock".localized : "menu.lock".localized
            let lockIcon = node.isLocked ? "lock.open" : "lock"
            menu.addItem(menuItem(lockTitle, action: #selector(contextMenuLockToggle(_:)), id: id, icon: lockIcon))
            menu.addItem(NSMenuItem.separator())
            // 删除
            menu.addItem(destructiveItem("canvas.context.delete".localized, action: #selector(contextMenuClose(_:)), id: id, icon: "trash"))

        case .stickyNote:
            menu.addItem(menuItem("canvas.context.duplicate".localized, action: #selector(contextMenuDuplicate(_:)), id: id))
            menu.addItem(menuItem("canvas.context.rename".localized, action: #selector(contextMenuRename(_:)), id: id))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(menuItem("canvas.context.connect".localized, action: #selector(contextMenuConnect(_:)), id: id))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(destructiveItem("canvas.context.delete".localized, action: #selector(contextMenuClose(_:)), id: id))

        case .portal:
            menu.addItem(menuItem("canvas.context.duplicate".localized, action: #selector(contextMenuDuplicate(_:)), id: id))
            menu.addItem(menuItem("canvas.context.rename".localized, action: #selector(contextMenuRename(_:)), id: id))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(menuItem("canvas.context.connect".localized, action: #selector(contextMenuConnect(_:)), id: id))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(destructiveItem("canvas.context.delete".localized, action: #selector(contextMenuClose(_:)), id: id))

        case .fileTree:
            menu.addItem(menuItem("canvas.context.duplicate".localized, action: #selector(contextMenuDuplicate(_:)), id: id))
            menu.addItem(menuItem("canvas.context.rename".localized, action: #selector(contextMenuRename(_:)), id: id))
            let lockTitle = node.isLocked ? "menu.unlock".localized : "menu.lock".localized
            menu.addItem(menuItem(lockTitle, action: #selector(contextMenuLockToggle(_:)), id: id))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(destructiveItem("canvas.context.delete".localized, action: #selector(contextMenuClose(_:)), id: id))

        case .text, .shape:
            menu.addItem(menuItem("canvas.context.duplicate".localized, action: #selector(contextMenuDuplicate(_:)), id: id))
            let lockTitle = node.isLocked ? "menu.unlock".localized : "menu.lock".localized
            menu.addItem(menuItem(lockTitle, action: #selector(contextMenuLockToggle(_:)), id: id))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(destructiveItem("canvas.context.delete".localized, action: #selector(contextMenuClose(_:)), id: id))
        }

        return menu
    }

    // MARK: - Connection Context Menu

    /// 构建连接线右键菜单（删除连接）
    private func buildConnectionMenu(connectionId: UUID) -> NSMenu {
        let menu = NSMenu()
        let deleteTitle = "connection.delete".localized
        let deleteItem = NSMenuItem(title: deleteTitle, action: #selector(contextMenuDeleteConnection(_:)), keyEquivalent: "")
        let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemRed]
        deleteItem.attributedTitle = NSAttributedString(string: deleteTitle, attributes: attrs)
        deleteItem.target = self
        deleteItem.representedObject = connectionId
        menu.addItem(deleteItem)
        return menu
    }

    @objc private func contextMenuDeleteConnection(_ sender: NSMenuItem) {
        guard let connectionId = sender.representedObject as? UUID else { return }
        connectionOverlayView?.onDeleteConnection?(connectionId)
    }

    // MARK: - Canvas Blank Area Context Menu

    /// 构建画布空白区域右键菜单（添加 → 终端/便签/附件/文件树/门户/文本 + 粘贴）
    private func buildCanvasBlankMenu(at screenPoint: CGPoint) -> NSMenu {
        let canvasPoint = screenToCanvas(screenPoint)
        let menu = NSMenu()

        // 「添加」子菜单
        let addItem = NSMenuItem(title: "canvas.context.add".localized, action: nil, keyEquivalent: "")
        addItem.image = NSImage(systemSymbolName: "plus.square", accessibilityDescription: nil)
        let addSubmenu = NSMenu()

        // 终端子菜单（含 Agent 预设列表）
        let terminalItem = NSMenuItem(title: "canvas.context.add.terminal".localized, action: nil, keyEquivalent: "")
        terminalItem.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
        let terminalSubmenu = NSMenu()

        for (index, preset) in agentPresets.enumerated() where preset.isActive {
            let presetItem = NSMenuItem(title: preset.name, action: #selector(contextMenuCreateTerminalPreset(_:)), keyEquivalent: "")
            presetItem.target = self
            presetItem.tag = index
            presetItem.representedObject = NSValue(point: NSPoint(x: canvasPoint.x, y: canvasPoint.y))
            if let iconName = presetIconName(for: preset) {
                presetItem.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            }
            terminalSubmenu.addItem(presetItem)
        }
        terminalItem.submenu = terminalSubmenu
        addSubmenu.addItem(terminalItem)

        // 便签
        let noteItem = NSMenuItem(title: "canvas.context.add.note".localized, action: #selector(contextMenuCreateNote(_:)), keyEquivalent: "")
        noteItem.target = self
        noteItem.image = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: nil)
        noteItem.representedObject = NSValue(point: NSPoint(x: canvasPoint.x, y: canvasPoint.y))
        addSubmenu.addItem(noteItem)

        // 附件（LinkedFile）
        let attachmentItem = NSMenuItem(title: "canvas.context.add.attachment".localized, action: #selector(contextMenuCreateAttachment(_:)), keyEquivalent: "")
        attachmentItem.target = self
        attachmentItem.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: nil)
        attachmentItem.representedObject = NSValue(point: NSPoint(x: canvasPoint.x, y: canvasPoint.y))
        addSubmenu.addItem(attachmentItem)

        // 文件树
        let fileTreeItem = NSMenuItem(title: "canvas.context.add.filetree".localized, action: #selector(contextMenuCreateFileTree(_:)), keyEquivalent: "")
        fileTreeItem.target = self
        fileTreeItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        fileTreeItem.representedObject = NSValue(point: NSPoint(x: canvasPoint.x, y: canvasPoint.y))
        addSubmenu.addItem(fileTreeItem)

        // 门户
        let portalItem = NSMenuItem(title: "canvas.context.add.portal".localized, action: #selector(contextMenuCreatePortal(_:)), keyEquivalent: "")
        portalItem.target = self
        portalItem.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        portalItem.representedObject = NSValue(point: NSPoint(x: canvasPoint.x, y: canvasPoint.y))
        addSubmenu.addItem(portalItem)

        // 文本
        let textItem = NSMenuItem(title: "canvas.context.add.text".localized, action: #selector(contextMenuCreateText(_:)), keyEquivalent: "")
        textItem.target = self
        textItem.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)
        textItem.representedObject = NSValue(point: NSPoint(x: canvasPoint.x, y: canvasPoint.y))
        addSubmenu.addItem(textItem)

        addItem.submenu = addSubmenu
        menu.addItem(addItem)

        // 粘贴
        let pasteItem = NSMenuItem(title: "canvas.context.paste".localized, action: #selector(contextMenuPaste(_:)), keyEquivalent: "")
        pasteItem.target = self
        pasteItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        pasteItem.representedObject = NSValue(point: NSPoint(x: canvasPoint.x, y: canvasPoint.y))
        // 仅在剪贴板有内容时可用
        pasteItem.isEnabled = NSPasteboard.general.string(forType: .string) != nil
        menu.addItem(pasteItem)

        return menu
    }

    /// 根据 AgentPreset 获取 SF Symbol 图标名
    private func presetIconName(for preset: AgentPreset) -> String? {
        switch preset.agentType {
        case "claude_code": return "seal"
        case "codex": return "brain"
        case "gemini_cli": return "sparkle"
        case "open_code": return "rectangle.portrait"
        case "generic_shell": return "terminal"
        default: return preset.icon.isEmpty ? nil : preset.icon
        }
    }

    // MARK: - Canvas Blank Area Context Menu Actions

    @objc private func contextMenuCreateTerminalPreset(_ sender: NSMenuItem) {
        guard let point = (sender.representedObject as? NSValue)?.pointValue else { return }
        let canvasPoint = CGPoint(x: point.x, y: point.y)
        onCanvasContextCreateTerminal?(sender.tag, canvasPoint)
    }

    @objc private func contextMenuCreateNote(_ sender: NSMenuItem) {
        guard let point = (sender.representedObject as? NSValue)?.pointValue else { return }
        let canvasPoint = CGPoint(x: point.x, y: point.y)
        onCanvasContextCreateNode?("stickyNote", canvasPoint)
    }

    @objc private func contextMenuCreateAttachment(_ sender: NSMenuItem) {
        guard let point = (sender.representedObject as? NSValue)?.pointValue else { return }
        let canvasPoint = CGPoint(x: point.x, y: point.y)
        onCanvasContextCreateNode?("linkedFile", canvasPoint)
    }

    @objc private func contextMenuCreateFileTree(_ sender: NSMenuItem) {
        guard let point = (sender.representedObject as? NSValue)?.pointValue else { return }
        let canvasPoint = CGPoint(x: point.x, y: point.y)
        onCanvasContextCreateNode?("fileTree", canvasPoint)
    }

    @objc private func contextMenuCreatePortal(_ sender: NSMenuItem) {
        guard let point = (sender.representedObject as? NSValue)?.pointValue else { return }
        let canvasPoint = CGPoint(x: point.x, y: point.y)
        onCanvasContextCreateNode?("portal", canvasPoint)
    }

    @objc private func contextMenuCreateText(_ sender: NSMenuItem) {
        guard let point = (sender.representedObject as? NSValue)?.pointValue else { return }
        let canvasPoint = CGPoint(x: point.x, y: point.y)
        onCanvasContextCreateNode?("text", canvasPoint)
    }

    @objc private func contextMenuPaste(_ sender: NSMenuItem) {
        guard let point = (sender.representedObject as? NSValue)?.pointValue else { return }
        let canvasPoint = CGPoint(x: point.x, y: point.y)
        onCanvasContextPaste?(canvasPoint)
    }

    // MARK: - Menu Item Helpers

    private func menuItem(_ title: String, action: Selector, id: UUID, icon: String? = nil, keyEquivalent: String = "", modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers.isEmpty && !keyEquivalent.isEmpty ? [.command] : modifiers
        item.representedObject = id
        item.target = self
        if let icon, let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            item.image = img
        }
        return item
    }

    private func destructiveItem(_ title: String, action: Selector, id: UUID, icon: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.representedObject = id
        item.target = self
        if let icon, let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            item.image = img
        }
        return item
    }

    // MARK: - Context Menu Actions

    @objc private func contextMenuRename(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onContextMenuRename?(id)
    }

    @objc private func contextMenuDuplicate(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onDuplicateNode?(id)
    }

    @objc private func contextMenuLockToggle(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onContextMenuLockToggle?(id)
    }

    @objc private func contextMenuClose(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onContextMenuClose?(id)
    }

    @objc private func contextMenuEditTerminal(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onContextMenuEditTerminal?(id)
    }

    @objc private func contextMenuConnect(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onContextMenuConnect?(id)
    }

    @objc private func contextMenuAssignRole(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onContextMenuAssignRole?(id)
    }

    @objc private func contextMenuToggleMaestro(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onContextMenuToggleMaestro?(id)
    }

    @objc private func contextMenuClearBuffer(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onContextMenuClearBuffer?(id)
    }

    @objc private func contextMenuReloadTerminal(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onContextMenuReloadTerminal?(id)
    }

    @objc private func contextMenuCopyTerminal(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onContextMenuCopyTerminal?(id)
    }

    @objc private func contextMenuToggleMonitor(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onContextMenuToggleMonitor?(id)
    }
}
