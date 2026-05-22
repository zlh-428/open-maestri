import Foundation

/// 节点内容枚举，与 Maestri v0.25.4 数据格式完全兼容
/// Maestri 格式：{ "terminal": { "_0": {...} } }
enum NodeContent: Codable, Equatable {
    case terminal(TerminalContent)
    case stickyNote(StickyNoteContent)
    case portal(PortalContent)
    case fileTree(FileTreeContent)
    case text(TextContent)
    case drawing(DrawingContent)

    // MARK: - Codable

    private enum TypeKeys: String, CodingKey {
        case terminal, stickyNote, portal, fileTree, text, drawing
    }

    private enum InnerKey: String, CodingKey {
        case _0
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKeys.self)
        if container.contains(.terminal) {
            let inner = try container.nestedContainer(keyedBy: InnerKey.self, forKey: .terminal)
            self = .terminal(try inner.decode(TerminalContent.self, forKey: ._0))
        } else if container.contains(.stickyNote) {
            let inner = try container.nestedContainer(keyedBy: InnerKey.self, forKey: .stickyNote)
            self = .stickyNote(try inner.decode(StickyNoteContent.self, forKey: ._0))
        } else if container.contains(.portal) {
            let inner = try container.nestedContainer(keyedBy: InnerKey.self, forKey: .portal)
            self = .portal(try inner.decode(PortalContent.self, forKey: ._0))
        } else if container.contains(.fileTree) {
            let inner = try container.nestedContainer(keyedBy: InnerKey.self, forKey: .fileTree)
            self = .fileTree(try inner.decode(FileTreeContent.self, forKey: ._0))
        } else if container.contains(.text) {
            let inner = try container.nestedContainer(keyedBy: InnerKey.self, forKey: .text)
            self = .text(try inner.decode(TextContent.self, forKey: ._0))
        } else if container.contains(.drawing) {
            let inner = try container.nestedContainer(keyedBy: InnerKey.self, forKey: .drawing)
            self = .drawing(try inner.decode(DrawingContent.self, forKey: ._0))
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: TypeKeys.terminal,
                in: container,
                debugDescription: "Unknown node content type"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TypeKeys.self)
        switch self {
        case .terminal(let c):
            var inner = container.nestedContainer(keyedBy: InnerKey.self, forKey: .terminal)
            try inner.encode(c, forKey: ._0)
        case .stickyNote(let c):
            var inner = container.nestedContainer(keyedBy: InnerKey.self, forKey: .stickyNote)
            try inner.encode(c, forKey: ._0)
        case .portal(let c):
            var inner = container.nestedContainer(keyedBy: InnerKey.self, forKey: .portal)
            try inner.encode(c, forKey: ._0)
        case .fileTree(let c):
            var inner = container.nestedContainer(keyedBy: InnerKey.self, forKey: .fileTree)
            try inner.encode(c, forKey: ._0)
        case .text(let c):
            var inner = container.nestedContainer(keyedBy: InnerKey.self, forKey: .text)
            try inner.encode(c, forKey: ._0)
        case .drawing(let c):
            var inner = container.nestedContainer(keyedBy: InnerKey.self, forKey: .drawing)
            try inner.encode(c, forKey: ._0)
        }
    }

    var terminalContent: TerminalContent? {
        if case .terminal(let c) = self { return c }
        return nil
    }
}

// MARK: - Terminal Content

struct TerminalContent: Codable, Equatable {
    var agentType: String       // "claude_code" | "codex" | "gemini_cli" | "open_code" | "generic_shell"
    var command: String
    var name: String
    var icon: String            // SF Symbol 名称
    var color: String           // hex
    var id: UUID
    var shellPath: String
    var workingDirectory: String
    var status: String          // "running" | "idle"
    var isManager: Bool         // Maestro Mode
    var monitorWithOmbro: Bool
    var autoScrollLocked: Bool
    var shortcutMode: ShortcutMode
    var assignedRoleId: UUID?
    var scrollbackFile: String?
    var scrollbackLineCount: Int
    var lastActiveAt: Date?

    init(name: String, agentType: String = "generic_shell", command: String = "", workingDirectory: String = "") {
        self.agentType = agentType
        self.command = command
        self.name = name
        self.icon = "terminal"
        self.color = "#007AFF"
        self.id = UUID()
        self.shellPath = "/bin/zsh"
        self.workingDirectory = workingDirectory
        self.status = "idle"
        self.isManager = false
        self.monitorWithOmbro = false
        self.autoScrollLocked = false
        self.shortcutMode = .automatic
        self.assignedRoleId = nil
        self.scrollbackFile = nil
        self.scrollbackLineCount = 0
        self.lastActiveAt = nil
    }
}

