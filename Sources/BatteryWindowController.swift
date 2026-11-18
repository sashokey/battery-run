import AppKit
import Combine

@MainActor
final class BatteryWindowController: NSWindowController, NSToolbarDelegate {
    let dashboard: AppKitDashboard
    let monitor: BatteryMonitor
    private var observation: AnyCancellable?
    private let refreshIdentifier = NSToolbarItem.Identifier("RefreshBattery")

    init(monitor: BatteryMonitor) {
        self.monitor = monitor
        let minimumSize = NSSize(width: 460, height: 590)
        dashboard = AppKitDashboard(frame: NSRect(x: 0, y: 0, width: 520, height: minimumSize.height))
        let window = NSWindow(contentRect: dashboard.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Battery Run"
        window.contentView = dashboard
        window.contentMinSize = minimumSize
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unifiedCompact
        let toolbar = NSToolbar(identifier: "BatteryToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        observation = monitor.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.render() }
        }
        render()
        fitOpeningHeight(of: window)
    }

    required init?(coder: NSCoder) { nil }

    private func fitOpeningHeight(of window: NSWindow) {
        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
        let maximumHeight = visibleFrame.map { max(0, window.contentRect(forFrameRect: $0).height) } ?? .infinity
        window.contentMinSize.height = min(window.contentMinSize.height, maximumHeight)
        let requiredHeight = max(ceil(dashboard.requiredContentHeight), window.contentMinSize.height)
        window.setContentSize(NSSize(width: dashboard.bounds.width, height: min(requiredHeight, maximumHeight)))
        if let visibleFrame {
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2))
        } else {
            window.center()
        }
    }

    @objc func refreshBatteryData(_ sender: Any?) {
        monitor.refresh()
        render()
        monitor.recoverHistory()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, refreshIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, refreshIdentifier]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard identifier == refreshIdentifier else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "Refresh Battery Data"
        item.toolTip = "Refresh battery data"
        item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh Battery Data")
        item.target = self
        item.action = #selector(refreshBatteryData(_:))
        return item
    }

    private func render() {
        let model = DashboardModel(sample: monitor.sample, session: monitor.tracker.session, forecastStart: monitor.tracker.forecastStart)
        dashboard.update(model: model, notice: monitor.notice, isReadingHistory: monitor.isReadingHistory)
    }
}
