import Foundation

enum DriveType: String, Codable, CaseIterable {
    case smb, nfs, ftp, afp, other

    var displayName: String {
        switch self {
        case .smb:   return "SMB"
        case .nfs:   return "NFS"
        case .ftp:   return "FTP"
        case .afp:   return "AFP (Apple)"
        case .other: return "Other / URI"
        }
    }

    static func infer(from url: String) -> DriveType {
        switch URL(string: url)?.scheme?.lowercased() {
        case "smb":  return .smb
        case "nfs":  return .nfs
        case "ftp":  return .ftp
        case "afp":  return .afp
        default:     return .other
        }
    }
}

struct NetworkDrive: Codable, Identifiable, Hashable {
    var id: UUID
    var url: String
    var driveType: DriveType
    var label: String?

    var checkHostReachability: Bool
    var checkDNSResolution: Bool
    var checkPortAvailability: Bool

    // Custom decode for backwards compatibility with stored drives that predate these fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        url = try c.decode(String.self, forKey: .url)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        checkHostReachability = try c.decodeIfPresent(Bool.self, forKey: .checkHostReachability) ?? false
        checkDNSResolution = try c.decodeIfPresent(Bool.self, forKey: .checkDNSResolution) ?? false
        checkPortAvailability = try c.decodeIfPresent(Bool.self, forKey: .checkPortAvailability) ?? false
        // Infers from URL scheme for drives saved before this field existed.
        driveType = try c.decodeIfPresent(DriveType.self, forKey: .driveType) ?? DriveType.infer(from: url)
    }

    init(id: UUID, url: String, driveType: DriveType = .other, label: String?,
         checkHostReachability: Bool = false,
         checkDNSResolution: Bool = false,
         checkPortAvailability: Bool = false) {
        self.id = id
        self.url = url
        self.driveType = driveType
        self.label = label
        self.checkHostReachability = checkHostReachability
        self.checkDNSResolution = checkDNSResolution
        self.checkPortAvailability = checkPortAvailability
    }

    var schemeLabel: String {
        URL(string: url)?.scheme?.uppercased() ?? "?"
    }

    var displayName: String {
        if let label, !label.isEmpty {
            return label
        }
        if let parsed = URL(string: url), let host = parsed.host {
            if let share = parsed.pathComponents.dropFirst().first {
                return "\(host)/\(share)"
            }
            return host
        }
        return url
    }

    /// Grouping key for drives sharing the same server: "scheme://host[:port]".
    var hostGroupKey: String {
        guard let parsed = URL(string: url), let host = parsed.host else { return url }
        let scheme = parsed.scheme ?? ""
        let port = parsed.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host.lowercased())\(port)"
    }

    /// Bare hostname for display in group headers.
    var normalizedHostDisplay: String {
        URL(string: url)?.host?.lowercased() ?? url
    }
}
