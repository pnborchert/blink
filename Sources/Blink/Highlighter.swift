import AppKit
import QuartzCore

/// Draws a short-lived ring around the cursor so the eye can find it after a blink.
@MainActor
final class Highlighter {
    private static let size: CGFloat = 56
    private static let duration: CFTimeInterval = 0.35

    private let panel: NSPanel
    private let ring = CAShapeLayer()
    private var generation = 0

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let view = NSView(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        view.wantsLayer = true
        panel.contentView = view

        let inset: CGFloat = 14 // ring diameter 28pt
        ring.frame = view.bounds
        ring.path = CGPath(ellipseIn: view.bounds.insetBy(dx: inset, dy: inset), transform: nil)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = NSColor.controlAccentColor.cgColor
        ring.lineWidth = 2
        ring.opacity = 0
        view.layer?.addSublayer(ring)
    }

    /// `point` is in Quartz coordinates (as used for the cursor).
    func flash(at point: CGPoint) {
        generation += 1
        let current = generation

        let center = SystemDisplays.cocoaPoint(fromQuartz: point)
        panel.setFrame(
            NSRect(x: center.x - Self.size / 2, y: center.y - Self.size / 2, width: Self.size, height: Self.size),
            display: false
        )
        panel.orderFrontRegardless()

        // Colors may have changed (accent color / appearance) since launch.
        ring.strokeColor = NSColor.controlAccentColor.cgColor

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.5
        scale.toValue = 0.8
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.85
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = Self.duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)

        ring.removeAllAnimations()
        ring.add(group, forKey: "flash")

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration) { [weak self] in
            guard let self, self.generation == current else { return }
            self.panel.orderOut(nil)
        }
    }
}
