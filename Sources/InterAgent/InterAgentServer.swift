import Foundation
import Network
import OSLog

/// 本地 HTTP IPC 服务器
/// - 绑定 127.0.0.1 动态端口，仅接受本机连接（安全约束）
/// - 单一路由：POST /cli
/// - 所有 omaestri CLI 命令通过此服务路由
final class InterAgentServer {
    static let shared = InterAgentServer()
    private let logger = Logger.make(category: "InterAgentServer")

    private var listener: NWListener?
    private(set) var port: UInt16 = 0

    private init() {}

    // MARK: - 启动

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(Constants.interAgentServerHost),
            port: .any
        )

        listener = try NWListener(using: params)

        // 用信号量等待端口就绪，确保 SwiftTermProvider 能读取到正确端口
        let semaphore = DispatchSemaphore(value: 0)
        var startError: Error? = nil

        listener?.stateUpdateHandler = { [weak self] state in
            self?.handleStateChange(state)
            switch state {
            case .ready, .failed:
                semaphore.signal()
            default:
                break
            }
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener?.start(queue: .global(qos: .userInitiated))

        // 最多等待 2 秒
        let result = semaphore.wait(timeout: .now() + 2.0)
        if result == .timedOut {
            logger.warning("InterAgentServer: timed out waiting for port assignment")
        }
        _ = startError
        logger.debug("InterAgentServer starting on \(Constants.interAgentServerHost):\(self.port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        logger.debug("InterAgentServer stopped")
    }

    // MARK: - 状态处理

    private func handleStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            port = listener?.port?.rawValue ?? 0
            restartCount = 0  // 成功后重置退避计数
            logger.info("InterAgentServer ready on port \(self.port)")
        case .failed(let error):
            logger.error("InterAgentServer failed: \(error)")
            scheduleRestart()
        default:
            break
        }
    }

    private var restartCount = 0
    private let maxRestarts = 5

    private func scheduleRestart() {
        guard restartCount < maxRestarts else {
            logger.error("InterAgentServer: max restart attempts (\(self.maxRestarts)) reached, giving up")
            return
        }
        // 指数退避：3s, 6s, 12s, 24s, 48s
        let delay = Constants.serverRestartDelay * pow(2.0, Double(restartCount))
        restartCount += 1
        logger.warning("InterAgentServer restarting in \(Int(delay))s (attempt \(self.restartCount)/\(self.maxRestarts))")
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            try? self?.start()
        }
    }

    // MARK: - 连接处理（HTTP POST /cli）

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveRequest(on: connection)
    }

    private func receiveRequest(on connection: NWConnection) {
        // 分块累积接收，最大 1MB（支持大型 portal evaluate 命令）
        receiveData(on: connection, accumulated: Data())
    }

    private func receiveData(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 262144) { [weak self] data, _, isComplete, error in
            guard error == nil else { connection.cancel(); return }
            let total = accumulated + (data ?? Data())
            // 检测 HTTP 请求是否完整（找到 header/body 分隔符）
            if let headerEnd = total.range(of: Data("\r\n\r\n".utf8)) {
                // 解析 Content-Length 决定是否继续读取
                let headerData = total[..<headerEnd.upperBound]
                let headerStr = String(decoding: headerData, as: UTF8.self)
                let bodyStart = headerEnd.upperBound
                let contentLength = Self.parseContentLength(from: headerStr)
                let bodyReceived = total.count - bodyStart
                if contentLength <= 0 || bodyReceived >= contentLength {
                    // 请求完整
                    if let response = self?.processHTTPRequest(total) {
                        let responseData = self?.buildHTTPResponse(body: response) ?? Data()
                        connection.send(content: responseData, completion: .idempotent)
                    }
                    connection.cancel()
                    return
                }
            }
            // 请求不完整，继续读取
            if !isComplete {
                self?.receiveData(on: connection, accumulated: total)
            } else {
                // 连接提前关闭
                if let response = self?.processHTTPRequest(total) {
                    let responseData = self?.buildHTTPResponse(body: response) ?? Data()
                    connection.send(content: responseData, completion: .idempotent)
                }
                connection.cancel()
            }
        }
    }

    private static func parseContentLength(from headers: String) -> Int {
        for line in headers.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let val = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                return Int(val) ?? 0
            }
        }
        return 0
    }

    private func processHTTPRequest(_ data: Data) -> String {
        // 解析 HTTP 请求，提取 JSON body 和 X-Terminal-ID header
        let raw = String(decoding: data, as: UTF8.self)
        var terminalId: UUID?
        var args: [String] = []

        // 简单解析：找到空行后的 JSON body
        let parts = raw.components(separatedBy: "\r\n\r\n")
        let headers = parts[0]
        let body = parts.count > 1 ? parts[1] : ""

        // 提取 X-Terminal-ID
        for line in headers.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("x-terminal-id:") {
                let idStr = line.dropFirst("x-terminal-id:".count).trimmingCharacters(in: .whitespaces)
                terminalId = UUID(uuidString: idStr)
            }
        }

        // 解析 JSON args
        if let bodyData = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
           let rawArgs = json["args"] as? [String] {
            args = rawArgs
        }

        guard !args.isEmpty else { return "error: missing args" }
        return CLIRouter.shared.route(args: args, terminalId: terminalId)
    }

    private func buildHTTPResponse(body: String) -> Data {
        let bodyData = body.data(using: .utf8) ?? Data()
        // 返回 text/plain：omaestri CLI 用 curl 直接打印输出，无需 JSON 解析
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        return (header.data(using: .utf8) ?? Data()) + bodyData
    }
}
