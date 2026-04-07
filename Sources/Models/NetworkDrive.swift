import Foundation

struct NetworkDrive: Codable, Identifiable, Hashable {
    var id: UUID
    var url: String
    var label: String?
    var autoConnect: Bool

    var checkHostReachability: Bool
    var checkDNSResolution: Bool
    var checkPortAvailability: Bool

    // Custom decode for backwards compatibility with stored drives that predate these fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        url = try c.decode(String.self, forKey: .url)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        autoConnect = try c.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? false
        checkHostReachability = try c.decodeIfPresent(Bool.self, forKey: .checkHostReachability) ?? false
        checkDNSResolution = try c.decodeIfPresent(Bool.self, forKey: .checkDNSResolution) ?? false
        checkPortAvailability = try c.decodeIfPresent(Bool.self, forKey: .checkPortAvailability) ?? false
    }

    init(id: UUID, url: String, label: String?, autoConnect: Bool,
         checkHostReachability: Bool = false,
         checkDNSResolution: Bool = false,
         checkPortAvailability: Bool = false) {
        self.id = id
        self.url = url
        self.label = label
        self.autoConnect = autoConnect
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
