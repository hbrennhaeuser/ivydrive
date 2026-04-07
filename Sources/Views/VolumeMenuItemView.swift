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
        onEject?()
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
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
        NSColor.labelColor.withAlphaComponent(0.18).setFill()
        bg.fill()

        let fillWidth = bounds.width * fraction
        guard fillWidth > 0 else { return }
        let fillRect = NSRect(x: 0, y: 0, width: fillWidth, height: bounds.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
        NSColor.labelColor.withAlphaComponent(0.55).setFill()
        fill.fill()
    }
}

/// Header row for a group of connected volumes sharing the same server host.
/// Optionally shows a capacity bar when all volumes in the group have identical total capacity.
/// Not interactive — no hover, no eject.
final class VolumeGroupHeaderView: NSView {
    init(host: String, capacity: VolumeCapacity?) {
        let label = NSTextField(labelWithString: host)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false

        let ud = UserDefaults.standard
        let showBar   = capacity != nil && ud.bool(forKey: "showCapacityLine")
        let showStats = showBar && ud.bool(forKey: "showCapacityStats")

        var totalHeight: CGFloat = 24
        let barView: CapacityBarView? = showBar ? CapacityBarView(fraction: capacity!.fraction) : nil
        if barView != nil { totalHeight += 8 }

        let statsTF: NSTextField?
        if showStats, let cap = capacity {
            let pct = Int(cap.fraction * 100)
            let tf = NSTextField(labelWithString:
                "Used \(formatBytes(cap.usedBytes)) from \(formatBytes(cap.totalBytes)) (\(pct)%)")
            tf.font = .systemFont(ofSize: 10)
            tf.textColor = .secondaryLabelColor
            tf.isEditable = false
            tf.isBordered = false
            tf.drawsBackground = false
            statsTF = tf
            totalHeight += 14
        } else {
            statsTF = nil
        }

        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: totalHeight))
        autoresizingMask = .width

        for v in ([label, barView, statsTF] as [NSView?]).compactMap({ $0 }) {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        var c: [NSLayoutConstraint] = [
            heightAnchor.constraint(equalToConstant: totalHeight),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
        ]

        if barView == nil {
            c.append(label.centerYAnchor.constraint(equalTo: centerYAnchor))
        } else {
            c.append(label.topAnchor.constraint(equalTo: topAnchor, constant: 4))
        }

        if let bar = barView {
            c += [
                bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
                bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                bar.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 2),
                bar.heightAnchor.constraint(equalToConstant: 4),
            ]
        }

        if let stats = statsTF {
            let anchor: NSView = barView ?? label
            c += [
                stats.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
                stats.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                stats.topAnchor.constraint(equalTo: anchor.bottomAnchor, constant: 2),
            ]
        }

        NSLayoutConstraint.activate(c)
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class VolumeMenuItemView: NSView {
    private let nameLabel: NSTextField
    private let ejectButton: EjectButtonView
    private let spinner: NSProgressIndicator
    private let iconView: NSImageView
    private let volumeURL: URL
    private let deviceType: DeviceType
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(icon: NSImage, name: String, volumeURL: URL, deviceType: DeviceType, capacity: VolumeCapacity? = nil, operation: DriveOperation? = nil, indented: Bool = false, onEject: @escaping () -> Void) {
        self.volumeURL = volumeURL
        self.deviceType = deviceType
        let isEjecting = operation == .ejecting

        let ud = UserDefaults.standard
        let showBar   = capacity != nil && ud.bool(forKey: "showCapacityLine")
        let showStats = showBar && ud.bool(forKey: "showCapacityStats")

        let hasCap   = showBar && capacity != nil
        let fraction = hasCap ? capacity!.fraction : 0.0
        let usedBytes  = capacity?.usedBytes  ?? 0
        let totalBytes = capacity?.totalBytes ?? 0

        iconView = NSImageView(image: icon)

        nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .menuFont(ofSize: 0)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isEditable = false
        nameLabel.isBordered = false
        nameLabel.drawsBackground = false

        ejectButton = EjectButtonView(frame: .zero)
        ejectButton.isHidden = true

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isHidden = !isEjecting
        if isEjecting { spinner.startAnimation(nil) }

        // Height grows downward from the base 28 pt icon row.
        var totalHeight: CGFloat = 28
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

        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: totalHeight))
        autoresizingMask = .width

        for v in ([iconView, nameLabel, ejectButton, spinner, barView, statsTF] as [NSView?]).compactMap({ $0 }) {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        var c: [NSLayoutConstraint] = [
            heightAnchor.constraint(equalToConstant: totalHeight),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: indented ? 28 : 20),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            ejectButton.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            ejectButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            ejectButton.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            ejectButton.widthAnchor.constraint(equalToConstant: 20),
            ejectButton.heightAnchor.constraint(equalToConstant: 20),

            spinner.centerXAnchor.constraint(equalTo: ejectButton.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: ejectButton.centerYAnchor),
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

        ejectButton.onEject = { [weak self] in
            self?.showEjecting()
            onEject()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func showEjecting() {
        ejectButton.isHidden = true
        spinner.isHidden = false
        spinner.startAnimation(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHovered else { return }
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 2), xRadius: 5, yRadius: 5).fill()
    }

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
        ejectButton.isHidden = false
        guard UserDefaults.standard.bool(forKey: "showHoverInfo") else { return }
        // Fetch resource values on a background thread — this call can block
        // when a network volume is mounted but the network is unreachable.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let rows = DriveInfoPanel.rowsForMountedVolume(at: self.volumeURL, deviceType: self.deviceType)
            DispatchQueue.main.async {
                DriveInfoPanel.shared.show(rows: rows, anchoredTo: self)
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
        ejectButton.isHidden = true
        DriveInfoPanel.shared.hide()
    }

    override func mouseUp(with event: NSEvent) {
        guard UserDefaults.standard.bool(forKey: "clickVolumeToOpenInFinder") else { return }
        NSWorkspace.shared.open(volumeURL)
        enclosingMenuItem?.menu?.cancelTracking()
    }
}
