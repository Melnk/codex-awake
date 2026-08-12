import Darwin
import Foundation

public struct SocketPathManager: @unchecked Sendable {
    public struct Runtime: Equatable, Sendable {
        public let directory: URL
        public let socket: URL

        public init(directory: URL, socket: URL) {
            self.directory = directory
            self.socket = socket
        }

        public var endpoint: String { "unix://\(socket.path)" }
    }

    public enum ExistingSocketDecision: Equatable, Sendable {
        case removeStale
        case refuseActive
        case refuseUnsafe
    }

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func runtime() throws -> Runtime {
        let uid = getuid()
        var directory = fileManager.temporaryDirectory.appendingPathComponent("codexawake-\(uid)", isDirectory: true)
        var socket = directory.appendingPathComponent("app-server.sock")
        if socket.path.utf8.count >= 100 {
            directory = URL(fileURLWithPath: "/tmp/caw-\(uid)", isDirectory: true)
            socket = directory.appendingPathComponent("server.sock")
        }
        guard socket.path.utf8.count < 104 else { throw CodexAwakeError.socketPathTooLong }
        return Runtime(directory: directory, socket: socket)
    }

    public func prepare(_ runtime: Runtime) throws {
        try fileManager.createDirectory(
            at: runtime.directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runtime.directory.path)
        try validateRuntimeDirectory(runtime.directory)

        guard fileManager.fileExists(atPath: runtime.socket.path) else { return }
        let metadata = try socketMetadata(at: runtime.socket.path)
        let decision = Self.existingSocketDecision(
            isSocket: metadata.isSocket,
            ownerMatches: metadata.uid == getuid(),
            acceptsConnection: socketAcceptsConnection(path: runtime.socket.path)
        )
        switch decision {
        case .removeStale:
            try fileManager.removeItem(at: runtime.socket)
        case .refuseActive:
            throw CodexAwakeError.socketOwnedByAnotherProcess
        case .refuseUnsafe:
            throw CodexAwakeError.invalidSocket("path is not an owned Unix socket")
        }
    }

    public func cleanupOwnedSocket(_ runtime: Runtime) throws {
        guard fileManager.fileExists(atPath: runtime.socket.path) else { return }
        let metadata = try socketMetadata(at: runtime.socket.path)
        guard metadata.isSocket, metadata.uid == getuid() else { return }
        try fileManager.removeItem(at: runtime.socket)
    }

    public func cleanupOwnedRuntime(_ runtime: Runtime) throws {
        try cleanupOwnedSocket(runtime)
        guard fileManager.fileExists(atPath: runtime.directory.path) else { return }
        try validateRuntimeDirectory(runtime.directory)
        let contents = try fileManager.contentsOfDirectory(atPath: runtime.directory.path)
        if contents.isEmpty {
            try fileManager.removeItem(at: runtime.directory)
        }
    }

    public static func existingSocketDecision(
        isSocket: Bool,
        ownerMatches: Bool,
        acceptsConnection: Bool
    ) -> ExistingSocketDecision {
        guard isSocket, ownerMatches else { return .refuseUnsafe }
        return acceptsConnection ? .refuseActive : .removeStale
    }

    private func validateRuntimeDirectory(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
            (info.st_mode & S_IFMT) == S_IFDIR,
            info.st_uid == getuid(),
            (info.st_mode & 0o077) == 0
        else {
            throw CodexAwakeError.invalidSocket("runtime directory ownership or permissions are unsafe")
        }
    }

    private func socketMetadata(at path: String) throws -> (isSocket: Bool, uid: uid_t) {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            throw CodexAwakeError.invalidSocket("cannot inspect runtime path")
        }
        return ((info.st_mode & S_IFMT) == S_IFSOCK, info.st_uid)
    }

    private func socketAcceptsConnection(path: String) -> Bool {
        let pathBytes = Array(path.utf8)
        guard pathBytes.count + 1 <= MemoryLayout.size(ofValue: sockaddr_un().sun_path) else { return true }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return true }
        defer { Darwin.close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        guard let sunPathOffset = MemoryLayout.offset(of: \sockaddr_un.sun_path) else { return true }
        let length = sunPathOffset + pathBytes.count + 1
        address.sun_len = UInt8(length)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: pathBytes)
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(length))
            }
        }
        return result == 0
    }
}
