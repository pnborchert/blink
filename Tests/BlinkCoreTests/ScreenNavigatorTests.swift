import CoreGraphics
import Testing
@testable import BlinkCore

private func display(_ id: UInt32, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Display {
    Display(id: id, frame: CGRect(x: x, y: y, width: w, height: h))
}

@Suite struct ScreenNavigatorTests {
    // [ 1 ][ 2 ]  — laptop on the left, external monitor on the right (taller).
    let laptop = display(1, 0, 0, 1512, 982)
    let monitor = display(2, 1512, -300, 2560, 1440)

    @Test func sideBySide() {
        let all = [laptop, monitor]
        #expect(ScreenNavigator.neighbor(of: laptop, direction: .right, in: all, wrap: false) == monitor)
        #expect(ScreenNavigator.neighbor(of: monitor, direction: .left, in: all, wrap: false) == laptop)
        #expect(ScreenNavigator.neighbor(of: laptop, direction: .left, in: all, wrap: false) == nil)
        #expect(ScreenNavigator.neighbor(of: laptop, direction: .up, in: all, wrap: false) == nil)
    }

    @Test func wrapAroundJumpsToFarEnd() {
        let left = display(1, -1920, 0, 1920, 1080)
        let middle = display(2, 0, 0, 1920, 1080)
        let right = display(3, 1920, 0, 1920, 1080)
        let all = [middle, right, left]
        #expect(ScreenNavigator.neighbor(of: right, direction: .right, in: all, wrap: true) == left)
        #expect(ScreenNavigator.neighbor(of: left, direction: .left, in: all, wrap: true) == right)
        #expect(ScreenNavigator.neighbor(of: middle, direction: .right, in: all, wrap: true) == right)
        // Nothing above or below: wrapping must not invent a vertical neighbor.
        #expect(ScreenNavigator.neighbor(of: middle, direction: .up, in: all, wrap: true) == nil)
    }

    @Test func stackedVertically() {
        // Monitor above the laptop (y grows downwards in Quartz coordinates).
        let top = display(2, -200, -1440, 2560, 1440)
        let bottom = display(1, 0, 0, 1512, 982)
        let all = [bottom, top]
        #expect(ScreenNavigator.neighbor(of: bottom, direction: .up, in: all, wrap: false) == top)
        #expect(ScreenNavigator.neighbor(of: top, direction: .down, in: all, wrap: false) == bottom)
        #expect(ScreenNavigator.neighbor(of: bottom, direction: .right, in: all, wrap: false) == nil)
    }

    @Test func prefersAlignedScreenOverDiagonalOne() {
        // [ 2 ][ 3 ]
        // [ 1 ]        Going right from 1 should pick 3 only if nothing is level with 1.
        let one = display(1, 0, 1080, 1920, 1080)
        let two = display(2, 0, 0, 1920, 1080)
        let three = display(3, 1920, 0, 1920, 1080)
        let four = display(4, 1920, 1080, 1920, 1080)
        #expect(ScreenNavigator.neighbor(of: one, direction: .right, in: [one, two, three, four], wrap: false) == four)
        #expect(ScreenNavigator.neighbor(of: one, direction: .right, in: [one, two, three], wrap: false) == three)
        #expect(ScreenNavigator.neighbor(of: one, direction: .up, in: [one, two, three], wrap: false) == two)
    }

    @Test func laptopBelowAndOffsetFromMonitor() {
        // [   monitor   ]
        //          [ laptop ]   — they share only part of an edge.
        let monitor = display(1, 0, -1440, 2560, 1440)
        let laptop = display(2, 2000, 0, 1512, 982)
        let all = [monitor, laptop]
        #expect(ScreenNavigator.neighbor(of: laptop, direction: .up, in: all, wrap: false) == monitor)
        #expect(ScreenNavigator.neighbor(of: monitor, direction: .down, in: all, wrap: false) == laptop)
        // Also reachable sideways: the monitor is mostly to the left of the laptop.
        #expect(ScreenNavigator.neighbor(of: laptop, direction: .left, in: all, wrap: false) == monitor)
        #expect(ScreenNavigator.neighbor(of: laptop, direction: .right, in: all, wrap: true) == monitor)
    }

    @Test func cycleAndNumbering() {
        let a = display(10, -1920, 0, 1920, 1080)
        let b = display(20, 0, 0, 1512, 982)
        let c = display(30, 1512, 0, 2560, 1440)
        let all = [c, a, b]
        #expect(ScreenNavigator.ordered(all) == [a, b, c])
        #expect(ScreenNavigator.cycle(from: b, offset: 1, in: all) == c)
        #expect(ScreenNavigator.cycle(from: c, offset: 1, in: all) == a)
        #expect(ScreenNavigator.cycle(from: a, offset: -1, in: all) == c)
        #expect(ScreenNavigator.cycle(from: a, offset: 1, in: [a]) == nil)
        #expect(ScreenNavigator.display(number: 1, in: all) == a)
        #expect(ScreenNavigator.display(number: 3, in: all) == c)
        #expect(ScreenNavigator.display(number: 4, in: all) == nil)
        #expect(ScreenNavigator.display(number: 0, in: all) == nil)
    }

    @Test func displayContainingPoint() {
        let all = [laptop, monitor]
        #expect(ScreenNavigator.display(containing: CGPoint(x: 10, y: 10), in: all) == laptop)
        #expect(ScreenNavigator.display(containing: CGPoint(x: 1512, y: 10), in: all) == monitor)
        // In the dead zone below the laptop but left of the monitor → nearest display.
        #expect(ScreenNavigator.display(containing: CGPoint(x: 1500, y: 1100), in: all) == monitor)
        #expect(ScreenNavigator.display(containing: .zero, in: []) == nil)
    }

    @Test func landingPoint() {
        let remembered = CGPoint(x: 100, y: 200)
        #expect(ScreenNavigator.landingPoint(on: laptop, preferred: remembered) == remembered)
        #expect(ScreenNavigator.landingPoint(on: laptop, preferred: nil) == CGPoint(x: 756, y: 491))
        // A remembered point that is no longer on the display (e.g. resolution changed).
        #expect(ScreenNavigator.landingPoint(on: laptop, preferred: CGPoint(x: 5000, y: 0)) == laptop.center)
    }

    @Test func clamp() {
        let r = CGRect(x: 0, y: 0, width: 100, height: 50)
        #expect(ScreenNavigator.clamp(CGPoint(x: -5, y: 70), to: r) == CGPoint(x: 0, y: 49))
        #expect(ScreenNavigator.clamp(CGPoint(x: 40, y: 20), to: r) == CGPoint(x: 40, y: 20))
    }
}
