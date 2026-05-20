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
    var dotIsTeal: Bool {
        let enabled = [dns, reachable, port].filter { $0 != .disabled && $0 != .skipped }
        return !enabled.isEmpty && enabled.allSatisfy { $0 == .passed }
    }
}

final class DriveAvailabilityChecker {
    static let shared = DriveAvailabilityChecker()

    // Max 6 host checks run concurrently; prevents saturating the network stack
    // when many drives are configured.
    private let hostQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.menubarfs.availability"
        q.maxConcurrentOperationCount = 6
        q.qualityOfService = .userInitiated
        return q
    }()

    private enum Timeout {
        static let dns:     TimeInterval = 0.2   // getaddrinfo cap
        static let tcp:     TimeInterval = 0.5   // non-blocking connect poll
        static let postDNS: TimeInterval = 0.8   // reachability + port budget
        static let batch:   TimeInterval = 1.0   // whole checkAll wall-clock cap
    }

    private struct HostResult {
        var dns:      DriveAvailabilityResult.Status = .disabled
        var reachable: DriveAvailabilityResult.Status = .disabled
        var port:     DriveAvailabilityResult.Status = .disabled
    }

    private init() {}

    // MARK: - Public API

    /// Runs all checks off the main thread; delivers results on the main queue.
    func checkAllAsync(_ drives: [NetworkDrive], completion: @escaping ([UUID: DriveAvailabilityResult]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let results = self.checkAll(drives)
            DispatchQueue.main.async { completion(results) }
        }
    }

    /// Checks all drives, deduplicating by host+scheme+port.
    /// Blocks the caller for at most Timeout.batch seconds.
    func checkAll(_ drives: [NetworkDrive]) -> [UUID: DriveAvailabilityResult] {
        var results = [UUID: DriveAvailabilityResult]()
        let lock = NSLock()
        let group = DispatchGroup()

        // Drives with all checks disabled: record immediately, no network needed.
        for drive in drives where !drive.checkDNSResolution && !drive.checkHostReachability && !drive.checkPortAvailability {
            results[drive.id] = DriveAvailabilityResult(driveID: drive.id, dns: .disabled, reachable: .disabled, port: .disabled)
        }

        // Deduplicate by hostGroupKey (scheme://host:port).
        // Drives sharing the same key get one network check; results are fanned out.
        var groups: [String: [NetworkDrive]] = [:]
        for drive in drives where drive.checkDNSResolution || drive.checkHostReachability || drive.checkPortAvailability {
            groups[drive.hostGroupKey, default: []].append(drive)
        }

        for (_, groupDrives) in groups {
            guard let first   = groupDrives.first,
                  let parsed  = URL(string: first.url),
                  let host    = parsed.host else { continue }

            let port    = parsed.port ?? Self.defaultPort(for: parsed.scheme)
            let isIP    = Self.isIPAddress(host)
            // Union of enabled checks across all drives in the group.
            let runDNS  = groupDrives.contains { $0.checkDNSResolution }
            let runPing = groupDrives.contains { $0.checkHostReachability }
            let runPort = groupDrives.contains { $0.checkPortAvailability }

            group.enter()
            hostQueue.addOperation {
                let hostResult = self.checkHost(
                    host: host, port: port, isIP: isIP,
                    runDNS: runDNS, runPing: runPing, runPort: runPort
                )
                lock.lock()
                for drive in groupDrives {
                    results[drive.id] = DriveAvailabilityResult(
                        driveID:   drive.id,
                        dns:       drive.checkDNSResolution    ? hostResult.dns       : .disabled,
                        reachable: drive.checkHostReachability ? hostResult.reachable : .disabled,
                        port:      drive.checkPortAvailability ? hostResult.port      : .disabled
                    )
                }
                lock.unlock()
                group.leave()
            }
        }

        _ = group.wait(timeout: .now() + Timeout.batch)
        return results
    }

    // MARK: - Per-host check

    private func checkHost(host: String, port: Int?, isIP: Bool,
                           runDNS: Bool, runPing: Bool, runPort: Bool) -> HostResult {
        // Phase 1: DNS (200 ms cap, sequential).
        // Failure short-circuits phases 2+; IP addresses skip DNS entirely.
        let dns: DriveAvailabilityResult.Status
        if !runDNS {
            dns = .disabled
        } else if isIP {
            dns = .skipped
        } else {
            dns = Self.checkDNS(host: host, timeout: Timeout.dns) ? .passed : .failed
        }

        guard dns != .failed else {
            return HostResult(
                dns:       dns,
                reachable: runPing ? .skipped : .disabled,
                port:      runPort ? .skipped : .disabled
            )
        }

        // Phase 2: Reachability + port in parallel (0.8 s budget after DNS).
        var reachable:  DriveAvailabilityResult.Status = runPing               ? .timedOut : .disabled
        var portStatus: DriveAvailabilityResult.Status = (runPort && port != nil) ? .timedOut : .disabled

        let lock = NSLock()
        let innerGroup = DispatchGroup()

        if runPing {
            innerGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let r: DriveAvailabilityResult.Status = Self.checkReachability() ? .passed : .failed
                lock.lock(); reachable = r; lock.unlock()
                innerGroup.leave()
            }
        }

        if runPort, let p = port {
            innerGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let r: DriveAvailabilityResult.Status = Self.checkPort(host: host, port: p) ? .passed : .failed
                lock.lock(); portStatus = r; lock.unlock()
                innerGroup.leave()
            }
        }

        _ = innerGroup.wait(timeout: .now() + Timeout.postDNS)

        lock.lock()
        let result = HostResult(dns: dns, reachable: reachable, port: portStatus)
        lock.unlock()
        return result
    }

    // MARK: - Individual checks

    /// Resolves a hostname with a hard timeout. Returns false on timeout or failure.
    /// getaddrinfo has no built-in timeout, so we dispatch it and cap the wait.
    private static func checkDNS(host: String, timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var resolved = false
        DispatchQueue.global(qos: .utility).async {
            var hints = addrinfo()
            hints.ai_family   = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM
            var res: UnsafeMutablePointer<addrinfo>? = nil
            let ret = getaddrinfo(host, nil, &hints, &res)
            if ret == 0 { freeaddrinfo(res) }
            resolved = ret == 0
            semaphore.signal()
        }
        return semaphore.wait(timeout: .now() + timeout) != .timedOut && resolved
    }

    /// Checks general network reachability via NWPathMonitor.
    /// Note: this reflects whether any network path exists, not host-specific reachability.
    /// NWPathMonitor fires immediately with the current path, so the semaphore unblocks
    /// without waiting for a network event.
    private static func checkReachability() -> Bool {
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

    /// Non-blocking TCP connect with poll()-based 500 ms timeout.
    private static func checkPort(host: String, port: Int) -> Bool {
        var hints = addrinfo()
        hints.ai_family   = AF_UNSPEC
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
        let ms  = Int32(Timeout.tcp * 1000)
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
