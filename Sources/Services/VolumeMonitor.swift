import Foundation
import DiskArbitration

final class VolumeMonitor {
    private var session: DASession?
    var onVolumesChanged: (() -> Void)?

    func start() {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return }
        self.session = session
        DASessionSetDispatchQueue(session, DispatchQueue.main)

        let context = Unmanaged.passUnretained(self).toOpaque()

        DARegisterDiskAppearedCallback(session, nil, { _, ctx in
            guard let ctx else { return }
            Unmanaged<VolumeMonitor>.fromOpaque(ctx).takeUnretainedValue().onVolumesChanged?()
        }, context)

        DARegisterDiskDisappearedCallback(session, nil, { _, ctx in
            guard let ctx else { return }
            Unmanaged<VolumeMonitor>.fromOpaque(ctx).takeUnretainedValue().onVolumesChanged?()
        }, context)

        DARegisterDiskDescriptionChangedCallback(session, nil, nil, { _, _, ctx in
            guard let ctx else { return }
            Unmanaged<VolumeMonitor>.fromOpaque(ctx).takeUnretainedValue().onVolumesChanged?()
        }, context)
    }

    func stop() {
        if let session {
            DASessionSetDispatchQueue(session, nil)
        }
        session = nil
    }

    static func ejectableVolumes() -> [MountedVolume] {
        // currentMounts() uses getfsstat(MNT_NOWAIT) — never contacts remote volumes,
        // so it cannot block even if a network drive is mounted but unreachable.
        return currentMounts().compactMap { mount -> MountedVolume? in
            guard mount.mountPoint != "/" && !mount.mountPoint.hasPrefix("/System/") else { return nil }

            let url = URL(fileURLWithPath: mount.mountPoint)

            if mount.isLocal {
                // Resource value queries are safe for local volumes.
                let keys: Set<URLResourceKey> = [
                    .volumeNameKey,
                    .volumeIsRemovableKey,
                    .volumeIsEjectableKey,
                    .volumeIsInternalKey,
                ]
                guard let values = try? url.resourceValues(forKeys: keys) else { return nil }

                let isEjectable = values.volumeIsEjectable ?? false
                let isRemovable = values.volumeIsRemovable ?? false
                let isInternal  = values.volumeIsInternal  ?? true

                guard isEjectable || isRemovable || !isInternal else { return nil }

                let deviceType = classifyDevice(
                    typeName:    mount.fsType,
                    isLocal:     true,
                    isRemovable: isRemovable,
                    isEjectable: isEjectable,
                    isInternal:  isInternal
                )
                return MountedVolume(
                    name:       values.volumeName ?? url.lastPathComponent,
                    path:       mount.mountPoint,
                    deviceType: deviceType,
                    volumeURL:  url,
                    remoteHost: nil
                )
            } else {
                // Network volume — do not query the filesystem to avoid blocking
                // when the volume is mounted but no longer reachable.
                return MountedVolume(
                    name:       url.lastPathComponent,
                    path:       mount.mountPoint,
                    deviceType: .network,
                    volumeURL:  url,
                    remoteHost: parseRemoteSource(mount.source)?.host
                )
            }
        }
        .sorted { ($0.deviceType, $0.name.lowercased()) < ($1.deviceType, $1.name.lowercased()) }
    }

    private static func classifyDevice(
        typeName: String,
        isLocal: Bool,
        isRemovable: Bool,
        isEjectable: Bool,
        isInternal: Bool
    ) -> DeviceType {
        if !isLocal { return .network }

        let opticalTypes = ["cd9660", "udf", "cddafs"]
        if opticalTypes.contains(typeName.lowercased()) && isRemovable {
            return .optical
        }

        if isRemovable { return .usb }

        // Ejectable + local + not removable + not internal = disk image
        if isEjectable && !isInternal { return .diskImage }

        return .other
    }
}
