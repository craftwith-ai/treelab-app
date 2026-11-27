public import Foundation

/// How a connection to Ginkgo ended.
public enum GinkgoConnectionEnd: Sendable, Equatable {
    /// Ginkgo closed the socket (it stopped, or it was asked to).
    case closedByPeer
    /// Ginkgo speaks another version of the contract: Treelab disconnected.
    case unknownVersion(Int?)
    /// Reading or writing failed (`errno`).
    case failed(Int32)
    /// Treelab closed it.
    case closedByTreelab
}

/// What a connection delivers, in order.
public enum GinkgoConnectionEvent: Sendable, Equatable {
    case event(GinkgoEnvelope)
    /// The last element: nothing follows.
    case ended(GinkgoConnectionEnd)
}

/// The direct channel to Ginkgo.app (§2 and §3 of the contract): a local Unix socket of the same
/// user, JSON lines both ways. No network, no sound, no timer: the kernel wakes the connection when
/// bytes arrive (`DispatchSourceRead`) or when the socket can take more (`DispatchSourceWrite`).
///
/// Every mutable property is only touched on `queue`, which is why the class is `@unchecked Sendable`.
public final class GinkgoConnection: @unchecked Sendable {
    /// Lines decoded so far are delivered here, then one ``GinkgoConnectionEvent/ended(_:)``.
    public let events: AsyncStream<GinkgoConnectionEvent>

    private let descriptor: Int32
    private let queue = DispatchQueue(label: "sh.treelab.ginkgo.connection")
    private let continuation: AsyncStream<GinkgoConnectionEvent>.Continuation
    private var readSource: (any DispatchSourceRead)?
    private var writeSource: (any DispatchSourceWrite)?
    private var framer = GinkgoLineFramer()
    private var pending = Data()
    private var nextID = 1
    private var isEnded = false

    /// Reads the user of the process at the other end of a connected socket.
    public typealias PeerReader = @Sendable (Int32) -> uid_t?

    /// The kernel's answer (`getpeereid`).
    public static let kernelPeer: PeerReader = { descriptor in
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(descriptor, &uid, &gid) == 0 ? uid : nil
    }

    /// Connects to Ginkgo's socket after checking its path, folder and owner, then the user of the
    /// process at the other end.
    /// - Parameters:
    ///   - location: the socket and the user who must own it.
    ///   - peer: reads the peer's user; the kernel's by default.
    /// - Returns: a connection reading already.
    /// - Throws: a ``GinkgoSocketRefusal``: ``GinkgoSocketRefusal/absent(_:)`` when nobody listens.
    public static func open(_ location: GinkgoSocketLocation, peer: PeerReader = kernelPeer) throws -> GinkgoConnection {
        try location.check()
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw GinkgoSocketRefusal.absent(location.path) }
        var yes: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(location.path.utf8)
        // check() already refused a path longer than sun_path can hold with its final zero.
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            Darwin.close(descriptor)
            throw GinkgoSocketRefusal.absent(location.path)
        }
        guard let uid = peer(descriptor) else {
            Darwin.close(descriptor)
            throw GinkgoSocketRefusal.absent(location.path)
        }
        do {
            try location.checkPeer(uid: uid)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        return GinkgoConnection(descriptor: descriptor)
    }

    private init(descriptor: Int32) {
        self.descriptor = descriptor
        (events, continuation) = AsyncStream.makeStream()
        queue.async { self.startReading() }
    }

    /// Sends an order with the next order number of the connection.
    /// - Parameter order: the order.
    public func send(_ order: GinkgoOrder) {
        queue.async {
            guard !self.isEnded else { return }
            self.pending.append(order.line(id: self.nextID))
            self.nextID += 1
            self.flush()
        }
    }

    /// Closes the connection; ``events`` ends with ``GinkgoConnectionEnd/closedByTreelab``.
    public func close() {
        queue.async { self.end(.closedByTreelab) }
    }

    private func startReading() {
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.readAvailable() }
        // The descriptor is closed once the kernel no longer watches it.
        source.setCancelHandler { [descriptor] in Darwin.close(descriptor) }
        readSource = source
        source.resume()
    }

    private func readAvailable() {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while !isEnded {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                for line in framer.append(Data(buffer[0..<count])) {
                    do {
                        if let envelope = try GinkgoEventDecoder.decode(line) { continuation.yield(.event(envelope)) }
                    } catch let GinkgoProtocolError.unknownVersion(version) {
                        end(.unknownVersion(version))
                        return
                    } catch {
                        // decode only throws unknownVersion: nothing else to stop on.
                    }
                }
            } else if count == 0 {
                end(.closedByPeer)
            } else if errno == EINTR {
                continue
            } else {
                if errno != EAGAIN { end(.failed(errno)) }
                return
            }
        }
    }

    private func flush() {
        while !pending.isEmpty, !isEnded {
            let written = pending.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
            if written > 0 {
                pending.removeFirst(written)
            } else if written < 0, errno == EINTR {
                continue
            } else if written < 0, errno == EAGAIN {
                waitForRoom()
                return
            } else {
                end(.failed(errno))
                return
            }
        }
        writeSource?.cancel()
        writeSource = nil
    }

    /// The socket is full: the kernel says when it can take more.
    private func waitForRoom() {
        guard writeSource == nil else { return }
        let source = DispatchSource.makeWriteSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.flush() }
        writeSource = source
        source.resume()
    }

    private func end(_ reason: GinkgoConnectionEnd) {
        guard !isEnded else { return }
        isEnded = true
        writeSource?.cancel()
        writeSource = nil
        if let readSource {
            readSource.cancel()
            self.readSource = nil
        } else {
            Darwin.close(descriptor)
        }
        continuation.yield(.ended(reason))
        continuation.finish()
    }

    deinit {
        guard !isEnded else { return }
        writeSource?.cancel()
        if let readSource { readSource.cancel() } else { Darwin.close(descriptor) }
        continuation.finish()
    }
}
