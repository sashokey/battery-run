import Foundation
import IOKit.ps

enum BatteryReader {
    static func sample(from descriptions: [[String: Any]], at date: Date, powerProperties: [String: Any] = [:]) -> BatterySample? {
        guard let battery = descriptions.first(where: { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }),
              battery[kIOPSIsPresentKey] as? Bool != false,
              let current = (battery[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue,
              let maximum = (battery[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue,
              current.isFinite, maximum.isFinite, maximum > 0,
              let source = battery[kIOPSPowerSourceStateKey] as? String,
              source == kIOPSBatteryPowerValue || source == kIOPSACPowerValue else { return nil }
        let onBattery = source == kIOPSBatteryPowerValue
        let isCharging = !onBattery && battery[kIOPSIsChargingKey] as? Bool == true
        let seconds = number(battery[kIOPSTimeToFullChargeKey]).map { $0.doubleValue * 60 }
        let timeToFull = isCharging ? seconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } : nil
        let telemetry = powerProperties["PowerTelemetryData"] as? [String: Any] ?? [:]
        let milliwatts = number(telemetry["BatteryPower"]).map { Double($0.int64Value) }
        let input = number(telemetry["SystemPowerIn"])?.doubleValue
        let count = number(telemetry["SystemPowerInAccumulatorCount"])?.int64Value
        let sample = BatterySample(
            date: date, percent: current / maximum * 100, onBattery: onBattery,
            isCharging: isCharging, timeToFull: timeToFull,
            batteryWatts: milliwatts.map { $0 / 1000 } ?? batteryPower(from: powerProperties),
            inputWatts: onBattery ? nil : input.flatMap { $0 >= 0 ? $0 / 1000 : nil },
            powerSampleCount: count.flatMap(UInt64.init(exactly:))
        )
        return sample.isValid ? sample : nil
    }

    static func read(at date: Date = Date()) -> BatterySample? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        let descriptions = sources.compactMap {
            IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
        }
        return sample(from: descriptions, at: date, powerProperties: readPowerProperties())
    }

    private static func readPowerProperties() -> [String: Any] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return [:] }
        defer { IOObjectRelease(service) }
        var properties = [String: Any]()
        for key in ["PowerTelemetryData", "Voltage", "InstantAmperage", "Amperage"] {
            properties[key] = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        return properties
    }

    private static func batteryPower(from properties: [String: Any]) -> Double? {
        guard let voltage = number(properties["Voltage"])?.doubleValue, voltage > 0,
              let current = number(properties["InstantAmperage"]) ?? number(properties["Amperage"]) else { return nil }
        let watts = (voltage / 1000) * (Double(current.int64Value) / 1000)
        return watts.isFinite ? watts : nil
    }

    private static func number(_ value: Any?) -> NSNumber? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite else { return nil }
        return value
    }
}
