import Cocoa

final class EjectButtonView: NSView {
    private let imageView: NSImageView
    private var isHovered = false
    private var trackingArea: NSTrackingArea?
    var onEject: (() -> Void)?

    override init(frame: NSRect) {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        let image = NSImage(
            systemSymbolName: "eject.fill",
            accessibilityDescription: "Eject"
        )?.withSymbolConfiguration(config)
        imageView = NSImageView(image: image ?? NSImage())
        imageView.contentTintColor = .tertiaryLabelColor

        super.init(frame: frame)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 12),
            imageView.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard bounds.contains(local) else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        onEject?()
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
            let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            circle.fill()
            imageView.contentTintColor = .labelColor
        } else {
            imageView.contentTintColor = .tertiaryLabelColor
        }
    }
}

// MARK: - Capacity Bar

private final class CapacityBarView: NSView {
    private let fraction: Double

    init(fraction: Double) {
        self.fraction = min(max(fraction, 0), 1)
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2)
        NSColor.separatorColor.withAlphaComponent(0.3).setFill()
        bg.fill()

        let fillWidth = bounds.width * fraction
        guard fillWidth > 0 else { return }
        let fillRect = NSRect(x: 0, y: 0, width: fillWidth, height: bounds.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
        NSColor.labelColor.withAlphaComponent(0.55).setFill()
        fill.fill()
    }
}

final class VolumeMenuItemView: NSView {
    private let nameLabel: NSTextField
    private let ejectButton: EjectButtonView
    private let iconView: NSImageView
    private let volumeURL: URL
    private let deviceType: DeviceType
    private var trackingArea: NSTrackingArea?

    init(icon: NSImage, name: String, volumeURL: URL, deviceType: DeviceType, onEject: @escaping () -> Void) {
        self.volumeURL = volumeURL
        self.deviceType = deviceType

        let ud = UserDefaults.standard
        let isReadOnly = (try? volumeURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true

        var capacityRelevant = true
        if isReadOnly && ud.bool(forKey: "hideCapacityForReadOnly") { capacityRelevant = false }

        let showBar   = capacityRelevant && ud.bool(forKey: "showCapacityLine")
        let showStats = showBar && ud.bool(forKey: "showCapacityStats")

        var usedBytes = 0
        var totalBytes = 0
        if showBar {
            let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]
            if let vals = try? volumeURL.resourceValues(forKeys: keys),
               let total = vals.volumeTotalCapacity,
               let free  = vals.volumeAvailableCapacity {
                usedBytes  = total - free
                totalBytes = total
            }
        }
        let hasCap   = totalBytes > 0
        let fraction = hasCap ? Double(usedBytes) / Double(totalBytes) : 0.0

        iconView = NSImageView(image: icon)

        nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .menuFont(ofSize: 0)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isEditable = false
        nameLabel.isBordered = false
        nameLabel.drawsBackground = false

        ejectButton = EjectButtonView(frame: .zero)
        ejectButton.onEject = onEject

        // Height grows downward from the base 22 pt icon row.
        var totalHeight: CGFloat = 22
        let barView: CapacityBarView? = (showBar && hasCap) ? CapacityBarView(fraction: fraction) : nil
        if barView != nil { totalHeight += 8 }   // 2 gap + 4 bar + 2 gap

        let statsTF: NSTextField?
        if showStats && hasCap {
            let pct = Int(fraction * 100)
            let tf = NSTextField(labelWithString:
                "Used \(formatBytes(usedBytes)) from \(formatBytes(totalBytes)) (\(pct)%)")
            tf.font = .systemFont(ofSize: 10)
            tf.textColor = .secondaryLabelColor
            tf.isEditable = false
            tf.isBordered = false
            tf.drawsBackground = false
            statsTF = tf
            totalHeight += 14  // 2 gap + 12 text height
        } else {
            statsTF = nil
        }

        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: totalHeight))
        autoresizingMask = .width

        for v in ([iconView, nameLabel, ejectButton, barView, statsTF] as [NSView?]).compactMap({ $0 }) {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        var c: [NSLayoutConstraint] = [
            heightAnchor.constraint(equalToConstant: totalHeight),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 19),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            ejectButton.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            ejectButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            ejectButton.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            ejectButton.widthAnchor.constraint(equalToConstant: 20),
            ejectButton.heightAnchor.constraint(equalToConstant: 20),
        ]

        if let bar = barView {
            c += [
                bar.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: ejectButton.trailingAnchor),
                bar.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 2),
                bar.heightAnchor.constraint(equalToConstant: 4),
            ]
        }

        if let stats = statsTF {
            let anchorView: NSView = barView ?? iconView
            c += [
                stats.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
                stats.trailingAnchor.constraint(equalTo: ejectButton.trailingAnchor),
                stats.topAnchor.constraint(equalTo: anchorView.bottomAnchor, constant: 2),
            ]
        }

        NSLayoutConstraint.activate(c)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        let rows = DriveInfoPanel.rowsForMountedVolume(at: volumeURL, deviceType: deviceType)
        DriveInfoPanel.shared.show(rows: rows, anchoredTo: self)
    }

    override func mouseExited(with event: NSEvent) {
        DriveInfoPanel.shared.hide()
    }

    override func mouseUp(with event: NSEvent) {
        // Only eject button handles clicks; ignore clicks elsewhere on the row
    }
}