struct ShortcutMode: Codable, Equatable {
    enum Kind: String, Codable {
        case automatic
        case manual
    }
    var kind: Kind

    static let automatic = ShortcutMode(kind: .automatic)

    private enum CodingKeys: String, CodingKey { case kind }
}

// MARK: - StickyNote Content

struct StickyNoteContent: Codable, Equatable {
    var color: String           // hex, e.g. "#FEFDE8" 或 Maestri 颜色名 "yellow"
    var fileName: String?       // .md 文件名（仅文件名，不含路径）
    var fontSize: Int
    var hasCustomName: Bool
    var isPreviewing: Bool
    var storageMode: StorageMode

    init(name: String) {
        self.color = Constants.noteDefaultColor
        self.fileName = "\(name).md"
        self.fontSize = 14
        self.hasCustomName = false
        self.isPreviewing = true
        self.storageMode = .managed
    }
}

enum StorageMode: Codable, Equatable {
    case managed
    case custom(path: String)

    private enum CodingKeys: String, CodingKey { case managed, custom }
    private enum CustomKeys: String, CodingKey { case _0 }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.managed) {
            self = .managed
        } else if c.contains(.custom) {
            let inner = try c.nestedContainer(keyedBy: CustomKeys.self, forKey: .custom)
            self = .custom(path: try inner.decode(String.self, forKey: ._0))
        } else {
            self = .managed
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .managed:
            try c.encode([String: String](), forKey: .managed)
        case .custom(let path):
            var inner = c.nestedContainer(keyedBy: CustomKeys.self, forKey: .custom)
            try inner.encode(path, forKey: ._0)
        }
    }
}

// MARK: - Portal Content

struct PortalContent: Codable, Equatable {
    var id: UUID
    var name: String
    var currentURL: String
    var source: PortalSource
    var status: String          // "idle" | "loading"
    var chromeHidden: Bool
    var storageScope: String    // "isolated" | "shared"

    init(name: String, url: String = "") {
        self.id = UUID()
        self.name = name
        self.currentURL = url
        self.source = url.isEmpty ? .none : .url(url)
        self.status = "idle"
        self.chromeHidden = false
        self.storageScope = "isolated"
    }
}

enum PortalSource: Codable, Equatable {
    case none
    case url(String)

    private enum CodingKeys: String, CodingKey { case url }
    private enum UrlKey: String, CodingKey { case _0 }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.url) {
            let inner = try c.nestedContainer(keyedBy: UrlKey.self, forKey: .url)
            self = .url(try inner.decode(String.self, forKey: ._0))
        } else {
            self = .none
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            break
        case .url(let s):
            var inner = c.nestedContainer(keyedBy: UrlKey.self, forKey: .url)
            try inner.encode(s, forKey: ._0)
        }
    }
}

// MARK: - FileTree Content

struct FileTreeContent: Codable, Equatable {
    var name: String
    var rootPath: String
    var viewMode: String        // "list" | "grid"

    init(name: String, rootPath: String) {
        self.name = name
        self.rootPath = rootPath
        self.viewMode = "list"
    }
}

// MARK: - Text Content

/// 画布文本标签节点（轻量级，无 header，直接编辑）
struct TextContent: Codable, Equatable {
    var text: String
    var fontSize: CGFloat
    var fontWeight: String      // "regular" | "medium" | "bold"
    var color: String           // hex
    var alignment: String       // "left" | "center" | "right"

    init(text: String = "") {
        self.text = text
        self.fontSize = 16
        self.fontWeight = "regular"
        self.color = "#000000"
        self.alignment = "left"
    }
}

// MARK: - Drawing Content

/// 画布手绘区域节点
struct DrawingContent: Codable, Equatable {
    var strokes: [DrawingStroke]
    var backgroundColor: String // hex, 默认透明

    init() {
        self.strokes = []
        self.backgroundColor = "#FFFFFF00"
    }
}

/// 单条笔画
struct DrawingStroke: Codable, Equatable {
    var points: [[CGFloat]]     // [[x, y], [x, y], ...]
    var color: String           // hex
    var width: CGFloat

    init(points: [[CGFloat]] = [], color: String = "#000000", width: CGFloat = 2) {
        self.points = points
        self.color = color
        self.width = width
    }
}
