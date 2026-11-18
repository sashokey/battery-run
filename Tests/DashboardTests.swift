import Foundation

let dashboardTests = [
    TestCase(name: "dashboard presents session-derived remaining and full durations") {
        let start = BatterySample(date: Date(timeIntervalSince1970: 1704110400), percent: 80, onBattery: true)
        let model = DashboardModel(sample: historyCurrent(), session: DischargeSession(start: start, origin: .observed), forecastStart: start)
        try expect(model.remaining == "3h 0m", "remaining estimate must be visible")
        try expect(model.fullDuration == "5h 0m", "full discharge estimate must be visible")
        try expect(model.startLabel == "Discharge started", "observed unplug may identify the start")
    },
    TestCase(name: "forecasts use the charge measured after the latest wake") {
        let current = historyCurrent(70)
        let unplug = BatterySample(date: current.date.addingTimeInterval(-36000), percent: 90, onBattery: true)
        let wake = BatterySample(date: current.date.addingTimeInterval(-1800), percent: 75, onBattery: true)
        var tracker = SessionTracker()
        tracker.update(unplug)
        tracker.markWake()
        tracker.update(wake)
        let collecting = DashboardModel(sample: wake, session: tracker.session, forecastStart: tracker.forecastStart)
        try expect(collecting.remaining == "—" && collecting.fullDuration == "—", "each wake must wait for a new discharge measurement")
        tracker.update(current)
        tracker.reconcile(history: "2024-01-01 12:00:00 +0000 Wake Wake from sleep Using Batt(Charge: 80%)", current: current)
        let model = DashboardModel(sample: current, session: tracker.session, forecastStart: tracker.forecastStart)
        try expect(model.remaining == "7h 0m", "remaining should use the five points consumed over the half hour after wake")
        try expect(model.fullDuration == "10h 0m", "full runtime should use the same post-wake rate")
        try expect(model.rate == "10%/h", "average drain should use the forecast window")
        try expect(model.startCharge == "90%" && model.chargeUsed == "20%", "session totals should still start at unplug")
    },
    TestCase(name: "startup recovers the latest full wake without using a maintenance wake") {
        let current = historyCurrent(70)
        var tracker = SessionTracker()
        tracker.reconcile(history: """
        2024-01-01 11:00:00 +0000 Sleep Using Batt(Charge: 95%)
        2024-01-01 12:10:00 +0000 Wake                 Wake from sleep Using Batt(Charge: 83%)
        2024-01-01 12:30:00 +0000 Wake                 DarkWake to FullWake from sleep Using Batt(Charge: 75%)
        2024-01-01 12:40:00 +0000 DarkWake DarkWake from sleep Using Batt(Charge: 74%)
        """, current: current)
        let model = DashboardModel(sample: current, session: tracker.session, forecastStart: tracker.forecastStart)
        try expect(model.remaining == "7h 0m" && model.fullDuration == "10h 0m", "the full wake should set the charge and elapsed time for both forecasts")
        try expect(model.startCharge == "95%", "history should still recover the original discharge")
    },
    TestCase(name: "startup uses an unplug logged in the same second after the wake") {
        let current = historyCurrent(70)
        var tracker = SessionTracker()
        tracker.reconcile(history: """
        2024-01-01 12:30:00 +0000 Wake                 Wake from sleep Using Batt(Charge: 80%)
        2024-01-01 12:30:00 +0000 Assertions Using AC(Charge: 74%)
        2024-01-01 12:30:00 +0000 Assertions Using Batt(Charge: 75%)
        """, current: current)
        let model = DashboardModel(sample: current, session: tracker.session, forecastStart: tracker.forecastStart)
        try expect(model.remaining == "7h 0m" && model.fullDuration == "10h 0m", "the newer unplug should set the forecast baseline")
    },
    TestCase(name: "history recovers an unplug missed after an observed wake") {
        let current = historyCurrent(70)
        let wake = BatterySample(date: current.date.addingTimeInterval(-3600), percent: 90, onBattery: true)
        var tracker = SessionTracker()
        tracker.markWake()
        tracker.update(wake)
        tracker.reconcile(history: """
        2024-01-01 12:15:00 +0000 Assertions Using AC(Charge: 74%)
        2024-01-01 12:30:00 +0000 Assertions Using Batt(Charge: 75%)
        """, current: current)
        let model = DashboardModel(sample: current, session: tracker.session, forecastStart: tracker.forecastStart)
        try expect(model.remaining == "7h 0m" && model.fullDuration == "10h 0m", "a recovered unplug must take precedence over an older live wake")
    },
    TestCase(name: "startup without a known wake waits for a new discharge measurement") {
        let current = historyCurrent(70)
        let saved = DischargeSession(
            start: BatterySample(date: current.date.addingTimeInterval(-36000), percent: 90, onBattery: true),
            origin: .observed
        )
        var tracker = SessionTracker(session: saved, lastSample: saved.start)
        tracker.reconcile(history: "2024-01-01 12:00:00 +0000 Sleep Using Batt(Charge: 80%)", current: current)
        let model = DashboardModel(sample: current, session: tracker.session, forecastStart: tracker.forecastStart)
        try expect(model.remaining == "—" && model.fullDuration == "—", "a saved session may include an unobserved sleep")
    },
    TestCase(name: "startup does not recover a forecast across a charge increase after wake") {
        let current = historyCurrent(70)
        let saved = DischargeSession(
            start: BatterySample(date: current.date.addingTimeInterval(-10800), percent: 95, onBattery: true),
            origin: .observed
        )
        var tracker = SessionTracker(session: saved, lastSample: saved.start)
        tracker.reconcile(history: """
        2024-01-01 11:00:00 +0000 Wake                 Wake from sleep Using Batt(Charge: 80%)
        2024-01-01 12:00:00 +0000 Assertions Using Batt(Charge: 60%)
        """, current: current)
        let model = DashboardModel(sample: current, session: tracker.session, forecastStart: tracker.forecastStart)
        try expect(model.remaining == "—" && model.fullDuration == "—", "a history ending at a lower charge cannot establish the current discharge")
    },
    TestCase(name: "startup does not use a wake preceding the last sleep") {
        let current = historyCurrent(70)
        var tracker = SessionTracker()
        tracker.reconcile(history: """
        2024-01-01 11:00:00 +0000 Wake Wake from sleep Using Batt(Charge: 90%)
        2024-01-01 12:00:00 +0000 Sleep                Entering Sleep state Using Batt(Charge: 80%)
        2024-01-01 12:00:01 +0000 Wake Requests [process=powerd request=Maintenance]
        2024-01-01 12:30:00 +0000 DarkWake DarkWake from sleep Using Batt(Charge: 75%)
        """, current: current)
        let model = DashboardModel(sample: current, session: tracker.session, forecastStart: tracker.forecastStart)
        try expect(model.remaining == "—" && model.fullDuration == "—", "a sleep without a recorded full wake cannot provide a forecast baseline")
    },
    TestCase(name: "startup does not recover a wake from before power history restarted") {
        let current = historyCurrent(70)
        var tracker = SessionTracker()
        tracker.reconcile(history: """
        2024-01-01 11:00:00 +0000 Wake                 Wake from sleep Using Batt(Charge: 90%)
        2024-01-01 12:00:00 +0000 Start                powerd process is started
        2024-01-01 12:30:00 +0000 Assertions Using Batt(Charge: 75%)
        """, current: current)
        let model = DashboardModel(sample: current, session: tracker.session, forecastStart: tracker.forecastStart)
        try expect(model.remaining == "—" && model.fullDuration == "—", "a power history restart makes the previous wake unsafe to use")
    },
    TestCase(name: "historical and launch-only starts cannot present themselves as exact unplug times") {
        let start = BatterySample(date: Date(timeIntervalSince1970: 1704110400), percent: 80, onBattery: true)
        let historical = DashboardModel(sample: historyCurrent(), session: DischargeSession(start: start, origin: .history), forecastStart: start)
        let monitored = DashboardModel(sample: historyCurrent(), session: DischargeSession(start: start, origin: .monitoring), forecastStart: start)
        try expect(historical.startValue.hasPrefix("≈"), "history must visibly signal uncertainty")
        try expect(monitored.startLabel == "Monitoring since", "launch-only observation cannot claim an unplug time")
    },
    TestCase(name: "dashboard suppresses stale estimates while plugged in") {
        let start = BatterySample(date: Date(timeIntervalSince1970: 1704110400), percent: 80, onBattery: true)
        let model = DashboardModel(sample: historyCurrent(60, onBattery: false), session: DischargeSession(start: start, origin: .history), forecastStart: start)
        try expect(model.remaining == "—", "AC cannot display a running discharge forecast")
        try expect(model.startValue == "—", "AC cannot display an active discharge session")
        try expect(!model.explanation.isEmpty, "AC state must explain why no estimate is shown")
    }
]
