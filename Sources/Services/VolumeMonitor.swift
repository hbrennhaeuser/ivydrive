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
            .volumeIsLocalKey,
            .volumeTypeNameKey
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

            let deviceType = classifyDevice(
                typeName: values.volumeTypeName ?? "",
                isLocal: isLocal,
                isRemovable: isRemovable,
                isEjectable: isEjectable,
                isInternal: isInternal
            )

            return MountedVolume(
                name: values.volumeName ?? url.lastPathComponent,
                path: url.path,
                deviceType: deviceType,
                volumeURL: url
            )
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
