import Cocoa

final class NetworkDriveMenuItemView: NSView {
    private let dotView: NSView
    private let nameLabel: NSTextField
    private let connectIconView: NSImageView
    private let drive: NetworkDrive
    private let isConnected: Bool
    private let mountPoint: URL?
    private let availability: DriveAvailabilityResult?
    private let onAction: () -> Void
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(
        drive: NetworkDrive,
        connected: Bool,
        mountPoint: URL?,
        availability: DriveAvailabilityResult? = nil,
        onAction: @escaping () -> Void
    ) {
        self.drive = drive
        self.isConnected = connected
        self.mountPoint = mountPoint
        self.availability = availability
        self.onAction = onAction

        let dotColor: NSColor
        if connected {
            dotColor = .systemGreen
        } else if let avail = availability, avail.dotIsTeal {
            dotColor = .systemBlue
        } else {
            dotColor = .systemRed
        }

        dotView = NSView(frame: .zero)
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 4
        dotView.layer?.backgroundColor = dotColor.cgColor

        nameLabel = NSTextField(labelWithString: drive.displayName)
        nameLabel.font = .menuFont(ofSize: 0)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isEditable = false
        nameLabel.isBordered = false
        nameLabel.drawsBackground = false

        let iconConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        let iconImage = connected ? nil : NSImage(
            systemSymbolName: "cable.connector",
            accessibilityDescription: "Connect"
        )?.withSymbolConfiguration(iconConfig)
        connectIconView = NSImageView(image: iconImage ?? NSImage())
        connectIconView.contentTintColor = .secondaryLabelColor
        connectIconView.isHidden = true

        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 28))
        autoresizingMask = .width

        for v in [dotView, nameLabel, connectIconView] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),

            // Name anchored to the left edge (mirrors macOS Wi-Fi menu layout)
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: connectIconView.leadingAnchor, constant: -8),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Connect icon sits to the left of the dot (only shown on hover)
            connectIconView.trailingAnchor.constraint(equalTo: dotView.leadingAnchor, constant: -6),
            connectIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            connectIconView.widthAnchor.constraint(equalToConstant: 16),
            connectIconView.heightAnchor.constraint(equalToConstant: 16),

            // Status dot on the right (mirrors lock icon position in Wi-Fi menu)
            dotView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 8),
            dotView.heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

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
        if !isConnected { connectIconView.isHidden = false }
        if isConnected, let mp = mountPoint {
            // Fetch resource values on a background thread — this call can block
            // when a network volume is mounted but the network is unreachable.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                let rows = DriveInfoPanel.rowsForMountedVolume(at: mp)
                DispatchQueue.main.async {
                    DriveInfoPanel.shared.show(rows: rows, anchoredTo: self)
                }
            }
        } else {
            let rows = DriveInfoPanel.rowsForUnmountedDrive(drive, availability: availability)
            DriveInfoPanel.shared.show(rows: rows, anchoredTo: self)
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
        connectIconView.isHidden = true
        DriveInfoPanel.shared.hide()
    }

    override func mouseUp(with event: NSEvent) {
        guard !isConnected else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        onAction()
    }
}
