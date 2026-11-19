import Foundation

struct DashboardModel {
    let sample: BatterySample?
    let session: DischargeSession?
    let forecastStart: BatterySample?

    var activeSession: DischargeSession? { sample?.onBattery == true ? session : nil }
    private var activeForecastStart: BatterySample? { activeSession == nil ? nil : forecastStart }
    var estimate: DischargeEstimate? {
        guard let sample, let forecastStart else { return nil }
        return activeSession?.estimate(at: sample, since: forecastStart)
    }
    var remaining: String { DurationText.string(estimate?.remaining) }
    var fullDuration: String { DurationText.string(estimate?.fullDuration) }
    var startLabel: String { activeSession?.origin == .monitoring ? "Monitoring since" : "Discharge started" }
    var startValue: String {
        guard let activeSession else { return "—" }
        let date = Self.formatStartTime(activeSession.start.date)
        return activeSession.origin == .history ? "≈ \(date)" : date
    }
    var elapsed: String { elapsed(since: activeSession?.start) }
    var startCharge: String { activeSession.map { Self.percent($0.start.percent) } ?? "—" }
    var forecastStartCharge: String { activeForecastStart.map { Self.percent($0.percent) } ?? "—" }
    var forecastStartTime: String { activeForecastStart.map { Self.formatStartTime($0.date) } ?? "—" }
    var forecastElapsed: String { elapsed(since: activeForecastStart) }
    var chargeUsed: String {
        guard let activeSession, let sample else { return "—" }
        return Self.percent(max(0, activeSession.start.percent - sample.percent))
    }
    var rate: String { estimate.map { Self.percent($0.ratePerHour) + "/h" } ?? "—" }
    var explanation: String {
        guard let sample else { return "Battery data is temporarily unavailable." }
        guard sample.onBattery else { return "The Mac is using external power. A new session starts when it switches to battery." }
        guard activeForecastStart != nil else { return "Waiting for a battery reading from a switch to battery power, wake, or Mac startup." }
        if estimate == nil { return "Collecting data. An estimate needs at least 1% of charge used and 1 minute of observation." }
        return "Based on average drain since the latest switch to battery power, wake, or Mac startup."
    }
    var originNote: String? {
        switch activeSession?.origin {
        case .history: "Start reconstructed from the first available battery entry. Discharge may have started earlier."
        case .monitoring: "The unplug time is unknown. Session totals use measurements since monitoring began."
        default: nil
        }
    }
    static func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + "%"
    }

    private func elapsed(since start: BatterySample?) -> String {
        guard let sample, let start else { return "—" }
        return DurationText.string(sample.date.timeIntervalSince(start.date))
    }

    private static func formatStartTime(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
