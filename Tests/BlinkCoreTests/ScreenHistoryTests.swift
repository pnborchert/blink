import CoreGraphics
import Testing
@testable import BlinkCore

@Suite struct ScreenHistoryTests {
    let a = Display(id: 1, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
    let b = Display(id: 2, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    let c = Display(id: 3, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))

    @Test func mostRecentFirstLikeCommandTab() {
        var history = ScreenHistory()
        history.visit(a.id)
        history.visit(c.id)
        history.visit(b.id)
        // On b: one tap goes back to c (where we came from), then a.
        #expect(history.order(of: [a, b, c], current: b) == [b, c, a])
    }

    @Test func currentScreenAlwaysFirstEvenIfNotRecorded() {
        var history = ScreenHistory()
        history.visit(b.id)
        // The cursor was moved to c by hand; c leads, b is the one to go back to.
        #expect(history.order(of: [a, b, c], current: c) == [c, b, a])
    }

    @Test func unvisitedInReadingOrderAndDisconnectedSkipped() {
        var history = ScreenHistory()
        history.visit(99) // a display that is gone
        #expect(history.order(of: [c, a, b], current: b) == [b, a, c])
    }

    @Test func sessionStepsWrapAndSelect() {
        var session = SwitchSession(origin: .zero, order: [b, c, a])
        #expect(session.target == b)
        #expect(session.step(1) == c)
        #expect(session.step(1) == a)
        #expect(session.step(1) == b)
        #expect(session.step(-1) == a)
        session.select(c)
        #expect(session.step(1) == a)
        #expect(session.originDisplay == b)
    }
}
