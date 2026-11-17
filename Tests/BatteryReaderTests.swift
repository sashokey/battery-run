import Foundation
import IOKit.ps

let batteryReaderTests = [
    TestCase(name: "internal battery is selected over a peripheral and capacity is normalized") {
        let descriptions: [[String: Any]] = [
            [kIOPSTypeKey: "UPS", kIOPSCurrentCapacityKey: 10, kIOPSMaxCapacityKey: 100],
            [kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSIsPresentKey: true,
             kIOPSCurrentCapacityKey: 3000, kIOPSMaxCapacityKey: 5000,
             kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue]
        ]
        let sample = BatteryReader.sample(from: descriptions, at: Date(timeIntervalSince1970: 1000))
        try expectNear(sample?.percent, 60, "must scale internal battery capacity to percent")
        try expect(sample?.onBattery == true, "must use the battery power-source state")
    },
    TestCase(name: "external power is distinguished from a paused charge") {
        let descriptions: [[String: Any]] = [
            [kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 80,
             kIOPSMaxCapacityKey: 100, kIOPSIsChargingKey: false,
             kIOPSPowerSourceStateKey: kIOPSACPowerValue]
        ]
        try expect(BatteryReader.sample(from: descriptions, at: Date())?.onBattery == false, "not charging does not mean running on battery")
    },
    TestCase(name: "missing absent or invalid battery data is unavailable rather than fabricated") {
        for descriptions: [[String: Any]] in [
            [],
            [[kIOPSTypeKey: "UPS", kIOPSCurrentCapacityKey: 80, kIOPSMaxCapacityKey: 100]],
            [[kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 80, kIOPSMaxCapacityKey: 0]],
            [[kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSIsPresentKey: false, kIOPSCurrentCapacityKey: 80, kIOPSMaxCapacityKey: 100]],
            [[kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: -1, kIOPSMaxCapacityKey: 100]],
            [[kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 80, kIOPSMaxCapacityKey: 100]]
        ] {
            try expect(BatteryReader.sample(from: descriptions, at: Date()) == nil, "invalid battery dictionary must yield no sample")
        }
    }
]

let batteryHardwareTests = [
    TestCase(name: "real IOKit battery read returns a valid internal battery sample") {
        let sample = BatteryReader.read()
        try expect(sample?.isValid == true, "this Mac has a readable battery")
    }
]
