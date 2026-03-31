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
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey
        ]

        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) ?? []

        return urls.compactMap { url -> MountedVolume? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }

            let isEjectable = values.volumeIsEjectable ?? false
            let isRemovable = values.volumeIsRemovable ?? false
            let isInternal = values.volumeIsInternal ?? true
            let isLocal = values.volumeIsLocal ?? true

            guard url.path != "/" else { return nil }
            guard !url.path.hasPrefix("/System/") else { return nil }
            guard isEjectable || isRemovable || !isInternal || !isLocal else { return nil }

            return MountedVolume(
                name: values.volumeName ?? url.lastPathComponent,
                path: url.path,
                isRemovable: isRemovable,
                isNetwork: !isLocal,
                isInternal: isInternal,
                volumeURL: url
            )
        }
    }
}
