import Foundation
import CoreGraphics

/// 用户偏好设置，持久化到 ~/.open-maestri/preferences.json（schemaVersion:1）
struct Preferences: Codable, Equatable {
    var schemaVersion: Int
    var agentPresets: [AgentPreset]
    var rolePresets: [RolePreset]
    var skillPaths: [SkillPath]
    var terminalFontFamily: String
    var terminalFontSize: CGFloat
    var terminalTheme: String           // "system"|"dark"|"light"|"dracula"|"solarized-dark"|"solarized-light"|"nord"|"one-dark"|"tokyo-night"
    var canvasBackground: String        // "dotGrid" | "solid" | "transparent"
    var defaultNoteColor: String
    var preferredIDE: String            // "cursor" | "vscode" | "xcode"
    var language: String                // "en" | "zh-Hans" — 应用界面语言
    var shortcuts: ShortcutConfig
    var sshEnabled: Bool
    var sshTunnelPort: Int
    var sshHost: String
    var sshUser: String
    var sshPort: Int
    var sshScriptPath: String
    var sshAddToPath: Bool
    var metalRendererEnabled: Bool
    var scrollbackMemoryLimit: Bool     // 是否限制每个终端的 scrollback 内存
    var optionAsMeta: Bool              // 将 Option 用作 Meta 键
    var autosaveIntervalSeconds: Int    // 自动保存间隔（秒），与 Maestri preferences 格式对齐

    init() {
        self.schemaVersion = 1
        self.agentPresets = AgentPreset.defaults
        self.rolePresets = []
        self.skillPaths = SkillPath.defaults
        self.terminalFontFamily = Constants.defaultFontFamily
        self.terminalFontSize = Constants.defaultFontSize
        self.terminalTheme = "dark"
        self.canvasBackground = "dotGrid"
        self.defaultNoteColor = Constants.noteDefaultColor
        self.preferredIDE = "cursor"
        self.language = "en"
        self.shortcuts = ShortcutConfig()
        self.sshEnabled = false
        self.sshTunnelPort = 7433
        self.sshHost = ""
        self.sshUser = ""
        self.sshPort = 22
        self.sshScriptPath = "~/.local/bin/omaestri"
        self.sshAddToPath = true
        self.metalRendererEnabled = true
        self.scrollbackMemoryLimit = false
        self.optionAsMeta = false
        self.autosaveIntervalSeconds = 30
    }

    /// 自定义解码：新增字段使用默认值，兼容旧版 JSON
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        agentPresets = try container.decodeIfPresent([AgentPreset].self, forKey: .agentPresets) ?? AgentPreset.defaults
        rolePresets = try container.decodeIfPresent([RolePreset].self, forKey: .rolePresets) ?? []
        skillPaths = try container.decodeIfPresent([SkillPath].self, forKey: .skillPaths) ?? SkillPath.defaults
        terminalFontFamily = try container.decodeIfPresent(String.self, forKey: .terminalFontFamily) ?? Constants.defaultFontFamily
        terminalFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .terminalFontSize) ?? Constants.defaultFontSize
        terminalTheme = try container.decodeIfPresent(String.self, forKey: .terminalTheme) ?? "dark"
        canvasBackground = try container.decodeIfPresent(String.self, forKey: .canvasBackground) ?? "dotGrid"
        defaultNoteColor = try container.decodeIfPresent(String.self, forKey: .defaultNoteColor) ?? Constants.noteDefaultColor
        preferredIDE = try container.decodeIfPresent(String.self, forKey: .preferredIDE) ?? "cursor"
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
        shortcuts = try container.decodeIfPresent(ShortcutConfig.self, forKey: .shortcuts) ?? ShortcutConfig()
        sshEnabled = try container.decodeIfPresent(Bool.self, forKey: .sshEnabled) ?? false
        sshTunnelPort = try container.decodeIfPresent(Int.self, forKey: .sshTunnelPort) ?? 7433
        sshHost = try container.decodeIfPresent(String.self, forKey: .sshHost) ?? ""
        sshUser = try container.decodeIfPresent(String.self, forKey: .sshUser) ?? ""
        sshPort = try container.decodeIfPresent(Int.self, forKey: .sshPort) ?? 22
        sshScriptPath = try container.decodeIfPresent(String.self, forKey: .sshScriptPath) ?? "~/.local/bin/omaestri"
        sshAddToPath = try container.decodeIfPresent(Bool.self, forKey: .sshAddToPath) ?? true
        metalRendererEnabled = try container.decodeIfPresent(Bool.self, forKey: .metalRendererEnabled) ?? true
        scrollbackMemoryLimit = try container.decodeIfPresent(Bool.self, forKey: .scrollbackMemoryLimit) ?? false
        optionAsMeta = try container.decodeIfPresent(Bool.self, forKey: .optionAsMeta) ?? false
        autosaveIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .autosaveIntervalSeconds) ?? 30
    }
}

