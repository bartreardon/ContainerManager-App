//
//  PortProbe.swift
//  ContainerManager
//

import Foundation

/// Checks whether something is accepting TCP connections yet. Used to wait for a stack
/// service to actually be listening before starting the services that depend on it.
enum PortProbe {
    /// One connection attempt. Blocking, so call it off the main actor.
    nonisolated static func canConnect(host: String, port: UInt16, timeout: TimeInterval = 1) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return false }

        // Connect non-blocking and bound the wait with poll(). SO_SNDTIMEO does *not*
        // apply to a blocking connect() here — an unreachable address would otherwise
        // stall for the system's full TCP timeout (~75s) on every attempt.
        let flags = fcntl(descriptor, F_GETFL, 0)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else { return false }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var poller = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        guard poll(&poller, 1, Int32(timeout * 1000)) == 1 else { return false }

        // Writable doesn't mean connected — check the pending socket error.
        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0 else { return false }
        return socketError == 0
    }

    /// Polls until `host:port` accepts a connection. Returns false if `timeout` elapses.
    static func waitUntilAccepting(host: String, port: UInt16, timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline, !Task.isCancelled {
            let open = await Task.detached(priority: .utility) {
                canConnect(host: host, port: port)
            }.value
            if open { return true }
            try? await Task.sleep(for: .seconds(1))
        }
        return false
    }
}
