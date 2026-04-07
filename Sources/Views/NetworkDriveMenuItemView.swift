import Cocoa

private final class StatusBubbleView: NSView {
    init(fillColor: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = fillColor.cgColor

        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        let image = NSImage(systemSymbolName: "network", accessibilityDescription: nil)
            .flatMap { $0.withSymbolConfiguration(config) }
        let iv = NSImageView(image: image ?? NSImage())
        iv.contentTintColor = .white
        iv.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iv)
        NSLayoutConstraint.activate([
            iv.centerXAnchor.constraint(equalTo: centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Header row for a group of drives sharing the same server host.
/// When onConnect is provided the row is interactive: it highlights on hover
/// and triggers a connect-all for the group on click.
final class NetworkGroupHeaderView: NSView {
    private let onConnect: (() -> Void)?
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(host: String, onConnect: (() -> Void)? = nil) {
        self.onConnect = onConnect

        let label = NSTextField(labelWithString: host)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false

        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        autoresizingMask = .width

        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard isHovered, onConnect != nil else { return }
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 2), xRadius: 5, yRadius: 5).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard onConnect != nil else { return }
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
        guard let action = onConnect else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        action()
    }
}

final class NetworkDriveMenuItemView: NSView {
    private let bubbleView: StatusBubbleView
    private let spinner: NSProgressIndicator
    private let nameLabel: NSTextField
    private let drive: NetworkDrive
    private let isConnected: Bool
    private let isInProgress: Bool
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
        operation: DriveOperation? = nil,
        indented: Bool = false,
        onAction: @escaping () -> Void
    ) {
        self.drive = drive
        self.isConnected = connected
        self.isInProgress = operation == .connecting
        self.mountPoint = mountPoint
        self.availability = availability
        self.onAction = onAction

        let fillColor: NSColor
        if connected {
            fillColor = .systemGreen
        } else if let avail = availability {
            let allDisabled = [avail.dns, avail.reachable, avail.port]
                .allSatisfy { $0 == .disabled || $0 == .skipped }
            if allDisabled {
                fillColor = NSColor.labelColor.withAlphaComponent(0.25)
            } else if avail.dotIsTeal {
                fillColor = .systemBlue
            } else {
                fillColor = .systemRed
            }
        } else {
            fillColor = NSColor.labelColor.withAlphaComponent(0.25)
        }

        bubbleView = StatusBubbleView(fillColor: fillColor)
        bubbleView.alphaValue = operation == .connecting ? 0 : 1

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isHidden = operation != .connecting

        nameLabel = NSTextField(labelWithString: drive.displayName)
        nameLabel.font = .menuFont(ofSize: 0)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isEditable = false
        nameLabel.isBordered = false
        nameLabel.drawsBackground = false

        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 28))
        autoresizingMask = .width

        for v in [bubbleView, spinner, nameLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        if operation == .connecting { spinner.startAnimation(nil) }

        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),

            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: indented ? 28 : 20),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: bubbleView.leadingAnchor, constant: -8),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            bubbleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            bubbleView.widthAnchor.constraint(equalToConstant: 18),
            bubbleView.heightAnchor.constraint(equalToConstant: 18),

            spinner.centerXAnchor.constraint(equalTo: bubbleView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: bubbleView.centerYAnchor),
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
        DriveInfoPanel.shared.hide()
    }

    override func mouseUp(with event: NSEvent) {
        guard !isConnected, !isInProgress else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        onAction()
    }
}
