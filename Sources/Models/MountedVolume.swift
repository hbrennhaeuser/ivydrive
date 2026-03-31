import Foundation

struct MountedVolume: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isRemovable: Bool
    let isNetwork: Bool
    let isInternal: Bool
    let volumeURL: URL
}
