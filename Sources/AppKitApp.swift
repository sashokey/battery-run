import AppKit

@main
enum AppKitApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppKitApplicationDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppKitApplicationDelegate: NSObject, NSApplicationDelegate {
    private var controller: BatteryWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 else {
            let alert = NSAlert()
            alert.messageText = "Battery Run requires macOS 27"
            alert.informativeText = "This build supports macOS 27 only."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let monitor = BatteryMonitor()
        monitor.start()
        let controller = BatteryWindowController(monitor: monitor)
        self.controller = controller
        configureMenu(target: controller)
        controller.showWindow(nil)
        NSApp.activate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { controller?.showWindow(nil) }
        return true
    }

    private func configureMenu(target: BatteryWindowController) {
        let main = NSMenu()
        let appMenu = NSMenu(title: "Battery Run")
        appMenu.addItem(withTitle: "About Battery Run", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let services = NSMenu(title: "Services")
        appMenu.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = services
        NSApp.servicesMenu = services
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Battery Run", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Battery Run", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "Battery Run", action: nil, keyEquivalent: "").submenu = appMenu

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: "File", action: nil, keyEquivalent: "").submenu = fileMenu
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = editMenu
        let batteryMenu = NSMenu(title: "Battery")
        let refresh = batteryMenu.addItem(withTitle: "Refresh Battery Data", action: #selector(BatteryWindowController.refreshBatteryData(_:)), keyEquivalent: "r")
        refresh.target = target
        main.addItem(withTitle: "Battery", action: nil, keyEquivalent: "").submenu = batteryMenu
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = main
    }
}
