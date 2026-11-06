import CoreGraphics

/// Most-recently-used order of displays, so the switch key behaves like ⌘Tab:
/// one tap goes back to the screen you came from, more taps go further back.
public struct ScreenHistory: Equatable, Sendable {
    /// Display IDs, most recent first.
    public private(set) var recent: [UInt32] = []

    public init() {}

    public mutating func visit(_ id: UInt32) {
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
    }

    /// `current` first, then the others from most to least recent. Displays never
    /// visited follow in reading order; IDs of disconnected displays are skipped.
    public func order(of displays: [Display], current: Display) -> [Display] {
        let byID = Dictionary(displays.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var result = [current]
        for id in recent where id != current.id {
            if let d = byID[id] { result.append(d) }
        }
        for d in ScreenNavigator.ordered(displays) where !result.contains(d) {
            result.append(d)
        }
        return result
    }
}

/// One press-and-hold of the modifier: from the first trigger until release.
public struct SwitchSession: Sendable {
    /// Where the cursor was when the session started (restored on cancel).
    public let origin: CGPoint
    public let originDisplay: Display
    /// Switch order, `originDisplay` first.
    public let order: [Display]
    public private(set) var target: Display

    public init(origin: CGPoint, order: [Display]) {
        precondition(!order.isEmpty)
        self.origin = origin
        self.originDisplay = order[0]
        self.order = order
        self.target = order[0]
    }

    /// Moves `steps` along the MRU order (negative = backwards), wrapping.
    @discardableResult
    public mutating func step(_ steps: Int) -> Display {
        let n = order.count
        let index = order.firstIndex(of: target) ?? 0
        target = order[((index + steps) % n + n) % n]
        return target
    }

    /// Jumps directly to `display` (arrow keys, screen numbers).
    public mutating func select(_ display: Display) {
        target = display
    }
}
