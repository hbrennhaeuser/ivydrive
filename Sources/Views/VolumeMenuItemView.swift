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

final class VolumeMenuItemView: NSView {
    private let nameLabel: NSTextField
    private let ejectButton: EjectButtonView
    private let iconView: NSImageView

    init(icon: NSImage, name: String, onEject: @escaping () -> Void) {
        iconView = NSImageView(image: icon)

        nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .menuFont(ofSize: 0)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.isEditable = false
        nameLabel.isBordered = false
        nameLabel.drawsBackground = false

        ejectButton = EjectButtonView(frame: .zero)
        ejectButton.onEject = onEject

        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 22))
        autoresizingMask = .width

        for v in [iconView, nameLabel, ejectButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 19),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            ejectButton.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
            ejectButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            ejectButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            ejectButton.widthAnchor.constraint(equalToConstant: 20),
            ejectButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseUp(with event: NSEvent) {
        // Only eject button handles clicks; ignore clicks elsewhere on the row
    }
}
