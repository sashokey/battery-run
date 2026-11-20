import AppKit
import Combine

@MainActor
final class BatteryWindowController: NSWindowController, NSToolbarDelegate {
    let dashboard: AppKitDashboard
    let monitor: BatteryMonitor
    private var observation: AnyCancellable?
    private let refreshIdentifier = NSToolbarItem.Identifier("RefreshBattery")
    private var compact = false
    private var expandedWidth: CGFloat = 520
    private var powerRefresh: PowerRefresh?

    private enum PowerRefresh {
        case waiting(previous: BatterySample?, until: ContinuousClock.Instant)
        case finished(message: String, until: ContinuousClock.Instant)
    }

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
        render(opening: true)
    }

    required init?(coder: NSCoder) { nil }

    private func fitWindow(_ window: NSWindow, opening: Bool) {
        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
        let maximum = visibleFrame.map { window.contentRect(forFrameRect: $0).size } ?? NSSize(width: CGFloat.infinity, height: CGFloat.infinity)
        let minimum = compact ? NSSize(width: 420, height: 220) : NSSize(width: 460, height: 590)
        let previousFrame = window.frame
        window.contentMinSize = NSSize(width: min(minimum.width, maximum.width), height: min(minimum.height, maximum.height))
        let compactWidth = max(minimum.width, expandedWidth - 60)
        let width = min(compact ? compactWidth : expandedWidth, maximum.width)
        window.setContentSize(NSSize(width: width, height: window.contentMinSize.height))
        let height = max(ceil(dashboard.requiredContentHeight), window.contentMinSize.height)
        let limitedHeight = min(height, maximum.height)
        if compact { window.contentMinSize.height = limitedHeight }
        window.setContentSize(NSSize(width: width, height: limitedHeight))
        if let visibleFrame {
            let size = window.frame.size
            let x = opening ? visibleFrame.midX - size.width / 2 : previousFrame.minX
            let y = opening ? visibleFrame.midY - size.height / 2 : previousFrame.maxY - size.height
            window.setFrameOrigin(NSPoint(
                x: max(visibleFrame.minX, min(x, visibleFrame.maxX - size.width)),
                y: max(visibleFrame.minY, min(y, visibleFrame.maxY - size.height))
            ))
        } else if opening {
            window.center()
        } else {
            window.setFrameTopLeftPoint(NSPoint(x: previousFrame.minX, y: previousFrame.maxY))
        }
    }

    @objc func refreshBatteryData(_ sender: Any?) {
        let previous = monitor.sample
        monitor.refresh()
        if monitor.sample?.mode == .idle {
            powerRefresh = .waiting(
                previous: previous?.mode == .idle ? previous : nil,
                until: ContinuousClock.now + .seconds(25)
            )
        }
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

    private func render(opening: Bool = false) {
        let model = DashboardModel(
            sample: monitor.sample, session: monitor.tracker.session,
            forecastStart: monitor.tracker.forecastStart, chargingSession: monitor.chargingSession
        )
        dashboard.update(
            model: model, notice: monitor.notice, isReadingHistory: monitor.isReadingHistory,
            powerRefreshMessage: powerRefreshMessage(for: model.sample)
        )
        guard let window, opening || model.isCompact != compact else { return }
        if !compact && model.isCompact { expandedWidth = dashboard.bounds.width }
        compact = model.isCompact
        fitWindow(window, opening: opening)
    }

    private func powerRefreshMessage(for sample: BatterySample?) -> String? {
        guard let sample, sample.mode == .idle else {
            powerRefresh = nil
            return nil
        }
        let now = ContinuousClock.now
        switch powerRefresh {
        case let .waiting(previous, until):
            let message: String
            if sample.batteryWatts == nil && sample.inputWatts == nil {
                message = "Power readings unavailable."
            } else if previous?.powerSampleCount != sample.powerSampleCount ||
                        previous?.batteryWatts != sample.batteryWatts || previous?.inputWatts != sample.inputWatts {
                message = "Power readings updated."
            } else if now < until {
                return "Waiting for a new power reading…"
            } else {
                message = "Power readings unchanged."
            }
            powerRefresh = .finished(message: message, until: now + .seconds(5))
            return message
        case let .finished(message, until) where now < until:
            return message
        default:
            powerRefresh = nil
            return nil
        }
    }
}
