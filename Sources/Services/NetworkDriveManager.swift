import Foundation
import NetFS
import AppKit

enum DriveMountOutcome {
    case mounted
    case requiresUserInteraction
    case failed(String)
}

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
        guard let driveURL = URL(string: drive.url), let driveHost = driveURL.host else { return nil }
        let normalizedHost = driveHost.lowercased()
        let normalizedPath = driveURL.path
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // currentMounts() uses getfsstat(MNT_NOWAIT) — never contacts remote volumes,
        // so it cannot block even if a network drive is mounted but unreachable.
        for mount in currentMounts() where !mount.isLocal {
            guard let (mfHost, mfPath) = parseRemoteSource(mount.source) else { continue }
            guard mfHost == normalizedHost else { continue }
            let normalizedMfPath = mfPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard normalizedMfPath == normalizedPath else { continue }
            return URL(fileURLWithPath: mount.mountPoint)
        }
        return nil
    }

    func isMounted(_ drive: NetworkDrive) -> Bool {
        mountPoint(for: drive) != nil
    }

    // MARK: - Mount

    func mount(_ drive: NetworkDrive, completion: @escaping (DriveMountOutcome) -> Void) {
        guard let url = URL(string: drive.url) else {
            completion(.failed("Invalid drive URL."))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var mountPoints: Unmanaged<CFArray>?
            let status = NetFSMountURLSync(
                url as CFURL,
                nil,
                nil,
                nil,
                nil,
                nil,
                &mountPoints
            )

            DispatchQueue.main.async {
                guard status != 0 else {
                    completion(.mounted)
                    return
                }

                if NSWorkspace.shared.open(url) {
                    completion(.requiresUserInteraction)
                } else {
                    completion(.failed("Could not start the connection request."))
                }
            }
        }
    }
}
