import AppKit
import Foundation

@MainActor
func visibleText(in view: NSView) -> [String] {
    guard !view.isHidden else { return [] }
    return (view as? NSTextField).map { [$0.stringValue] } ?? view.subviews.flatMap { visibleText(in: $0) }
}

let appKitTests = [
    TestCase(name: "AppKit presents all measured session values in native text controls") {
        try MainActor.assumeIsolated {
            let view = AppKitDashboard(frame: NSRect(x: 0, y: 0, width: 520, height: 650))
            let start = BatterySample(date: Date(timeIntervalSince1970: 1704110400), percent: 80, onBattery: true)
            view.update(model: DashboardModel(sample: historyCurrent(), session: DischargeSession(start: start, origin: .history), forecastStart: start), notice: nil, isReadingHistory: false)
            let values = visibleText(in: view)
            for expected in ["60%", "On Battery", "3h 0m", "5h 0m", "80%", "1h 0m", "20%", "20%/h"] {
                try expect(values.contains(expected), "native window must display \(expected)")
            }
            try expect(values.contains { $0.hasPrefix("≈") }, "historical uncertainty must remain visible")
        }
    },
    TestCase(name: "AppKit shows the forecast starting charge during a battery session") {
        try MainActor.assumeIsolated {
            func sessionValue(_ label: String, in view: NSView) -> String? {
                if let grid = view as? NSGridView {
                    let row = (0..<grid.numberOfRows).first {
                        (grid.cell(atColumnIndex: 0, rowIndex: $0).contentView as? NSTextField)?.stringValue == label
                    }
                    return row.flatMap { (grid.cell(atColumnIndex: 1, rowIndex: $0).contentView as? NSTextField)?.stringValue }
                }
                return view.subviews.lazy.compactMap { sessionValue(label, in: $0) }.first
            }

            let view = AppKitDashboard(frame: NSRect(x: 0, y: 0, width: 460, height: 590))
            let current = historyCurrent(70)
            let start = BatterySample(date: current.date.addingTimeInterval(-7200), percent: 90, onBattery: true)
            let wake = BatterySample(date: current.date.addingTimeInterval(-1800), percent: 75, onBattery: true)
            let session = DischargeSession(start: start, origin: .observed)
            view.update(model: DashboardModel(sample: current, session: session, forecastStart: wake), notice: nil, isReadingHistory: false)
            try expect(sessionValue("Charge at forecast start", in: view) == "75%", "the forecast row must show the charge at wake")
            try expect(sessionValue("Starting charge", in: view) == "90%", "the starting charge row must show the charge at unplugging")

            view.update(model: DashboardModel(sample: historyCurrent(70, onBattery: false), session: session, forecastStart: wake), notice: nil, isReadingHistory: false)
            try expect(sessionValue("Charge at forecast start", in: view) == "—", "the forecast baseline must clear on external power")

            view.update(model: DashboardModel(sample: current, session: session, forecastStart: nil), notice: nil, isReadingHistory: false)
            try expect(sessionValue("Charge at forecast start", in: view) == "—", "an unknown forecast baseline must display as unavailable")
        }
    },
    TestCase(name: "AppKit clears stale forecasts when power switches to AC") {
        try MainActor.assumeIsolated {
            let view = AppKitDashboard(frame: NSRect(x: 0, y: 0, width: 520, height: 650))
            let start = BatterySample(date: Date(timeIntervalSince1970: 1704110400), percent: 80, onBattery: true)
            let session = DischargeSession(start: start, origin: .history)
            view.update(model: DashboardModel(sample: historyCurrent(), session: session, forecastStart: start), notice: nil, isReadingHistory: false)
            view.update(model: DashboardModel(sample: historyCurrent(60, onBattery: false), session: session, forecastStart: start), notice: nil, isReadingHistory: false)
            let values = visibleText(in: view)
            try expect(values.contains("External Power"), "source change must be reflected in the native window")
            try expect(!values.contains("3h 0m"), "previous remaining time must be removed")
            try expect(!values.contains("80%"), "previous session values must be removed")
        }
    },
    TestCase(name: "AppKit unavailable state hides old charge and presents the data error") {
        try MainActor.assumeIsolated {
            let view = AppKitDashboard(frame: NSRect(x: 0, y: 0, width: 520, height: 650))
            view.update(model: DashboardModel(sample: historyCurrent(), session: nil, forecastStart: nil), notice: nil, isReadingHistory: false)
            view.update(model: DashboardModel(sample: nil, session: nil, forecastStart: nil), notice: nil, isReadingHistory: false)
            let values = visibleText(in: view)
            try expect(values.contains("Battery Unavailable"), "unavailable data must have a clear state")
            try expect(!values.contains("60%"), "stale charge must not remain visible")
        }
    },
    TestCase(name: "AppKit presents persistence errors and history progress") {
        try MainActor.assumeIsolated {
            let view = AppKitDashboard(frame: NSRect(x: 0, y: 0, width: 520, height: 650))
            view.update(model: DashboardModel(sample: historyCurrent(), session: nil, forecastStart: nil), notice: "Session storage failed", isReadingHistory: true)
            let values = visibleText(in: view)
            try expect(values.contains("Session storage failed"), "the native view must surface storage errors")
            try expect(values.contains("Reading power history…"), "history progress must be visible")
        }
    },
    TestCase(name: "AppKit window refresh binds live battery data to the dashboard") {
        try MainActor.assumeIsolated {
            let url = URL(fileURLWithPath: ".build/window-\(UUID().uuidString).json")
            let reading = historyCurrent(71, onBattery: false)
            let monitor = BatteryMonitor(stateURL: url, readSample: { reading })
            let controller = BatteryWindowController(monitor: monitor)
            controller.refreshBatteryData(nil)
            try expect(controller.window != nil, "the app must provide a native window")
            try expect(monitor.sample == reading, "refresh must read the battery source")
            try expect(visibleText(in: controller.dashboard).contains("71%"), "measured charge must reach the native dashboard")
        }
    },
    TestCase(name: "AppKit observes monitor updates without a manual window refresh") {
        try MainActor.assumeIsolated {
            let url = URL(fileURLWithPath: ".build/automatic-window-\(UUID().uuidString).json")
            let monitor = BatteryMonitor(stateURL: url, readSample: { historyCurrent(63) })
            let controller = BatteryWindowController(monitor: monitor)
            monitor.refresh()
            let expected = "63%"
            let deadline = Date().addingTimeInterval(1)
            while !visibleText(in: controller.dashboard).contains(expected), Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            try expect(visibleText(in: controller.dashboard).contains(expected), "published battery changes must update the native window automatically")
        }
    },
    TestCase(name: "AppKit opens at 520 by 650 points including the toolbar") {
        try MainActor.assumeIsolated {
            let monitor = BatteryMonitor(stateURL: URL(fileURLWithPath: ".build/window-size-\(UUID().uuidString).json"))
            let controller = BatteryWindowController(monitor: monitor)
            try expectNear(controller.window.map { Double($0.frame.width) }, 520, "opening width must match the intended size")
            try expectNear(controller.window.map { Double($0.frame.height) }, 650, "the toolbar must be included in the intended opening height")
        }
    }
]