/// Agent 预设配置（与 Maestri agentPresets 格式一致）
struct AgentPreset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var command: String
    var icon: String            // SF Symbol 名称
    var agentType: String       // "claude_code" | "codex" | "gemini_cli" | "open_code" | "generic_shell"
    var color: String           // hex
    var isActive: Bool          // 是否在 Terminal 创建 sheet 中显示
    var isBuiltIn: Bool

    static let defaults: [AgentPreset] = [
        AgentPreset(id: UUID(), name: "Claude Code", command: "claude",    icon: "seal",                           agentType: "claude_code",    color: "#007AFF", isActive: true, isBuiltIn: true),
        AgentPreset(id: UUID(), name: "Codex",       command: "codex",     icon: "brain",                          agentType: "codex",          color: "#5856D6", isActive: true, isBuiltIn: true),
        AgentPreset(id: UUID(), name: "Gemini CLI",  command: "gemini",    icon: "sparkle",                        agentType: "gemini_cli",     color: "#34C759", isActive: true, isBuiltIn: true),
        AgentPreset(id: UUID(), name: "OpenCode",    command: "opencode",  icon: "rectangle.portrait",             agentType: "open_code",      color: "#FF9500", isActive: true, isBuiltIn: true),
        AgentPreset(id: UUID(), name: "Shell",       command: "bash",      icon: "terminal",                       agentType: "generic_shell",  color: "#8E8E93", isActive: true, isBuiltIn: true),
    ]
}

/// 角色预设
struct RolePreset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var prompt: String
    var color: String           // hex
    var icon: String            // SF Symbol 名称
}

/// CLI 技能路径配置
struct SkillPath: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String            // 显示名称，如 "Claude Code"
    var path: String            // 技能目录路径，如 "~/.claude/skills"
    var icon: String            // SF Symbol 名称
    var isActive: Bool          // 是否启用
    var isBuiltIn: Bool         // 是否为内置项（内置项不可删除）

    static let defaults: [SkillPath] = [
        SkillPath(id: UUID(), name: "Claude Code",  path: "~/.claude/skills",                   icon: "gearshape",     isActive: true, isBuiltIn: true),
        SkillPath(id: UUID(), name: "Agent Skills", path: "~/.agents/skills",                   icon: "doc.text",      isActive: true, isBuiltIn: true),
        SkillPath(id: UUID(), name: "Hermes",       path: "~/.hermes/skills",                   icon: "paperplane",    isActive: true, isBuiltIn: true),
        SkillPath(id: UUID(), name: "Antigravity",  path: "~/.gemini/antigravity-cli/skills",   icon: "sparkle",       isActive: true, isBuiltIn: true),
    ]
}

/// 快捷键配置（Maestri preferences.json shortcuts 对象格式）
struct ShortcutConfig: Codable, Equatable {
    /// 用户自定义快捷键（actionId → 快捷键字符串，覆盖默认值）
    var customKeys: [String: String] = [:]
    var nodeJumpModifier: KeyBinding
    var connectShortcut: KeyBinding
    var nextTerminalShortcut: KeyBinding
    var prevTerminalShortcut: KeyBinding
    var nextWorkspaceShortcut: KeyBinding
    var prevWorkspaceShortcut: KeyBinding
    var workspaceJumpModifier: KeyBinding
    var zoomToggleShortcut: KeyBinding
    var zoomScrollModifier: KeyBinding
    var scrollSwitchModifier: KeyBinding
    var tileModifier: KeyBinding
    var panToggleShortcut: KeyBinding
    var autoScrollLockShortcut: KeyBinding
    var floorOverviewShortcut: KeyBinding
    var filterShortcut: KeyBinding

    init() {
        nodeJumpModifier       = KeyBinding(command: true,  control: false, option: false, shift: false, keyCode: "command")
        connectShortcut        = KeyBinding(command: true,  control: false, option: false, shift: false, keyCode: "l")
        nextTerminalShortcut   = KeyBinding(command: false, control: true,  option: false, shift: false, keyCode: "tab")
        prevTerminalShortcut   = KeyBinding(command: false, control: true,  option: false, shift: true,  keyCode: "tab")
        nextWorkspaceShortcut  = KeyBinding(command: true,  control: false, option: false, shift: false, keyCode: "arrowdown")
        prevWorkspaceShortcut  = KeyBinding(command: true,  control: false, option: false, shift: false, keyCode: "arrowup")
        workspaceJumpModifier  = KeyBinding(command: true,  control: false, option: false, shift: false, keyCode: "command")
        zoomToggleShortcut     = KeyBinding(command: true,  control: false, option: false, shift: false, keyCode: "backslash")
        zoomScrollModifier     = KeyBinding(command: true,  control: false, option: false, shift: false, keyCode: "command")
        scrollSwitchModifier   = KeyBinding(command: true,  control: false, option: false, shift: false, keyCode: "command")
        tileModifier           = KeyBinding(command: true,  control: false, option: false, shift: false, keyCode: "command")
        panToggleShortcut      = KeyBinding(command: false, control: false, option: false, shift: false, keyCode: "h")
        autoScrollLockShortcut = KeyBinding(command: true,  control: false, option: false, shift: true,  keyCode: "b")
        floorOverviewShortcut  = KeyBinding(command: true,  control: false, option: false, shift: true,  keyCode: "backslash")
        filterShortcut         = KeyBinding(command: true,  control: false, option: false, shift: false, keyCode: "p")
    }
}

struct KeyBinding: Codable, Equatable {
    var command: Bool
    var control: Bool
    var option: Bool
    var shift: Bool
    var keyCode: String
}
