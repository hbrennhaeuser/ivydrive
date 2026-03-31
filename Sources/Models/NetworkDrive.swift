import Foundation

struct NetworkDrive: Codable, Identifiable, Hashable {
    var id: UUID
    var url: String
    var label: String?
    var autoConnect: Bool

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
}
