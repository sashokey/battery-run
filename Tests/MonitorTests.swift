import Foundation

let monitorTests = [
    TestCase(name: "native monitor refresh publishes the battery reading and persists its session") {
        try MainActor.assumeIsolated {
            let url = URL(fileURLWithPath: ".build/monitor-\(UUID().uuidString).json")
            let reading = historyCurrent(71)
            let monitor = BatteryMonitor(stateURL: url, readSample: { reading })
            monitor.refresh()
            try expect(monitor.sample == reading, "refresh must publish the battery reading")
            try expect(SessionStore.load(from: url)?.lastSample?.percent == monitor.sample?.percent, "refresh must persist the latest measured charge")
        }
    },
    TestCase(name: "native monitor loads a valid persisted baseline") {
        try MainActor.assumeIsolated {
            let url = URL(fileURLWithPath: ".build/monitor-load-\(UUID().uuidString).json")
            var tracker = SessionTracker()
            tracker.update(BatterySample(date: Date(timeIntervalSince1970: 1000), percent: 80, onBattery: true))
            try SessionStore.save(tracker, to: url)
            let monitor = BatteryMonitor(stateURL: url)
            try expect(monitor.tracker.session?.start.percent == 80, "launch must recover valid saved state")
        }
    },
    TestCase(name: "duration display converts seconds into readable time without misleading precision") {
        try expect(DurationText.string(10800) == "3h 0m", "three hours must display as hours and minutes")
        try expect(DurationText.string(3660) == "1h 1m", "hour and minute should both be visible")
        try expect(DurationText.string(0) == "0m", "zero must not look unavailable")
        try expect(DurationText.string(30) == "<1m", "seconds must not look like precise long-term predictions")
        try expect(DurationText.string(nil) == "—", "missing prediction must be clearly unavailable")
        try expect(DurationText.string(.infinity) == "—", "invalid prediction must not overflow formatting")
    }
]
