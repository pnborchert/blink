import CoreGraphics

public enum Direction: String, CaseIterable, Sendable {
    case left, right, up, down
}

/// A display in global Quartz coordinates (origin at the top-left of the main
/// display, y grows downwards) — the same space used by `CGWarpMouseCursorPosition`,
/// `CGDisplayBounds` and `CGWindowListCopyWindowInfo`.
public struct Display: Equatable, Sendable {
    public let id: UInt32
    public let frame: CGRect

    public init(id: UInt32, frame: CGRect) {
        self.id = id
        self.frame = frame
    }

    public var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    /// `CGRect.contains` treats maxX/maxY as outside, which matches how the
    /// cursor behaves on display edges.
    public func contains(_ point: CGPoint) -> Bool { frame.contains(point) }
}

public enum ScreenNavigator {
    /// Displays in "reading order": left to right, ties broken top to bottom.
    /// Used for next/previous cycling and for numbering displays 1…n.
    public static func ordered(_ displays: [Display]) -> [Display] {
        displays.sorted {
            if $0.frame.minX != $1.frame.minX { return $0.frame.minX < $1.frame.minX }
            if $0.frame.minY != $1.frame.minY { return $0.frame.minY < $1.frame.minY }
            return $0.id < $1.id
        }
    }

    /// The display containing `point`, or the closest one if the point is in a
    /// gap between displays (possible with oddly arranged screens).
    public static func display(containing point: CGPoint, in displays: [Display]) -> Display? {
        if let hit = displays.first(where: { $0.contains(point) }) { return hit }
        return displays.min { distance(from: point, to: $0.frame) < distance(from: point, to: $1.frame) }
    }

    /// The best display in `direction` from `current`.
    ///
    /// A display qualifies when its center lies further along `direction` and it
    /// is genuinely in that direction: either the two displays overlap on the
    /// perpendicular axis (e.g. share part of an edge), or its center is within a
    /// 45° cone. So a monitor to the right that happens to sit a little higher is
    /// reached with →, never with ↑.
    ///
    /// Candidates are ranked by how far their center is along the direction plus a
    /// penalty for being offset sideways (zero when the displays overlap).
    ///
    /// With `wrap`, if nothing lies in `direction`, the display furthest in the
    /// opposite direction is returned instead (like a carousel).
    public static func neighbor(
        of current: Display,
        direction: Direction,
        in displays: [Display],
        wrap: Bool
    ) -> Display? {
        let others = displays.filter { $0.id != current.id }

        func best(_ dir: Direction, preferFurthest: Bool) -> Display? {
            let scored: [(Display, CGFloat)] = others.compactMap { other in
                let along = alongDistance(from: current, to: other, dir)
                guard along > 0 else { return nil }
                let sideways = perpendicularGap(current.frame, other.frame, dir)
                let sidewaysCenter = abs(perpendicularCenterOffset(current, other, dir))
                let overlaps = perpendicularOverlap(current.frame, other.frame, dir) > 0
                guard overlaps || sidewaysCenter <= along else { return nil }
                // Small tie-breaker on the center offset keeps the ordering stable.
                let score = (preferFurthest ? -along : along) + 2 * sideways + 0.01 * sidewaysCenter
                return (other, score)
            }
            return scored.min { $0.1 < $1.1 }?.0
        }

        if let hit = best(direction, preferFurthest: false) { return hit }
        guard wrap else { return nil }
        return best(direction.opposite, preferFurthest: true)
    }

    /// The display `offset` steps away from `current` in reading order, wrapping.
    public static func cycle(from current: Display, offset: Int, in displays: [Display]) -> Display? {
        let list = ordered(displays)
        guard list.count > 1, let index = list.firstIndex(where: { $0.id == current.id }) else { return nil }
        let n = list.count
        return list[((index + offset) % n + n) % n]
    }

    /// The display with the given 1-based number in reading order.
    public static func display(number: Int, in displays: [Display]) -> Display? {
        let list = ordered(displays)
        guard number >= 1, number <= list.count else { return nil }
        return list[number - 1]
    }

    /// Where the cursor should land on `display`: the preferred point if it is
    /// still on that display (displays can be rearranged or resized), else the center.
    public static func landingPoint(on display: Display, preferred: CGPoint?) -> CGPoint {
        if let preferred, display.contains(preferred) { return preferred }
        return display.center
    }

    /// Keeps `point` strictly inside `rect`.
    public static func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX - 1),
            y: min(max(point.y, rect.minY), rect.maxY - 1)
        )
    }

    // MARK: - Geometry helpers

    private static func alongDistance(from a: Display, to b: Display, _ dir: Direction) -> CGFloat {
        switch dir {
        case .right: return b.center.x - a.center.x
        case .left: return a.center.x - b.center.x
        case .down: return b.center.y - a.center.y
        case .up: return a.center.y - b.center.y
        }
    }

    private static func perpendicularCenterOffset(_ a: Display, _ b: Display, _ dir: Direction) -> CGFloat {
        switch dir {
        case .left, .right: return b.center.y - a.center.y
        case .up, .down: return b.center.x - a.center.x
        }
    }

    /// Signed overlap of the two rects on the axis perpendicular to `dir`:
    /// positive = shared length, zero = touching corners, negative = gap.
    private static func perpendicularOverlap(_ a: CGRect, _ b: CGRect, _ dir: Direction) -> CGFloat {
        switch dir {
        case .left, .right: return min(a.maxY, b.maxY) - max(a.minY, b.minY)
        case .up, .down: return min(a.maxX, b.maxX) - max(a.minX, b.minX)
        }
    }

    /// Gap between the two rects on the axis perpendicular to `dir` (0 if they overlap).
    private static func perpendicularGap(_ a: CGRect, _ b: CGRect, _ dir: Direction) -> CGFloat {
        max(0, -perpendicularOverlap(a, b, dir))
    }

    private static func distance(from p: CGPoint, to r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}

extension Direction {
    public var opposite: Direction {
        switch self {
        case .left: return .right
        case .right: return .left
        case .up: return .down
        case .down: return .up
        }
    }
}
