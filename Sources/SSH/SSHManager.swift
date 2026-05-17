import Foundation
import OSLog

/// SSH 连接配置
struct SSHConfig: Codable {
    var host: String
    var user: String
    var port: Int
    var scriptPath: String  // 远程服务器上安装 omaestri 的路径
    var tunnelPort: Int     // 反向隧道本地端口（默认 7433）
    var addToPath: Bool     // 是否将脚本目录添加到 shell profile PATH
}

/// Remote SSH 管理器（FR59-60，Epic 11）
/// - 建立 SSH 连接并在远程安装 omaestri 脚本
/// - 通过反向隧道（-R）将远端 omaestri ask 路由回本地 InterAgentServer
final class SSHManager {
    static let shared = SSHManager()
    private let logger = Logger.make(category: "SSHManager")
    private var sshProcess: Process?
    private var isConnected: Bool = false
    private init() {}

    // MARK: - 连接

    func connect(config: SSHConfig) throws {
        guard !isConnected else {
            logger.warning("SSH already connected")
            return
        }

        // 建立反向隧道：远程 tunnelPort → 本地 InterAgentServer
        let localPort = InterAgentServer.shared.port
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [
            "-N",                           // 不执行远程命令
            "-o", "StrictHostKeyChecking=accept-new",
            "-R", "\(config.tunnelPort):127.0.0.1:\(localPort)",  // 反向隧道（NFR8）
            "-p", "\(config.port)",
            "\(config.user)@\(config.host)"
        ]
        try process.run()
        sshProcess = process
        isConnected = true
        logger.info("SSH tunnel established to \(config.host):\(config.port), tunnelPort=\(config.tunnelPort)")

        // 在远程安装 omaestri 脚本
        Task { try await installOmaestri(config: config) }
    }

    func disconnect() {
        sshProcess?.terminate()
        sshProcess = nil
        isConnected = false
        logger.debug("SSH disconnected")
    }

    // MARK: - 安装 omaestri 脚本

    private func installOmaestri(config: SSHConfig) async throws {
        let tunnelHost = "127.0.0.1:\(config.tunnelPort)"
        let scriptContent = SkillInjector.shared.buildSkillScript(terminalId: UUID(), host: tunnelHost)

        // 使用 base64 编码避免引号/变量展开转义问题
        guard let scriptData = scriptContent.data(using: .utf8) else { return }
        let base64Script = scriptData.base64EncodedString()
        let scriptDir = (config.scriptPath as NSString).deletingLastPathComponent
        let scriptFile = (config.scriptPath as NSString).lastPathComponent

        let remoteCmd = [
            "mkdir -p \(scriptDir)",
            "echo \(base64Script) | base64 -d > \(config.scriptPath)",
            "chmod +x \(config.scriptPath)",
        ].joined(separator: " && ")

        // 若用户选择 addToPath，追加到 shell profile
        let addToPathCmd = config.addToPath
            ? " && echo 'export PATH=\"\(scriptDir):$PATH\"' >> ~/.zshrc 2>/dev/null; echo 'export PATH=\"\(scriptDir):$PATH\"' >> ~/.bashrc 2>/dev/null; true"
            : ""

        let sshCmd = Process()
        sshCmd.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        sshCmd.arguments = [
            "-o", "StrictHostKeyChecking=accept-new",
            "-p", "\(config.port)",
            "\(config.user)@\(config.host)",
            remoteCmd + addToPathCmd
        ]
        try sshCmd.run()
        sshCmd.waitUntilExit()
        logger.info("omaestri script installed at \(config.host):\(config.scriptPath) (file: \(scriptFile))")
    }
}
