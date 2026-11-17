import Foundation

func historyCurrent(_ percent: Double = 60, onBattery: Bool = true) -> BatterySample {
    BatterySample(date: Date(timeIntervalSince1970: 1704114000), percent: percent, onBattery: onBattery)
}

let historyTests = [
    TestCase(name: "history uses the battery segment after the latest AC boundary") {
        let log = """
        2024-01-01 09:00:00 +0000 Assertions Using Batt(Charge: 95)
        2024-01-01 11:00:00 +0000 Assertions Using AC(Charge: 70)
        2024-01-01 12:00:00 +0000 Assertions Using Batt(Charge: 80)
        2024-01-01 12:30:00 +0000 Sleep Using BATT (Charge:70%)
        """
        let session = PowerHistory.recover(from: log, current: historyCurrent())
        try expectNear(session?.start.date.timeIntervalSince1970, 1704110400, "must start at 12:00, after AC")
        try expect(session?.origin == .history, "historical start must be marked approximate")
        try expectNear(session?.estimate(at: historyCurrent())?.remaining, 10800, "must use the new 80 percent baseline")
    },
    TestCase(name: "truncated history is usable only as an approximate observation") {
        let log = "2024-01-01 12:00:00 +0000 Sleep Using Batt (Charge:80%)"
        let session = PowerHistory.recover(from: log, current: historyCurrent())
        try expect(session?.start.percent == 80, "known earlier discharge should be usable")
        try expect(session?.origin == .history, "must not claim an exact unplug time")
    },
    TestCase(name: "latest AC with no later battery entry cannot recover the old session") {
        let log = """
        2024-01-01 11:00:00 +0000 Sleep Using Batt(Charge: 80)
        2024-01-01 12:00:00 +0000 Sleep Using AC(Charge: 60)
        """
        try expect(PowerHistory.recover(from: log, current: historyCurrent()) == nil, "must not reuse discharge before AC")
    },
    TestCase(name: "malformed future and out-of-order records cannot corrupt the current segment") {
        let log = """
        invalid Using Batt(Charge: 100)
        2024-01-01 12:00:00 +0000 Sleep Using Batt(Charge: 80)
        2024-01-01 11:00:00 +0000 Sleep Using AC(Charge: 90)
        2024-01-01 14:00:00 +0000 Sleep Using AC(Charge: 60)
        2024-01-01 12:30:00 +0000 Sleep Using Batt(Charge: 999)
        """
        try expect(PowerHistory.recover(from: log, current: historyCurrent())?.start.percent == 80, "invalid records must not reset valid history")
    },
    TestCase(name: "a battery charge increase invalidates the preceding historical baseline") {
        let log = """
        2024-01-01 10:00:00 +0000 Sleep Using Batt(Charge: 90)
        2024-01-01 11:00:00 +0000 Sleep Using Batt(Charge: 40)
        2024-01-01 12:00:00 +0000 Sleep Using Batt(Charge: 80)
        """
        try expect(PowerHistory.recover(from: log, current: historyCurrent())?.start.percent == 80, "unobserved charging must not be included")
    },
    TestCase(name: "AC now or a current charge above the latest record rejects recovery") {
        let log = "2024-01-01 12:00:00 +0000 Sleep Using Batt(Charge: 40)"
        try expect(PowerHistory.recover(from: log, current: historyCurrent()) == nil, "stale history with increased charge must be rejected")
        try expect(PowerHistory.recover(from: log, current: historyCurrent(30, onBattery: false)) == nil, "AC has no active discharge session")
    }
]
