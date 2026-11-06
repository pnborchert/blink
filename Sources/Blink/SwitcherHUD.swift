import AppKit
import BlinkCore

/// The ⌘Tab-style overlay shown while the modifier is held: a miniature of the
/// display arrangement with the target screen highlighted.
@MainActor
final class SwitcherHUD {
    private static let mapSize = CGSize(width: 280, height: 140)
    private static let padding: CGFloat = 18
    private static let labelHeight: CGFloat = 22

    private let panel: NSPanel
    private let map = DisplayMapView()
    private let label = NSTextField(labelWithString: "")
    private let background = NSVisualEffectView()

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 18
        background.layer?.masksToBounds = true
        panel.contentView = background
        background.addSubview(map)

        label.alignment = .center
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        background.addSubview(label)
    }

    var isVisible: Bool { panel.isVisible }

    /// Shows (or updates) the overlay centered on `target`.
    func show(displays: [Display], target: Display) {
        let ordered = ScreenNavigator.ordered(displays)
        if map.displays != ordered { layout(for: ordered) }
        map.displays = ordered
        map.targetID = target.id
        map.needsDisplay = true
        let number = (ordered.firstIndex(of: target) ?? 0) + 1
        label.stringValue = "\(number)  \(SystemDisplays.name(of: target.id))"

        let center = SystemDisplays.cocoaPoint(fromQuartz: target.center)
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Sizes the panel so the map keeps the arrangement's aspect ratio.
    private func layout(for displays: [Display]) {
        let union = displays.dropFirst().reduce(displays[0].frame) { $0.union($1.frame) }
        let scale = min(Self.mapSize.width / union.width, Self.mapSize.height / union.height)
        let mapSize = CGSize(width: max(union.width * scale, 160), height: union.height * scale)
        let size = CGSize(
            width: mapSize.width + 2 * Self.padding,
            height: mapSize.height + Self.labelHeight + 2.5 * Self.padding
        )
        background.frame = NSRect(origin: .zero, size: size)
        map.frame = NSRect(x: Self.padding, y: Self.padding * 1.5 + Self.labelHeight, width: mapSize.width, height: mapSize.height)
        label.frame = NSRect(x: Self.padding, y: Self.padding, width: mapSize.width, height: Self.labelHeight)
        panel.setContentSize(size)
    }
}

/// Draws display rectangles scaled to fit, numbered in reading order.
private final class DisplayMapView: NSView {
    var displays: [Display] = []
    var targetID: UInt32 = 0

    override func draw(_ dirtyRect: NSRect) {
        guard !displays.isEmpty else { return }
        let union = displays.map(\.frame).reduce(displays[0].frame) { $0.union($1) }
        let scale = min(bounds.width / union.width, bounds.height / union.height)
        // Center the arrangement in the view.
        let offset = CGPoint(
            x: (bounds.width - union.width * scale) / 2,
            y: (bounds.height - union.height * scale) / 2
        )

        for (index, display) in displays.enumerated() {
            let f = display.frame
            // Quartz is y-down, the view is y-up.
            let rect = CGRect(
                x: offset.x + (f.minX - union.minX) * scale,
                y: offset.y + (union.maxY - f.maxY) * scale,
                width: f.width * scale,
                height: f.height * scale
            ).insetBy(dx: 3, dy: 3)

            let isTarget = display.id == targetID
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            (isTarget ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.14)).setFill()
            path.fill()
            if !isTarget {
                NSColor.white.withAlphaComponent(0.25).setStroke()
                path.lineWidth = 1
                path.stroke()
            }

            let fontSize = max(10, min(rect.height * 0.42, 34))
            let text = NSAttributedString(string: "\(index + 1)", attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: NSColor.white.withAlphaComponent(isTarget ? 1 : 0.6),
            ])
            let textSize = text.size()
            text.draw(at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
        }
    }
}
