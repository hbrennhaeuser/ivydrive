import Foundation
import NetFS
import AppKit

final class NetworkDriveManager: ObservableObject {
    @Published var drives: [NetworkDrive] = []

    private static let storageKey = "configured_network_drives"

    init() {
        load()
    }

    // MARK: - CRUD

    func add(_ drive: NetworkDrive) {
        drives.append(drive)
        save()
    }

    func remove(_ drive: NetworkDrive) {
        drives.removeAll { $0.id == drive.id }
        KeychainHelper.delete(for: drive.id)
        save()
    }

    func update(_ drive: NetworkDrive) {
        guard let index = drives.firstIndex(where: { $0.id == drive.id }) else { return }
        drives[index] = drive
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([NetworkDrive].self, from: data) else { return }
        drives = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(drives) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    // MARK: - Mount Status

    func mountPoint(for drive: NetworkDrive) -> URL? {
        guard let driveURL = URL(string: drive.url) else { return nil }
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeURLForRemountingKey],
            options: []
        ) ?? []

        return volumes.first { url in
            guard let values = try? url.resourceValues(forKeys: [.volumeURLForRemountingKey]),
                  let remountURL = values.volumeURLForRemounting else { return false }
            return remountURL.host?.lowercased() == driveURL.host?.lowercased()
                && remountURL.path.lowercased() == driveURL.path.lowercased()
        }
    }

    func isMounted(_ drive: NetworkDrive) -> Bool {
        mountPoint(for: drive) != nil
    }

    // MARK: - Mount

    func mount(_ drive: NetworkDrive) {
        guard let url = URL(string: drive.url) else { return }
        let credentials = KeychainHelper.load(for: drive.id)

        DispatchQueue.global(qos: .userInitiated).async {
            var mountPoints: Unmanaged<CFArray>?
            let status = NetFSMountURLSync(
                url as CFURL,
                nil,
                credentials?.username as CFString?,
                credentials?.password as CFString?,
                nil,
                nil,
                &mountPoints
            )

            if status != 0 {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
