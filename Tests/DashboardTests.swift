import Foundation

let dashboardTests = [
    TestCase(name: "dashboard presents session-derived remaining and full durations") {
        let start = BatterySample(date: Date(timeIntervalSince1970: 1704110400), percent: 80, onBattery: true)
        let model = DashboardModel(sample: historyCurrent(), session: DischargeSession(start: start, origin: .observed))
        try expect(model.remaining == "3h 0m", "remaining estimate must be visible")
        try expect(model.fullDuration == "5h 0m", "full discharge estimate must be visible")
        try expect(model.startLabel == "Discharge started", "observed unplug may identify the start")
    },
    TestCase(name: "historical and launch-only starts cannot present themselves as exact unplug times") {
        let start = BatterySample(date: Date(timeIntervalSince1970: 1704110400), percent: 80, onBattery: true)
        let historical = DashboardModel(sample: historyCurrent(), session: DischargeSession(start: start, origin: .history))
        let monitored = DashboardModel(sample: historyCurrent(), session: DischargeSession(start: start, origin: .monitoring))
        try expect(historical.startValue.hasPrefix("≈"), "history must visibly signal uncertainty")
        try expect(monitored.startLabel == "Monitoring since", "launch-only observation cannot claim an unplug time")
    },
    TestCase(name: "dashboard suppresses stale estimates while plugged in") {
        let start = BatterySample(date: Date(timeIntervalSince1970: 1704110400), percent: 80, onBattery: true)
        let model = DashboardModel(sample: historyCurrent(60, onBattery: false), session: DischargeSession(start: start, origin: .history))
        try expect(model.remaining == "—", "AC cannot display a running discharge forecast")
        try expect(model.startValue == "—", "AC cannot display an active discharge session")
        try expect(!model.explanation.isEmpty, "AC state must explain why no estimate is shown")
    }
]
