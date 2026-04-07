import Cocoa
import SwiftUI

private struct DriveInfoView: View {
    let rows: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(rows[i].label + ":")
                        .frame(width: 66, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Text(rows[i].value)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        // Grows with content but never exceeds 360 pt.
        .frame(minWidth: 200, maxWidth: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separatorColor), lineWidth: 0.5)
        )
    }
}

final class DriveInfoPanel {
    static let shared = DriveInfoPanel()

    private let panel: NSPanel
    private var hostingView: NSHostingView<DriveInfoView>

    private init() {
        hostingView = NSHostingView(rootView: DriveInfoView(rows: []))
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 220, height: 60)),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hostingView
    }

    func show(rows: [(label: String, value: String)], anchoredTo view: NSView) {
        guard !rows.isEmpty, let viewWindow = view.window else { return }

        hostingView.rootView = DriveInfoView(rows: rows)
        let size = hostingView.fittingSize

        let viewFrameInWindow = view.convert(view.bounds, to: nil)
        let screenFrame = viewWindow.convertToScreen(viewFrameInWindow)
        let screenBounds = viewWindow.screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = screenFrame.maxX + 6
        if x + size.width > screenBounds.maxX - 10 {
            x = screenFrame.minX - size.width - 6
        }
        let y = screenFrame.maxY - size.height

        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }
}

// MARK: - Row builders

extension DriveInfoPanel {
    static func rowsForUnmountedDrive(
        _ drive: NetworkDrive,
        availability: DriveAvailabilityResult? = nil
    ) -> [(label: String, value: String)] {
        let parsedURL = URL(string: drive.url)
        let scheme = parsedURL?.scheme?.uppercased() ?? "—"

        var rows: [(String, String)] = [
            ("URL", drive.url),
            ("Type", scheme),
        ]

        if drive.checkDNSResolution {
            rows.append(("DNS", statusLabel(availability?.dns)))
        }
        if drive.checkHostReachability {
            rows.append(("Ping", statusLabel(availability?.reachable)))
        }
        if drive.checkPortAvailability {
            rows.append(("Port", statusLabel(availability?.port)))
        }

        return rows
    }

    private static func statusLabel(_ status: DriveAvailabilityResult.Status?) -> String {
        switch status {
        case .passed:        return "✓ OK"
        case .failed:        return "✗ Failed"
        case .timedOut:      return "Timeout"
        case .skipped:       return "Skipped"
        case .disabled, nil: return "—"
        }
    }

    static func rowsForMountedVolume(at url: URL, deviceType: DeviceType = .other) -> [(label: String, value: String)] {
        let capacityRelevant = deviceType == .usb || deviceType == .network || deviceType == .other
        var keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeURLForRemountingKey,
            .volumeIsReadOnlyKey,
            .volumeIsLocalKey,
            .volumeLocalizedFormatDescriptionKey,
        ]
        if capacityRelevant {
            keys.formUnion([.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        }
        guard let values = try? url.resourceValues(forKeys: keys) else { return [] }

        var rows: [(String, String)] = []

        if let name = values.volumeName {
            rows.append(("Name", name))
        }
        if let remount = values.volumeURLForRemounting {
            rows.append(("Mount URL", remount.absoluteString))
        }
        if let fsType = values.volumeLocalizedFormatDescription {
            rows.append(("Type", fsType))
        }

        if capacityRelevant, let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacity {
            let used = total - free
            let pct = total > 0 ? Int(Double(used) / Double(total) * 100) : 0
            rows.append(("Total", formatBytes(total)))
            rows.append(("Used", "\(formatBytes(used)) (\(pct)%)"))
            rows.append(("Free", formatBytes(free)))
        }

        rows.append(("Remote", (values.volumeIsLocal == true) ? "No" : "Yes"))
        rows.append(("Access", (values.volumeIsReadOnly == true) ? "Read-Only" : "Read/Write"))

        return rows
    }

}

func formatBytes(_ bytes: Int) -> String {
    let formatter = ByteCountFormatter()
    let binary = UserDefaults.standard.bool(forKey: "useBinaryUnits")
    formatter.countStyle = binary ? .binary : .decimal
    return formatter.string(fromByteCount: Int64(bytes))
}

extension DriveInfoPanel {

    // Detects plain IPv4 (four dot-separated integers) and IPv6 (contains colon).
    private static func isIPAddress(_ host: String) -> Bool {
        if host.contains(":") { return true }
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0) != nil }
    }
}
