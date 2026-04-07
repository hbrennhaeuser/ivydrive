import Foundation
import Network
import Darwin

struct DriveAvailabilityResult {
    enum Status: Equatable { case passed, failed, disabled, timedOut, skipped }

    let driveID: UUID
    var dns: Status
    var reachable: Status
    var port: Status

    /// True when at least one check ran and every run check passed.
    var dotIsOrange: Bool {
        let enabled = [dns, reachable, port].filter { $0 != .disabled && $0 != .skipped }
        return !enabled.isEmpty && enabled.allSatisfy { $0 == .passed }
    }
}

final class DriveAvailabilityChecker {
    static let shared = DriveAvailabilityChecker()

    private let queue = DispatchQueue(label: "com.menubarfs.availability", attributes: .concurrent)

    private init() {}

    /// Runs all enabled checks for all provided drives fully in parallel.
    /// Blocks the caller for at most `timeout` seconds.
    func checkAll(_ drives: [NetworkDrive], timeout: TimeInterval = 1.5) -> [UUID: DriveAvailabilityResult] {
        var results = [UUID: DriveAvailabilityResult]()
        let lock = NSLock()
        let group = DispatchGroup()

        for drive in drives {
            guard drive.checkDNSResolution || drive.checkHostReachability || drive.checkPortAvailability else {
                results[drive.id] = DriveAvailabilityResult(driveID: drive.id, dns: .disabled, reachable: .disabled, port: .disabled)
                continue
            }
            group.enter()
            queue.async {
                let result = self.check(drive, timeout: timeout)
                lock.lock(); results[drive.id] = result; lock.unlock()
                group.leave()
            }
        }

        _ = group.wait(timeout: .now() + timeout)
        return results
    }

    private func check(_ drive: NetworkDrive, timeout: TimeInterval) -> DriveAvailabilityResult {
        guard let parsed = URL(string: drive.url), let host = parsed.host else {
            return DriveAvailabilityResult(driveID: drive.id, dns: .failed, reachable: .failed, port: .failed)
        }
        let portNumber = parsed.port ?? Self.defaultPort(for: parsed.scheme)
        let isIP = Self.isIPAddress(host)

        // DNS runs synchronously first; a failure short-circuits ping and port.
        let dns: DriveAvailabilityResult.Status
        if !drive.checkDNSResolution {
            dns = .disabled
        } else if isIP {
            dns = .skipped
        } else {
            dns = Self.checkDNS(host: host) ? .passed : .failed
        }

        let dnsBlocked = (dns == .failed)

        var reachable: DriveAvailabilityResult.Status
        if !drive.checkHostReachability  { reachable = .disabled }
        else if dnsBlocked               { reachable = .skipped  }
        else                             { reachable = .timedOut }

        var port: DriveAvailabilityResult.Status
        if !drive.checkPortAvailability || portNumber == nil { port = .disabled }
        else if dnsBlocked                                   { port = .skipped  }
        else                                                 { port = .timedOut }

        let lock = NSLock()
        let group = DispatchGroup()

        if reachable == .timedOut {
            group.enter()
            queue.async {
                let r: DriveAvailabilityResult.Status = Self.checkReachability(host: host) ? .passed : .failed
                lock.lock(); reachable = r; lock.unlock()
                group.leave()
            }
        }

        if port == .timedOut, let p = portNumber {
            group.enter()
            queue.async {
                let r: DriveAvailabilityResult.Status = Self.checkPort(host: host, port: p, timeout: timeout) ? .passed : .failed
                lock.lock(); port = r; lock.unlock()
                group.leave()
            }
        }

        _ = group.wait(timeout: .now() + timeout)

        lock.lock()
        let result = DriveAvailabilityResult(driveID: drive.id, dns: dns, reachable: reachable, port: port)
        lock.unlock()
        return result
    }

    // MARK: - Individual Checks

    private static func checkDNS(host: String) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>? = nil
        let ret = getaddrinfo(host, nil, &hints, &res)
        if ret == 0 { freeaddrinfo(res) }
        return ret == 0
    }

    // NWPathMonitor fires its handler immediately with the current path on start,
    // so the semaphore unblocks without waiting for a network event.
    private static func checkReachability(host: String) -> Bool {
        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        var reachable = false
        monitor.pathUpdateHandler = { path in
            reachable = path.status == .satisfied
            monitor.cancel()
            semaphore.signal()
        }
        monitor.start(queue: .global())
        semaphore.wait()
        return reachable
    }

    /// Non-blocking TCP connect with poll()-based timeout.
    private static func checkPort(host: String, port: Int, timeout: TimeInterval) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>? = nil
        guard getaddrinfo(host, String(port), &hints, &res) == 0, let addr = res else { return false }
        defer { freeaddrinfo(addr) }

        let sockfd = socket(Int32(addr.pointee.ai_family), SOCK_STREAM, 0)
        guard sockfd >= 0 else { return false }
        defer { Darwin.close(sockfd) }

        let f = fcntl(sockfd, F_GETFL, 0)
        guard f >= 0, fcntl(sockfd, F_SETFL, f | O_NONBLOCK) == 0 else { return false }

        let ret = Darwin.connect(sockfd, addr.pointee.ai_addr, addr.pointee.ai_addrlen)
        if ret == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pfd = pollfd(fd: sockfd, events: Int16(POLLOUT), revents: 0)
        let ms = Int32(min(timeout * 1000, Double(Int32.max)))
        guard poll(&pfd, 1, ms) > 0 else { return false }

        var sockErr: Int32 = 0
        var sockErrLen = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(sockfd, SOL_SOCKET, SO_ERROR, &sockErr, &sockErrLen)
        return sockErr == 0
    }

    // MARK: - Helpers

    private static func defaultPort(for scheme: String?) -> Int? {
        switch scheme?.lowercased() {
        case "smb":               return 445
        case "afp":               return 548
        case "nfs":               return 2049
        case "ftp":               return 21
        case "ftps":              return 990
        case "http", "webdav":    return 80
        case "https", "webdavs":  return 443
        default:                  return nil
        }
    }

    private static func isIPAddress(_ host: String) -> Bool {
        if host.contains(":") { return true }
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0) != nil }
    }
}
