import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var statusMenu: StatusMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = AppController()
        statusMenu = StatusMenu(controller: controller)
        controller.start()
        self.controller = controller
    }
}
