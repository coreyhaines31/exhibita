import Darwin
import Foundation

/// The Unix domain socket under Application Support, and the POSIX calls around it. Local only: there is no TCP
/// and no network address anywhere in the bridge.
public enum BridgeSocket {
    public static let directoryName = "Bridge"
    public static let fileName = "bridge.sock"

    /// `<support>/Bridge/bridge.sock`. The directory is 0700 and the socket 0600.
    public static func url(inSupportDirectory support: URL) -> URL {
        support.appendingPathComponent(directoryName, isDirectory: true).appendingPathComponent(fileName)
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case pathTooLong(String)
        case system(String, Int32)
        /// Something that is not a socket sits at the socket's path, or the directory belongs to someone else.
        case unsafePath(String)
        /// Another copy of the app is already serving on the socket.
        case alreadyServing(String)

        public var description: String {
            switch self {
            case .pathTooLong(let path): "The socket path is too long for a Unix socket: \(path)"
            case let .system(call, code): "\(call) failed: \(String(cString: strerror(code)))"
            case .unsafePath(let reason): reason
            case .alreadyServing(let path): "Another Exhibit A is already serving \(path)"
            }
        }
    }

    // MARK: Addresses and descriptors

    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw Failure.pathTooLong(path) }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }

    static func makeSocket() throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Failure.system("socket", errno) }
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        return descriptor
    }

    /// Connects to `path`. Throws `.system("connect", errno)`; ENOENT and ECONNREFUSED mean nobody is serving.
    static func connect(to path: String) throws -> Int32 {
        var address = try address(path)
        let descriptor = try makeSocket()
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw Failure.system("connect", code)
        }
        return descriptor
    }

    /// The user id of the process on the other end of a connected socket (`getpeereid`, `LOCAL_PEERCRED`).
    static func peerUID(_ descriptor: Int32) -> uid_t? {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(descriptor, &uid, &gid) == 0 else { return nil }
        return uid
    }

    static func setNonBlocking(_ descriptor: Int32) {
        let flags = fcntl(descriptor, F_GETFL)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
    }

    // MARK: Lines

    enum IOFailure: Error, Equatable {
        case timedOut
        case closed
        case tooLong
        case failed(Int32)
    }

    /// Reads up to the first newline, waiting at most until `deadline`. The newline is not returned.
    static func readLine(_ descriptor: Int32, deadline: Date, limit: Int = BridgeProtocol.maxLineBytes) throws -> Data {
        var line = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            try wait(descriptor, events: Int16(POLLIN), deadline: deadline)
            let transferred = Darwin.read(descriptor, &buffer, buffer.count)
            if transferred < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                throw IOFailure.failed(errno)
            }
            if transferred == 0 { throw IOFailure.closed }
            if let newline = buffer[0..<transferred].firstIndex(of: 0x0A) {
                line.append(contentsOf: buffer[0..<newline])
                guard line.count <= limit else { throw IOFailure.tooLong }
                return line
            }
            line.append(contentsOf: buffer[0..<transferred])
            guard line.count <= limit else { throw IOFailure.tooLong }
        }
    }

    static func writeAll(_ descriptor: Int32, _ data: Data, deadline: Date) throws {
        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            try wait(descriptor, events: Int16(POLLOUT), deadline: deadline)
            let transferred = bytes[offset...].withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
            if transferred < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                throw IOFailure.failed(errno)
            }
            offset += transferred
        }
    }

    private static func wait(_ descriptor: Int32, events: Int16, deadline: Date) throws {
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw IOFailure.timedOut }
            var request = pollfd(fd: descriptor, events: events, revents: 0)
            let milliseconds = Int32(min(remaining * 1000, Double(Int32.max)).rounded(.up))
            let ready = poll(&request, 1, milliseconds)
            if ready > 0 { return }
            if ready == 0 { throw IOFailure.timedOut }
            if errno != EINTR { throw IOFailure.failed(errno) }
        }
    }

    // MARK: The directory

    /// Creates `<support>/Bridge` as 0700, or tightens an existing one, and checks it belongs to this user and is
    /// not a symbolic link.
    static func preparePrivateDirectory(_ directory: URL) throws {
        let path = directory.path
        var info = stat()
        if lstat(path, &info) != 0 {
            try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            guard mkdir(path, 0o700) == 0 || errno == EEXIST else { throw Failure.system("mkdir", errno) }
            guard lstat(path, &info) == 0 else { throw Failure.system("lstat", errno) }
        }
        guard info.st_mode & S_IFMT == S_IFDIR else {
            throw Failure.unsafePath("\(path) is not a directory.")
        }
        guard info.st_uid == getuid() else {
            throw Failure.unsafePath("\(path) belongs to another user.")
        }
        guard chmod(path, 0o700) == 0 else { throw Failure.system("chmod", errno) }
    }

    /// The permission bits of a file or directory, without following links.
    public static func mode(of path: String) -> mode_t? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return info.st_mode & 0o777
    }
}
