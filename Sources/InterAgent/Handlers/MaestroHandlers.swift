import Foundation
import OSLog

final class MaestroHandlers {
    static let shared = MaestroHandlers()
    private let logger = Logger.make(category: "MaestroHandlers")
    private init() {}

    func handleAsync(args: [String], terminalId: UUID?) async -> String {
        guard let command = args.first else { return "error: empty command" }
        switch command {
        case "recruit": return await handleRecruitAsync(args: args, fromTerminalId: terminalId)
        case "dismiss": return await handleDismissAsync(args: args, fromTerminalId: terminalId)
        case "connect": return await handleConnectAsync(args: args, fromTerminalId: terminalId)
        case "role":    return await handleRoleAsync(args: args, fromTerminalId: terminalId)
        case "preset":  return await handlePresetAsync(args: args)
        default: return "error: unknown maestro command '\(command)'"
        }
    }

    // MARK: - recruit

    @MainActor
    private func handleRecruitAsync(args: [String], fromTerminalId: UUID?) async -> String {
        guard args.count >= 2 else {
            return "error: usage: omaestri recruit \"Name\" [--preset <agentType>] [--role <roleName>] [--command <cmd>]"
        }
        let recruitName = args[1]
        var presetIdentifier = "generic_shell"
        var roleName: String? = nil
        var customCommand: String? = nil
        var i = 2
        while i < args.count {
            switch args[i] {
            case "--preset"  where i + 1 < args.count: presetIdentifier = args[i+1]; i += 2
            case "--role"    where i + 1 < args.count: roleName         = args[i+1]; i += 2
            case "--command" where i + 1 < args.count: customCommand    = args[i+1]; i += 2
            default: i += 1
            }
        }
        let tm = TerminalManager.shared
        let cm = ConnectionManager.shared
        let prefs = PersistenceManager.shared.loadPreferencesSync()

        guard let maestroId = fromTerminalId, let maestroSession = tm.terminals[maestroId] else {
            return "error: recruit can only be called from a Maestro terminal"
        }

        // 验证 isManager 字段（fail-closed：任何加载失败均拒绝 recruit）
        guard let wsId = (try? PersistenceManager.shared.loadAppState())?.activeWorkspaceId,
              let doc = try? PersistenceManager.shared.loadWorkspace(id: wsId),
              let maestroNode = doc.payload.nodes.first(where: { $0.id == maestroId }),
              case .terminal(let maestroTc) = maestroNode.content,
              maestroTc.isManager
        else {
            return "error: this terminal is not in Maestro mode. Enable Maestro mode when creating the terminal."
        }

        // 查找预设（按 agentType 或 name 匹配）
        let preset = prefs.agentPresets.first {
            $0.agentType == presetIdentifier ||
            $0.name.lowercased() == presetIdentifier.lowercased() ||
            $0.command == presetIdentifier
        } ?? AgentPreset(
            id: UUID(), name: recruitName,
            command: customCommand ?? presetIdentifier,
            icon: "terminal", agentType: "generic_shell",
            color: "#8E8E93", isActive: true, isBuiltIn: false
        )

        // 如有 customCommand，覆盖 preset command
        var effectivePreset = preset
        if let cmd = customCommand { effectivePreset.command = cmd }

        // 查找角色
        let role = roleName.flatMap { rn in
            prefs.rolePresets.first { $0.name.lowercased() == rn.lowercased() }
        }

        let recruitId = UUID()
        let activeWsId = (try? PersistenceManager.shared.loadAppState())?.activeWorkspaceId
        _ = tm.createTerminal(
            id: recruitId,
            command: effectivePreset.command,
            workingDirectory: maestroSession.workingDirectory,
            workspaceId: activeWsId,
            roleName: role?.name,
            agentType: effectivePreset.agentType
        )
        tm.writeLine(to: recruitId, text: "export OMAESTRI_AGENT_NAME=\"\(recruitName)\"")
        // 同步到 TerminalSession 供 ListHandler 使用
        tm.terminals[recruitId]?.agentName = recruitName
        let conn = cm.connectTerminals(idA: maestroId, idB: recruitId, serverPort: InterAgentServer.shared.port)

        // 在画布上创建节点并自动布局在 Maestro 下方
        // 通过 NotificationCenter 通知主线程（AppState）更新工作区节点
        let maestroIdCopy = maestroId
        let connCopy = conn
        var tc = TerminalContent(
            name: recruitName,
            agentType: effectivePreset.agentType,
            command: effectivePreset.command,
            workingDirectory: maestroSession.workingDirectory
        )
        tc.id = recruitId

        NotificationCenter.default.post(
            name: .maestroRecruited,
            object: nil,
            userInfo: [
                "maestroId": maestroIdCopy,
                "recruitNode": CanvasNode(id: recruitId, frame: .zero, content: .terminal(tc)),
                "connection": connCopy,
                "connectedIds": cm.connectedNodeIds(for: maestroId),
            ]
        )

        logger.info("Recruited '\(recruitName)' (preset: \(effectivePreset.agentType))")
        var msg = "Recruited '\(recruitName)' with preset '\(effectivePreset.name)'"
        if let role { msg += " and role '\(role.name)'" }
        return msg
    }

