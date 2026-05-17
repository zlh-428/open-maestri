import Foundation
import OSLog

/// SSH 反向隧道服务（FR59-60，配合 SSHManager）
final class SSHTunnelService {
    static let shared = SSHTunnelService()
    private let logger = Logger.make(category: "SSHTunnelService")
    private(set) var isActive: Bool = false
    private(set) var tunnelPort: Int = 7433
    private init() {}

    func startTunnel(config: SSHConfig) throws {
        try SSHManager.shared.connect(config: config)
        tunnelPort = config.tunnelPort
        isActive = true
        logger.info("SSH tunnel active on port \(self.tunnelPort)")
    }

    func stopTunnel() {
        SSHManager.shared.disconnect()
        isActive = false
        logger.info("SSH tunnel stopped")
    }
}
