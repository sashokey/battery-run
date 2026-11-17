import Foundation
import IOKit.ps

enum BatteryReader {
    static func sample(from descriptions: [[String: Any]], at date: Date) -> BatterySample? {
        guard let battery = descriptions.first(where: { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType }),
              battery[kIOPSIsPresentKey] as? Bool != false,
              let current = (battery[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue,
              let maximum = (battery[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue,
              current.isFinite, maximum.isFinite, maximum > 0,
              let source = battery[kIOPSPowerSourceStateKey] as? String,
              source == kIOPSBatteryPowerValue || source == kIOPSACPowerValue else { return nil }
        let sample = BatterySample(date: date, percent: current / maximum * 100, onBattery: source == kIOPSBatteryPowerValue)
        return sample.isValid ? sample : nil
    }

    static func read(at date: Date = Date()) -> BatterySample? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        let descriptions = sources.compactMap {
            IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
        }
        return sample(from: descriptions, at: date)
    }
}