    // 节点位置计算已移至 ContentView.handleMaestroRecruited（主线程，可访问 workspace）

    // MARK: - dismiss

    @MainActor
    private func handleDismissAsync(args: [String], fromTerminalId: UUID?) async -> String {
        guard args.count >= 2 else { return "error: usage: omaestri dismiss \"Name\"" }
        let targetName = args[1]
        guard let maestroId = fromTerminalId else { return "error: missing terminal ID" }
        let tm = TerminalManager.shared
        let cm = ConnectionManager.shared
        let connectedIds = cm.connectedNodeIds(for: maestroId)
        let lower = targetName.lowercased()
        guard let target = tm.terminals.values.first(where: {
            connectedIds.contains($0.id) &&
            ($0.agentName?.lowercased().contains(lower) == true ||
             $0.command.lowercased().contains(lower) ||
             ($0.roleName ?? "").lowercased().contains(lower) ||
             $0.id.uuidString.prefix(8) == targetName.prefix(8))
        }) else { return "error: agent '\(targetName)' not found among connected agents" }
        cm.disconnectAll(involvedNode: target.id)
        tm.removeTerminal(id: target.id)
        return "Dismissed '\(targetName)'"
    }

    // MARK: - connect

    @MainActor
    private func handleConnectAsync(args: [String], fromTerminalId: UUID?) async -> String {
        guard args.count >= 3 else { return "error: usage: omaestri connect \"From\" \"To\"" }
        let (fromName, toName) = (args[1], args[2])
        let tm = TerminalManager.shared
        let cm = ConnectionManager.shared
        guard let fromS = tm.terminals.values.first(where: {
            $0.command.lowercased().contains(fromName.lowercased()) ||
            ($0.roleName ?? "").lowercased().contains(fromName.lowercased())
        }) else { return "error: '\(fromName)' not found" }
        guard let toS = tm.terminals.values.first(where: {
            $0.command.lowercased().contains(toName.lowercased()) ||
            ($0.roleName ?? "").lowercased().contains(toName.lowercased())
        }) else { return "error: '\(toName)' not found" }
        _ = cm.connectTerminals(idA: fromS.id, idB: toS.id, serverPort: InterAgentServer.shared.port)
        return "Connected '\(fromName)' ↔ '\(toName)'"
    }

    // MARK: - role

