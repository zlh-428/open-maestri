import AppKit

// MARK: - Terminal Context Menu Handlers

extension CanvasNodeRenderer {

    /// 清除缓冲区：向终端发送 clear 命令（模拟 ⌘K 行为）
    func handleClearBuffer(terminalId: UUID) {
        guard let ws = currentWorkspace,
              let node = ws.nodes.first(where: { $0.id == terminalId }),
              case .terminal(let tc) = node.content else { return }
        // 通过 provider 直接清除终端屏幕
        if let provider = TerminalManager.shared.providers[tc.id],
           let tv = provider.terminalView {
            // 发送 ANSI 清屏 + 重置光标（等同于 clear 命令效果）
            tv.getTerminal().resetToInitialState()
            tv.getTerminal().updateFullScreen()
        }
    }

    /// 重新加载终端：重启 PTY 进程
    func handleReloadTerminal(terminalId: UUID) {
        guard let ws = currentWorkspace,
              let node = ws.nodes.first(where: { $0.id == terminalId }),
              case .terminal(let tc) = node.content else { return }
        if let provider = TerminalManager.shared.providers[tc.id] {
            provider.restartProcess(command: tc.command, workingDirectory: tc.workingDirectory)
        }
    }

    /// 拷贝终端可见内容到剪贴板
    func handleCopyTerminal(terminalId: UUID) {
        guard let ws = currentWorkspace,
              let node = ws.nodes.first(where: { $0.id == terminalId }),
              case .terminal(let tc) = node.content else { return }
        if let session = TerminalManager.shared.terminals[tc.id] {
            let text = session.recentOutput(lines: 200)
            if !text.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }

    /// 切换监控活动
    func handleToggleMonitor(terminalId: UUID) {
        guard let ws = currentWorkspace,
              let idx = ws.nodes.firstIndex(where: { $0.id == terminalId }),
              case .terminal(var tc) = ws.nodes[idx].content else { return }
        tc.monitorWithOmbro.toggle()
        ws.nodes[idx].content = .terminal(tc)
        NotificationCenter.default.post(
            name: .canvasNodeContentChanged,
            object: nil,
            userInfo: ["nodeId": terminalId, "content": NodeContent.terminal(tc)]
        )
        saveWorkspace()
    }
}
