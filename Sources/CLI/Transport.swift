// Sources/CLI/Transport.swift
import Foundation

enum Transport {
    /// 向主 app 发送 CLI 请求，返回响应 body（纯文本）
    /// 对标逆向：socketTransport @ 0x10000c34c + buildHTTPRequest @ 0x10000b9c0 + sendAndReceive @ 0x10000c0c8
    static func send(args: [String], socketPath: String, terminalId: String) -> String {
        // 1. 创建 Unix socket（对标逆向：socket(AF_UNIX=1, SOCK_STREAM=1, 0)）
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            fputs("error: socket creation failed\n", stderr)
            exit(1)
        }
        defer { close(fd) }

        // 2. 设置超时（对标逆向：SO_SNDTIMEO=0x1006, SO_RCVTIMEO=0x1005, SOL_SOCKET=0xffff）
        var tv = timeval(tv_sec: 30, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // 3. 构建 sockaddr_un（对标逆向：sizeof = 106 = sun_len(1) + sun_family(1) + sun_path(104)）
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8.prefix(103)  // 最大 103 字节（+1 null terminator）
        withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
            pathBytes.enumerated().forEach { ptr[$0.offset] = $0.element }
        }

        // 4. 连接
        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            let errMsg = String(cString: strerror(errno))
            fputs("error: connection failed: \(errMsg)\n", stderr)
            fputs("Is open-maestri running? Try: omaestri debug\n", stderr)
            exit(1)
        }

        // 5. 构建 JSON body（对标逆向：{"args":["command","arg1","arg2",...]}）
        guard let bodyData = try? JSONSerialization.data(withJSONObject: ["args": args]) else {
            fputs("error: JSON serialization failed\n", stderr)
            exit(1)
        }

        // 6. 构建 HTTP/1.0 请求头（对标逆向：buildHTTPRequest @ 0x10000b9c0）
        var request = "POST /cli HTTP/1.0\r\n"
        request += "Host: maestri\r\n"
        request += "X-Terminal-ID: \(terminalId)\r\n"
        request += "Content-Type: application/json\r\n"
        request += "Content-Length: \(bodyData.count)\r\n"
        request += "\r\n"

        // 7. 发送请求头 + body（两次 send，对标逆向两次 _send 调用）
        guard let headerData = request.data(using: .utf8) else {
            fputs("error: header encoding failed\n", stderr)
            exit(1)
        }
        let sendResult = headerData.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        guard sendResult >= 0 else {
            fputs("error: send failed\n", stderr)
            exit(1)
        }
        let sendBodyResult = bodyData.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        guard sendBodyResult >= 0 else {
            fputs("error: send body failed\n", stderr)
            exit(1)
        }

        // 8. 接收响应（循环 recv，8KB buffer，对标逆向 0x2000 缓冲区）
        var accumulated = Data()
        var buffer = [UInt8](repeating: 0, count: 0x2000)
        while true {
            let n = recv(fd, &buffer, 0x2000, 0)
            guard n >= 1 else { break }
            accumulated.append(contentsOf: buffer[..<n])
        }

        // 9. 解析 HTTP 响应，提取 body（对标逆向：查找 \r\n\r\n 后取 body）
        return parseHTTPResponse(accumulated)
    }

    private static func parseHTTPResponse(_ data: Data) -> String {
        guard let responseStr = String(data: data, encoding: .utf8) else {
            fputs("error: invalid response encoding\n", stderr)
            exit(1)
        }
        // 检查状态码
        guard responseStr.hasPrefix("HTTP/") else {
            fputs("error: invalid HTTP response\n", stderr)
            exit(1)
        }
        let statusLine = responseStr.components(separatedBy: "\r\n")[0]
        let parts = statusLine.components(separatedBy: " ")
        let statusCode = parts.count >= 2 ? Int(parts[1]) ?? 0 : 0
        if statusCode >= 300 {
            fputs("Request failed (status \(statusCode))\n", stderr)
            exit(1)
        }
        // 提取 body（\r\n\r\n 之后）
        guard let range = responseStr.range(of: "\r\n\r\n") else {
            return responseStr
        }
        return String(responseStr[range.upperBound...])
    }
}
