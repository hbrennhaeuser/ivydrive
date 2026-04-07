import Foundation

enum DeviceType: Int, Comparable {
    case optical = 0
    case usb = 1
    case diskImage = 2
    case network = 3
    case other = 4

    static func < (lhs: DeviceType, rhs: DeviceType) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct MountedVolume: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let deviceType: DeviceType
    let volumeURL: URL
}

struct VolumeCapacity {
    let usedBytes: Int
    let totalBytes: Int
    let isReadOnly: Bool

    var fraction: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
}
