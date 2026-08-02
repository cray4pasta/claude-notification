import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Local-only Unix domain socket server. Hook scripts (running as
/// subprocesses of Claude Code) connect here to hand off a hook payload;
/// nothing outside this machine can reach it (PRD docs/PRD.md §9, "local-only,
/// no network exposure").
///
/// Framing note: Apple's `nc` doesn't half-close its write side after
/// stdin EOF (no `-N`-equivalent), so "read until EOF" doesn't work to
/// detect "the client finished sending." Instead we read incrementally and
/// try to parse a complete JSON object after each chunk — once that
/// succeeds, the message is complete, regardless of whether the client's
/// connection is still nominally open.
final class SocketServer {
    private let socketPath: String
    private var listenFD: Int32 = -1
    private let queue = DispatchQueue(label: "nudge.socketserver")
    private var running = false

    private static let maxPayloadBytes = 2 * 1024 * 1024

    /// Called on a background thread once a complete JSON payload has
    /// arrived. May block (e.g. waiting on a human decision). Return
    /// non-nil to write those bytes back to the client before closing;
    /// return nil for fire-and-forget events.
    var onPayload: ((Data) -> Data?)?

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func start() throws {
        let directory = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        // Remove a stale socket file from a previous run, if present.
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.posix("socket() failed") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw SocketError.pathTooLong
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { rawPtr in
            rawPtr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count + 1) { ptr in
                for (i, byte) in pathBytes.enumerated() { ptr[i] = CChar(bitPattern: byte) }
                ptr[pathBytes.count] = 0
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw SocketError.posix("bind() failed")
        }

        // Local socket file, owner-only.
        chmod(socketPath, 0o600)

        guard listen(fd, 8) == 0 else {
            close(fd)
            throw SocketError.posix("listen() failed")
        }

        listenFD = fd
        running = true
        queue.async { [weak self] in self?.acceptLoop() }
    }

    func stop() {
        running = false
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        unlink(socketPath)
    }

    private func acceptLoop() {
        while running {
            let clientFD = accept(listenFD, nil, nil)
            guard clientFD >= 0 else {
                if running {
                    // Interrupted or transient error; brief backoff, keep serving.
                    usleep(100_000)
                }
                continue
            }
            // Handlers run on the global concurrent queue, NOT `queue` —
            // `queue` is permanently occupied by this loop's blocking
            // accept() call, so anything dispatched back onto it would
            // just queue up behind an infinite loop and never execute.
            // A PreToolUse handler in particular can block for minutes
            // waiting on a human decision, so it must own its own thread.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handle(clientFD: clientFD)
            }
        }
    }

    private func handle(clientFD: Int32) {
        defer { close(clientFD) }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        var parsed: Data?

        while buffer.count < Self.maxPayloadBytes {
            let bytesRead = read(clientFD, &chunk, chunk.count)
            if bytesRead <= 0 { break } // client closed or errored before sending a complete object
            buffer.append(contentsOf: chunk[0..<bytesRead])

            if (try? JSONSerialization.jsonObject(with: buffer)) != nil {
                parsed = buffer
                break
            }
        }

        guard let parsed else { return }
        let response = onPayload?(parsed)
        guard let response else { return }

        response.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            var offset = 0
            let base = rawBuffer.bindMemory(to: UInt8.self)
            while offset < base.count {
                let written = write(clientFD, base.baseAddress!.advanced(by: offset), base.count - offset)
                if written <= 0 { break }
                offset += written
            }
        }
    }

    enum SocketError: Error {
        case posix(String)
        case pathTooLong
    }
}
