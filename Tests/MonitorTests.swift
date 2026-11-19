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
    TestCase(name: "native monitor persists a wake with unchanged battery charge") {
        try MainActor.assumeIsolated {
            let url = URL(fileURLWithPath: ".build/monitor-wake-\(UUID().uuidString).json")
            let current = historyCurrent(75)
            let previousWake = BatterySample(date: current.date.addingTimeInterval(-600), percent: 75, onBattery: true)
            var tracker = SessionTracker()
            tracker.update(previousWake, wakeDate: previousWake.date)
            tracker.update(current)
            try SessionStore.save(tracker, to: url)
            var reading = current
            let monitor = BatteryMonitor(stateURL: url, readSample: { reading }, bootDate: nil)
            monitor.refresh()
            try expect(monitor.tracker.forecastStart == previousWake, "monitor must load the previously saved wake")

            let nextWake = BatterySample(date: current.date.addingTimeInterval(1), percent: 75, onBattery: true)
            reading = nextWake
            monitor.refresh(wakeDate: nextWake.date)
            try expect(monitor.tracker.forecastStart == nextWake, "the wake must start a new forecast")
            try expect(SessionStore.load(from: url)?.forecastStart == nextWake, "an unchanged charge must not suppress persistence")
        }
    },
    TestCase(name: "native monitor invalidates a stored forecast from before system boot") {
        try MainActor.assumeIsolated {
            let url = URL(fileURLWithPath: ".build/monitor-boot-\(UUID().uuidString).json")
            let current = historyCurrent(70)
            let previousWake = BatterySample(date: current.date.addingTimeInterval(-600), percent: 75, onBattery: true)
            let bootDate = current.date.addingTimeInterval(-300)
            var tracker = SessionTracker()
            tracker.update(previousWake, wakeDate: previousWake.date)
            try SessionStore.save(tracker, to: url)
            let monitor = BatteryMonitor(stateURL: url, readSample: { current }, bootDate: bootDate)
            monitor.refresh()
            try expect(monitor.tracker.forecastStart == nil, "preboot measurements cannot be used while history is unavailable")
        }
    },
    TestCase(name: "native monitor does not use a delayed reading as the wake start") {
        try MainActor.assumeIsolated {
            let url = URL(fileURLWithPath: ".build/monitor-missed-wake-\(UUID().uuidString).json")
            let current = historyCurrent(75)
            var reading: BatterySample? = current
            let monitor = BatteryMonitor(stateURL: url, readSample: { reading }, bootDate: nil)
            monitor.refresh()

            reading = nil
            monitor.refresh(wakeDate: current.date.addingTimeInterval(1))
            try expect(monitor.sample == nil, "the reading at wake must be unavailable")
            reading = BatterySample(date: current.date.addingTimeInterval(600), percent: 70, onBattery: true)
            monitor.refresh()
            try expect(monitor.tracker.forecastStart == nil, "a later timer reading cannot stand in for the missing wake sample")
        }
    },
    TestCase(name: "native monitor does not date an unplug across missing battery readings") {
        try MainActor.assumeIsolated {
            let url = URL(fileURLWithPath: ".build/monitor-missed-unplug-\(UUID().uuidString).json")
            let current = historyCurrent(75, onBattery: false)
            var reading: BatterySample? = current
            let monitor = BatteryMonitor(stateURL: url, readSample: { reading }, bootDate: nil)
            monitor.refresh()
            reading = nil
            monitor.refresh()
            reading = BatterySample(date: current.date.addingTimeInterval(600), percent: 70, onBattery: true)
            monitor.refresh()
            try expect(monitor.tracker.forecastStart == nil, "a delayed battery reading cannot timestamp a missed power transition")
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
