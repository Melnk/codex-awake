import CryptoKit
import Darwin
import Foundation

public protocol LocalWebSocketTransport: Sendable {
    func connect() throws
    func send(text: String) throws
    func receive() throws -> String?
    func close()
}

public final class UnixWebSocketTransport: LocalWebSocketTransport, @unchecked Sendable {
    private let socketPath: String
    private let stateLock = NSLock()
    private let writeLock = NSLock()
    private var descriptor: Int32 = -1

    public init(socketPath: String) {
        self.socketPath = socketPath
    }

    deinit {
        close()
    }

    public func connect() throws {
        let pathBytes = Array(socketPath.utf8)
        let pathCapacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        guard pathBytes.count + 1 <= pathCapacity else { throw CodexAwakeError.socketPathTooLong }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw socketError("socket") }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let addressLength = MemoryLayout.offset(of: \sockaddr_un.sun_path)! + pathBytes.count + 1
        address.sun_len = UInt8(addressLength)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: pathBytes)
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(addressLength))
            }
        }
        guard result == 0 else {
            Darwin.close(fd)
            throw socketError("connect")
        }

        stateLock.withLock { descriptor = fd }
        do {
            try performHandshake(fd: fd)
        } catch {
            close()
            throw error
        }
    }

    public func send(text: String) throws {
        try sendFrame(opcode: 0x1, payload: Array(text.utf8))
    }

    public func receive() throws -> String? {
        while true {
            let first = try readExactly(count: 2)
            let opcode = first[0] & 0x0F
            let isMasked = (first[1] & 0x80) != 0
            var length = UInt64(first[1] & 0x7F)
            if length == 126 {
                let bytes = try readExactly(count: 2)
                length = UInt64(bytes[0]) << 8 | UInt64(bytes[1])
            } else if length == 127 {
                let bytes = try readExactly(count: 8)
                length = bytes.reduce(0) { ($0 << 8) | UInt64($1) }
            }
            guard length <= 16 * 1_024 * 1_024 else {
                throw CodexAwakeError.connectionFailed("WebSocket frame is too large")
            }
            let mask = isMasked ? try readExactly(count: 4) : []
            var payload = try readExactly(count: Int(length))
            if isMasked {
                for index in payload.indices { payload[index] ^= mask[index % 4] }
            }

            switch opcode {
            case 0x1:
                guard let text = String(bytes: payload, encoding: .utf8) else {
                    throw CodexAwakeError.malformedMessage
                }
                return text
            case 0x8:
                close()
                return nil
            case 0x9:
                try sendFrame(opcode: 0xA, payload: payload)
            case 0xA:
                continue
            default:
                throw CodexAwakeError.connectionFailed("Unsupported WebSocket opcode \(opcode)")
            }
        }
    }

    public func close() {
        let fd = stateLock.withLock { () -> Int32 in
            let current = descriptor
            descriptor = -1
            return current
        }
        if fd >= 0 {
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
    }

    private func performHandshake(fd: Int32) throws {
        let keyData = Data(UUID().uuidString.utf8.prefix(16))
        let key = keyData.base64EncodedString()
        let request = [
            "GET / HTTP/1.1",
            "Host: localhost",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Key: \(key)",
            "Sec-WebSocket-Version: 13",
            "",
            ""
        ].joined(separator: "\r\n")
        try writeAll(fd: fd, bytes: Array(request.utf8))

        var response: [UInt8] = []
        let terminator = Array("\r\n\r\n".utf8)
        while response.count < 16_384, !response.suffix(4).elementsEqual(terminator) {
            response += try readExactly(fd: fd, count: 1)
        }
        guard let headers = String(bytes: response, encoding: .utf8),
              headers.hasPrefix("HTTP/1.1 101") || headers.hasPrefix("HTTP/1.0 101") else {
            throw CodexAwakeError.connectionFailed("Unix WebSocket upgrade was rejected")
        }

        let expected = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
        let acceptLine = headers.split(separator: "\r\n").first {
            $0.lowercased().hasPrefix("sec-websocket-accept:")
        }
        let actual = acceptLine?.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces)
        guard actual == expected else {
            throw CodexAwakeError.connectionFailed("Unix WebSocket handshake validation failed")
        }
    }

    private func sendFrame(opcode: UInt8, payload: [UInt8]) throws {
        let fd = try currentDescriptor()
        var header: [UInt8] = [0x80 | opcode]
        let count = payload.count
        if count < 126 {
            header.append(0x80 | UInt8(count))
        } else if count <= 65_535 {
            header += [0x80 | 126, UInt8((count >> 8) & 0xFF), UInt8(count & 0xFF)]
        } else {
            header += [0x80 | 127]
            header += (0..<8).reversed().map { UInt8((UInt64(count) >> UInt64($0 * 8)) & 0xFF) }
        }
        let mask = Array(UUID().uuidString.utf8.prefix(4))
        header += mask
        let masked = payload.enumerated().map { $0.element ^ mask[$0.offset % 4] }
        try writeLock.withLock {
            try writeAll(fd: fd, bytes: header + masked)
        }
    }

    private func readExactly(count: Int) throws -> [UInt8] {
        try readExactly(fd: currentDescriptor(), count: count)
    }

    private func readExactly(fd: Int32, count: Int) throws -> [UInt8] {
        guard count > 0 else { return [] }
        var result = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let readCount = result.withUnsafeMutableBytes { buffer in
                Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), count - offset)
            }
            if readCount == 0 { throw CodexAwakeError.connectionFailed("Unix socket closed") }
            if readCount < 0 {
                if errno == EINTR { continue }
                throw socketError("read")
            }
            offset += readCount
        }
        return result
    }

    private func writeAll(fd: Int32, bytes: [UInt8]) throws {
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { buffer in
                Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), bytes.count - offset)
            }
            if written < 0 {
                if errno == EINTR { continue }
                throw socketError("write")
            }
            if written == 0 { throw CodexAwakeError.connectionFailed("Unix socket write returned zero bytes") }
            offset += written
        }
    }

    private func currentDescriptor() throws -> Int32 {
        let fd = stateLock.withLock { descriptor }
        guard fd >= 0 else { throw CodexAwakeError.connectionFailed("Unix socket is not connected") }
        return fd
    }

    private func socketError(_ operation: String) -> CodexAwakeError {
        .connectionFailed("\(operation): \(String(cString: strerror(errno)))")
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
