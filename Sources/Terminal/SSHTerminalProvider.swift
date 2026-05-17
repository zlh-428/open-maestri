import Foundation
// SSH 远程终端提供者（SSH 连接的终端，Epic 11 完整实现）
// 复用 SSHTunnelService 建立的连接
final class SSHTerminalProvider {
    let terminalId: UUID
    let config: SSHConfig

    init(terminalId: UUID, config: SSHConfig) {
        self.terminalId = terminalId
        self.config = config
    }
}
