import Cocoa

// Custom pill view draws its own background/border/text to avoid NSTextField's
// rectangular background clipping and vertical centering limitations.
private final class ConnectPillView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: inset, xRadius: 9, yRadius: 9)

        NSColor.unemphasizedSelectedContentBackgroundColor.setFill()
        path.fill()

        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        let str = "Connect" as NSString
        let sz = str.size(withAttributes: attrs)
        let pt = NSPoint(
            x: round((bounds.width - sz.width) / 2),
            y: round((bounds.height - sz.height) / 2)
        )
        str.draw(at: pt, withAttributes: attrs)
    }
}

final class NetworkDriveMenuItemView: NSView {
    private let dotView: NSView
    private let nameLabel: NSTextField
    private let connectPill: ConnectPillView
    private let drive: NetworkDrive
    private let isConnected: Bool
    private let mountPoint: URL?
    private let availability: DriveAvailabilityResult?
    private let onAction: () -> Void
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
            dotColor = .systemTeal
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

        connectPill = ConnectPillView(frame: .zero)
        connectPill.isHidden = true

        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 22))
        autoresizingMask = .width

        for v in [dotView, nameLabel, connectPill] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),

            dotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 23),
            dotView.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 8),
            dotView.heightAnchor.constraint(equalToConstant: 8),

            nameLabel.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            connectPill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            connectPill.centerYAnchor.constraint(equalTo: centerYAnchor),
            connectPill.widthAnchor.constraint(equalToConstant: 62),
            connectPill.heightAnchor.constraint(equalToConstant: 18),
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
        if !isConnected { connectPill.isHidden = false }
        let rows: [(label: String, value: String)]
        if isConnected, let mp = mountPoint {
            rows = DriveInfoPanel.rowsForMountedVolume(at: mp)
        } else {
            rows = DriveInfoPanel.rowsForUnmountedDrive(drive, availability: availability)
        }
        DriveInfoPanel.shared.show(rows: rows, anchoredTo: self)
    }

    override func mouseExited(with event: NSEvent) {
        connectPill.isHidden = true
        DriveInfoPanel.shared.hide()
    }

    override func mouseUp(with event: NSEvent) {
        guard !isConnected else { return }
        let local = convert(event.locationInWindow, from: nil)
        guard connectPill.frame.insetBy(dx: -4, dy: -4).contains(local) else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        onAction()
    }
}
