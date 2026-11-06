import AppKit
import BlinkCore

/// Posted by `Blink --perform <action>` so the running instance does the work
/// (keeping its remembered cursor positions). `object` is the action name.
let performNotification = Notification.Name((Bundle.main.bundleIdentifier ?? "blink") + ".perform")

let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--perform") {
    let names = Action.all.map(\.configName).joined(separator: ", ")
    guard flag + 1 < arguments.count, let action = Action(configName: arguments[flag + 1]) else {
        FileHandle.standardError.write(Data("usage: Blink --perform <\(names)>\n".utf8))
        exit(2)
    }
    let ownPID = ProcessInfo.processInfo.processIdentifier
    let isRunning = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        .contains { $0.processIdentifier != ownPID }
    if isRunning {
        DistributedNotificationCenter.default().postNotificationName(
            performNotification, object: action.configName, userInfo: nil, deliverImmediately: true
        )
    } else {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            Blinker(config: ConfigStore().load().config).perform(action)
            // Give the highlight animation time to play before exiting.
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        }
    }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Menu bar only: no Dock icon, no app switcher entry (also set via LSUIElement).
    app.setActivationPolicy(.accessory)
    app.run()
}
