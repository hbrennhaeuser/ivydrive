import Darwin
import Foundation

/// A lightweight snapshot of one entry from the kernel mount table.
struct MountEntry {
    let mountPoint: String  // f_mntonname  — e.g. "/Volumes/MyShare"
    let source: String      // f_mntfromname — e.g. "//server/share"
    let fsType: String      // f_fstypename  — e.g. "smbfs"
    let isLocal: Bool       // true when MNT_LOCAL flag is set
}

/// Returns a snapshot of all mounted volumes from the kernel with no blocking I/O.
/// Uses MNT_NOWAIT so it never contacts remote volumes regardless of reachability.
func currentMounts() -> [MountEntry] {
    let count = getfsstat(nil, 0, MNT_NOWAIT)
    guard count > 0 else { return [] }
    // Use Darwin.statfs to resolve the ambiguity between the struct and the C function.
    var buf = Array<Darwin.statfs>(repeating: Darwin.statfs(), count: Int(count))
    let actual = getfsstat(&buf, Int32(MemoryLayout<Darwin.statfs>.size * Int(count)), MNT_NOWAIT)
    guard actual > 0 else { return [] }

    return buf.prefix(Int(actual)).map { entry in
        MountEntry(
            mountPoint: cStringTuple(entry.f_mntonname),
            source:     cStringTuple(entry.f_mntfromname),
            fsType:     cStringTuple(entry.f_fstypename),
            isLocal:    entry.f_flags & UInt32(MNT_LOCAL) != 0
        )
    }
}

/// Extracts (host, path) from a raw f_mntfromname value.
/// Handles common macOS formats:
///   - Standard URL:              afp://host/share, smb://host/share
///   - Slash-prefixed (no scheme): //[domain;user@]host/share
///   - NFS colon form:            host:/export/path
func parseRemoteSource(_ source: String) -> (host: String, path: String)? {
    // Standard URL — handles afp://, smb://, https://, etc.
    if let url = URL(string: source), let host = url.host {
        return (host.lowercased(), url.path.lowercased())
    }

    // Slash-prefixed form (no scheme): //[domain;user@]host/path
    var s = source
    while s.hasPrefix("/") { s = String(s.dropFirst()) }

    if !s.isEmpty, let slashRange = s.range(of: "/") {
        var hostPart = String(s[..<slashRange.lowerBound])
        if let semiIdx = hostPart.firstIndex(of: ";") {
            hostPart = String(hostPart[hostPart.index(after: semiIdx)...])
        }
        if let atIdx = hostPart.lastIndex(of: "@") {
            hostPart = String(hostPart[hostPart.index(after: atIdx)...])
        }
        let path = String(s[slashRange.lowerBound...])
        return (hostPart.lowercased(), path.lowercased())
    }

    // NFS form: host:/path
    if let colonIdx = s.firstIndex(of: ":"),
       s.index(after: colonIdx) < s.endIndex,
       s[s.index(after: colonIdx)] == "/" {
        return (String(s[..<colonIdx]).lowercased(), String(s[s.index(after: colonIdx)...]).lowercased())
    }

    return nil
}

// Reads a fixed-size C-string stored as a Swift tuple (e.g. statfs char arrays).
private func cStringTuple<T>(_ tuple: T) -> String {
    withUnsafeBytes(of: tuple) { bytes in
        String(cString: bytes.bindMemory(to: CChar.self).baseAddress!)
    }
}
