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

    // MARK: - Unix Socket 支持
    private var unixSocketFd: Int32 = -1
    private var unixSocketSource: DispatchSourceRead?

    /// 当前活跃的 Unix socket 路径（供 SwiftTermProvider 注入 MAESTRI_SOCKET）
    private(set) var currentSocketPath: String?

    /// 全局固定 socket 路径（不再绑定 workspace UUID，避免切换工作区后旧终端 CLI 断联）
    static var globalSocketPath: String {
        let runDir = PersistenceManager.shared.appDataURL
            .appendingPathComponent("run").path
        return "\(runDir)/agent.sock"
    }

    private init() {}

    // MARK: - 启动

    /// Starts the TCP HTTP server on a dynamic port. Throws if the listener cannot be created.
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

    // MARK: - Unix Socket 生命周期

    /// 启动全局 Unix socket（应用生命周期内只调用一次）
    /// 不再随 workspace 切换重建，终端通过 X-Terminal-ID 标识身份
    func startUnixSocketIfNeeded() {
        guard unixSocketFd < 0 else { return }  // 已在运行
        do {
            try startUnixSocket()
        } catch {
            logger.error("InterAgentServer: Unix socket start failed: \(error)")
        }
    }

    private func startUnixSocket() throws {
        let path = Self.globalSocketPath
        currentSocketPath = path

        // 创建 run/ 目录
        let runDir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: runDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // 清理旧 socket 文件（防崩溃残留）
        unlink(path)

        // 创建 Unix socket
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "InterAgentServer", code: Int(errno),
                          userInfo: [NSLocalizedDescriptionKey: "socket() failed: \(String(cString: strerror(errno)))"])
        }
        unixSocketFd = fd

        // 绑定
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8.prefix(103)
        withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
            pathBytes.enumerated().forEach { ptr[$0.offset] = $0.element }
        }
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw NSError(domain: "InterAgentServer", code: Int(errno),
                          userInfo: [NSLocalizedDescriptionKey: "bind() failed: \(String(cString: strerror(errno)))"])
        }

        // 监听
        guard listen(fd, 10) == 0 else {
            close(fd)
            throw NSError(domain: "InterAgentServer", code: Int(errno),
                          userInfo: [NSLocalizedDescriptionKey: "listen() failed"])
        }

        // DispatchSource accept 循环
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            self?.acceptUnixConnection(serverFd: fd)
        }
        source.resume()
        unixSocketSource = source
        logger.info("InterAgentServer Unix socket ready at \(path)")
    }

    private func stopUnixSocket() {
        unixSocketSource?.cancel()
        unixSocketSource = nil
        if unixSocketFd >= 0 {
            close(unixSocketFd)
            unixSocketFd = -1
        }
        if let path = currentSocketPath {
            unlink(path)
        }
        currentSocketPath = nil
    }

    private func acceptUnixConnection(serverFd: Int32) {
        let clientFd = accept(serverFd, nil, nil)
        guard clientFd >= 0 else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.handleUnixClient(fd: clientFd)
        }
    }

    private func handleUnixClient(fd: Int32) {
        var accumulated = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        // 接收完整 HTTP 请求（阻塞 recv 保留在 DispatchQueue 线程上）
        while true {
            let n = recv(fd, &buffer, buffer.count, 0)
            guard n > 0 else { break }
            accumulated.append(contentsOf: buffer[..<n])
            // 检查 HTTP 请求是否完整
            if let headerEnd = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                let headerStr = String(decoding: accumulated[..<headerEnd.upperBound], as: UTF8.self)
                let contentLength = Self.parseContentLength(from: headerStr)
                let bodyReceived = accumulated.count - headerEnd.upperBound
                if contentLength <= 0 || bodyReceived >= contentLength { break }
            }
        }
        guard !accumulated.isEmpty else { return }
        // 读取完成后进入 async 上下文路由命令，不再阻塞 GCD 线程
        Task { [weak self, fd] in
            if let self {
                let parsed = await self.parseHTTPRequest(accumulated)
                let responseData = self.buildHTTPResponse(body: parsed.responseBody, httpVersion: parsed.httpVersion)
                responseData.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
            }
            close(fd)
        }
    }

    /// Gracefully shuts down the TCP listener and cancels all in-flight connections.
    func stop() {
        // 先取消 listener 阻止新连接进入
        listener?.cancel()
        listener = nil
        stopUnixSocket()
        port = 0
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
                    // 请求完整 — 进入 async 上下文路由命令
                    Task { [weak self] in
                        guard let self else { connection.cancel(); return }
                        let parsed = await self.parseHTTPRequest(total)
                        let responseData = self.buildHTTPResponse(body: parsed.responseBody, httpVersion: parsed.httpVersion)
                        connection.send(content: responseData, completion: .idempotent)
                        connection.cancel()
                    }
                    return
                }
            }
            // 请求不完整，继续读取
            if !isComplete {
                self?.receiveData(on: connection, accumulated: total)
            } else {
                // 连接提前关闭
                Task { [weak self] in
                    guard let self else { connection.cancel(); return }
                    let parsed = await self.parseHTTPRequest(total)
                    let responseData = self.buildHTTPResponse(body: parsed.responseBody, httpVersion: parsed.httpVersion)
                    connection.send(content: responseData, completion: .idempotent)
                    connection.cancel()
                }
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

    /// 解析结果：响应体 + 请求的 HTTP 版本
    private struct ParsedRequest {
        let responseBody: String
        let httpVersion: String  // "1.0" 或 "1.1"
    }

    private func parseHTTPRequest(_ data: Data) async -> ParsedRequest {
        // 解析 HTTP 请求，提取 JSON body、X-Terminal-ID header 和 HTTP 版本
        let raw = String(decoding: data, as: UTF8.self)
        var terminalId: UUID?
        var args: [String] = []
        var httpVersion = "1.1"  // 默认 HTTP/1.1（TCP 通道常见）

        // 简单解析：找到空行后的 JSON body
        let parts = raw.components(separatedBy: "\r\n\r\n")
        let headers = parts[0]
        let body = parts.count > 1 ? parts[1] : ""

        // 从请求行提取 HTTP 版本（如 "POST /cli HTTP/1.0"）
        let headerLines = headers.components(separatedBy: "\r\n")
        if let requestLine = headerLines.first {
            if requestLine.contains("HTTP/1.0") {
                httpVersion = "1.0"
            } else if requestLine.contains("HTTP/1.1") {
                httpVersion = "1.1"
            }
        }

        // 提取 X-Terminal-ID
        for line in headerLines {
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

        guard !args.isEmpty else {
            return ParsedRequest(responseBody: "error: missing args", httpVersion: httpVersion)
        }
        let responseBody = await CLIRouter.shared.routeAsync(args: args, terminalId: terminalId)
        return ParsedRequest(responseBody: responseBody, httpVersion: httpVersion)
    }

    private func buildHTTPResponse(body: String, httpVersion: String = "1.1") -> Data {
        let bodyData = body.data(using: .utf8) ?? Data()
        // 返回与请求匹配的 HTTP 版本（CLI 使用 HTTP/1.0，SSH/curl 使用 HTTP/1.1）
        let header = "HTTP/\(httpVersion) 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        return (header.data(using: .utf8) ?? Data()) + bodyData
    }
}
