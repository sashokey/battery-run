import Foundation

struct DashboardModel {
    let sample: BatterySample?
    let session: DischargeSession?

    var activeSession: DischargeSession? { sample?.onBattery == true ? session : nil }
    var estimate: DischargeEstimate? { sample.flatMap { activeSession?.estimate(at: $0) } }
    var remaining: String { DurationText.string(estimate?.remaining) }
    var fullDuration: String { DurationText.string(estimate?.fullDuration) }
    var startLabel: String { activeSession?.origin == .monitoring ? "Monitoring since" : "Discharge started" }
    var startValue: String {
        guard let activeSession else { return "—" }
        let date = activeSession.start.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return activeSession.origin == .history ? "≈ \(date)" : date
    }
    var elapsed: String {
        DurationText.string(sample.flatMap { current in activeSession.map { current.date.timeIntervalSince($0.start.date) } })
    }
    var startCharge: String { activeSession.map { Self.percent($0.start.percent) } ?? "—" }
    var chargeUsed: String {
        guard let activeSession, let sample else { return "—" }
        return Self.percent(max(0, activeSession.start.percent - sample.percent))
    }
    var rate: String { estimate.map { Self.percent($0.ratePerHour) + "/h" } ?? "—" }
    var explanation: String {
        guard let sample else { return "Battery data is temporarily unavailable." }
        guard sample.onBattery else { return "The Mac is using external power. A new session starts when it switches to battery." }
        if estimate == nil { return "Collecting data. An estimate needs at least 1% of charge used and 1 minute of observation." }
        return "Based on the average drain since this session began, including sleep. The estimate changes with your workload."
    }
    var originNote: String? {
        switch activeSession?.origin {
        case .history: "Start reconstructed from the first available battery entry. Discharge may have started earlier."
        case .monitoring: "The unplug time is unknown. Calculations use measurements since monitoring began."
        default: nil
        }
    }
    static func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + "%"
    }
}