    @MainActor
    private func handleRoleAsync(args: [String], fromTerminalId: UUID?) async -> String {
        guard args.count >= 2 else {
            return "error: usage: omaestri role <list|create|show|edit|write|assign> [args...]"
        }
        switch args[1] {
        case "list":
            let prefs = PersistenceManager.shared.loadPreferencesSync()
            if prefs.rolePresets.isEmpty {
                return "No roles defined. Create one: omaestri role create \"RoleName\" \"Role instructions\""
            }
            return prefs.rolePresets.map { "  - \($0.name): \($0.prompt.prefix(60))..." }.joined(separator: "\n")

        case "create":
            guard args.count >= 4 else {
                return "error: usage: omaestri role create \"RoleName\" \"Role instructions\""
            }
            let (roleName, rolePrompt) = (args[2], args[3])
            var prefs = PersistenceManager.shared.loadPreferencesSync()
            let newRole = RolePreset(id: UUID(), name: roleName, prompt: rolePrompt, color: "#007AFF", icon: "person.fill")
            prefs.rolePresets.append(newRole)
            try? PersistenceManager.shared.savePreferences(prefs)
            return "Role '\(roleName)' created"

        case "show":
            guard args.count >= 3 else {
                return "error: usage: omaestri role show \"RoleName\""
            }
            let roleName = args[2]
            let prefs = PersistenceManager.shared.loadPreferencesSync()
            guard let role = prefs.rolePresets.first(where: { $0.name.lowercased() == roleName.lowercased() }) else {
                return "error: role '\(roleName)' not found"
            }
            return "Name: \(role.name)\nPrompt: \(role.prompt)"

        case "edit", "write":
            guard args.count >= 4 else {
                return "error: usage: omaestri role \(args[1]) \"RoleName\" --prompt \"...\""
            }
            let roleName = args[2]
            var prefs = PersistenceManager.shared.loadPreferencesSync()
            guard let idx = prefs.rolePresets.firstIndex(where: { $0.name.lowercased() == roleName.lowercased() }) else {
                return "error: role '\(roleName)' not found"
            }
            var i = 3
            while i < args.count {
                if args[i] == "--prompt" && i + 1 < args.count {
                    prefs.rolePresets[idx].prompt = args[i+1]
                    i += 2
                } else { i += 1 }
            }
            try? PersistenceManager.shared.savePreferences(prefs)
            return "Role '\(roleName)' updated"

        case "assign":
            guard args.count >= 4 else {
                return "error: usage: omaestri role assign \"AgentName\" \"RoleName\" (use --none to clear)"
            }
            let (agentName, roleName) = (args[2], args[3])
            let tm = TerminalManager.shared
            guard let session = tm.terminals.values.first(where: {
                $0.command.lowercased().contains(agentName.lowercased())
            }) else { return "error: agent '\(agentName)' not found" }

            if roleName == "--none" {
                // 清除角色：重启到原始目录
                return "Role cleared for '\(agentName)' (takes effect on next restart)"
            }

            let prefs = PersistenceManager.shared.loadPreferencesSync()
            guard let role = prefs.rolePresets.first(where: { $0.name.lowercased() == roleName.lowercased() }) else {
                return "error: role '\(roleName)' not found"
            }
            // 注入角色文件
            RoleInjector.shared.prepareRoleDirectory(
                roleId: role.id,
                rolePrompt: role.prompt,
                workingDirectory: session.workingDirectory
            )
            return "Role '\(roleName)' assigned to '\(agentName)' (takes effect on next restart)"

        default:
            return "error: unknown role subcommand '\(args[1])'. Valid: list|create|show|edit|write|assign"
        }
    }

    // MARK: - preset

    @MainActor
    private func handlePresetAsync(args: [String]) async -> String {
        guard args.count >= 2 else {
            return "error: usage: omaestri preset <list>"
        }
        switch args[1] {
        case "list":
            let prefs = PersistenceManager.shared.loadPreferencesSync()
            let active = prefs.agentPresets.filter { $0.isActive }
            return active.map { "  - \($0.agentType): \($0.name) (\($0.command))" }.joined(separator: "\n")
        default:
            return "error: unknown preset subcommand '\(args[1])'. Valid: list"
        }
    }
}
