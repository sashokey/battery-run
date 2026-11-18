import Foundation

struct BatterySample: Codable, Equatable, Sendable {
    let date: Date
    let percent: Double
    let onBattery: Bool

    var isValid: Bool {
        percent.isFinite && (0...100).contains(percent) && date.timeIntervalSince1970.isFinite
    }
}

enum SessionOrigin: String, Codable, Sendable {
    case observed
    case history
    case monitoring
}

struct DischargeEstimate: Sendable {
    let remaining: TimeInterval
    let fullDuration: TimeInterval
    let ratePerHour: Double
}

struct DischargeSession: Codable, Equatable, Sendable {
    let start: BatterySample
    let origin: SessionOrigin

    func estimate(at current: BatterySample, since forecastStart: BatterySample? = nil) -> DischargeEstimate? {
        let start = forecastStart ?? self.start
        let elapsed = current.date.timeIntervalSince(start.date)
        let consumed = start.percent - current.percent
        guard start.isValid, current.isValid, start.onBattery, current.onBattery,
              elapsed.isFinite, elapsed >= 60, consumed >= 1 else { return nil }
        let secondsPerPoint = elapsed / consumed
        return DischargeEstimate(
            remaining: secondsPerPoint * current.percent,
            fullDuration: secondsPerPoint * 100,
            ratePerHour: consumed / elapsed * 3600
        )
    }
}

struct SessionTracker: Codable, Sendable {
    var session: DischargeSession?
    var lastSample: BatterySample?
    var historyFloor: Date?
    private(set) var forecastStart: BatterySample?
    private var canRecoverForecast = true
    private var hasContinuousObservation = false

    private enum CodingKeys: String, CodingKey {
        case session, lastSample, historyFloor
    }

    init(session: DischargeSession? = nil, lastSample: BatterySample? = nil, historyFloor: Date? = nil) {
        self.session = session
        self.lastSample = lastSample
        self.historyFloor = historyFloor
    }

    mutating func markObservationGap() {
        hasContinuousObservation = false
    }

    mutating func markWake() {
        markObservationGap()
        forecastStart = nil
        canRecoverForecast = false
    }

    mutating func reconcile(history: String, current: BatterySample) {
        reconcile(history: PowerHistory(from: history, before: current.date), current: current)
    }

    mutating func reconcile(history: PowerHistory, current: BatterySample) {
        update(current)
        guard current.isValid, current.onBattery else { return }
        let records = history.samples.filter { $0.date >= (historyFloor ?? .distantPast) }
        let recovered = PowerHistory.recover(samples: records, current: current)
        var previous: BatterySample?
        var interruption: Date?
        for record in records {
            if let session, record.date > session.start.date,
               !record.onBattery || previous.map({ record.percent > $0.percent }) == true {
                interruption = record.date
            }
            previous = record
        }
        if let interruption {
            historyFloor = interruption
            session = recovered ?? DischargeSession(start: current, origin: .monitoring)
            if let forecastStart, forecastStart.date < interruption {
                self.forecastStart = recovered?.start ?? current
            }
        } else if let recovered, session?.origin != .observed,
                  session.map({ recovered.start.date < $0.start.date }) ?? true {
            session = recovered
        }
        guard canRecoverForecast, let wake = history.lastWake, recovered != nil, let session else { return }
        let samplesSinceWake = history.samples.dropFirst(wake.sampleIndex).filter {
            $0.date >= (historyFloor ?? .distantPast)
        }
        let start = session.start.date > wake.date ? session.start : PowerHistory.recover(samples: samplesSinceWake, current: current)?.start
        if let start, start.percent >= current.percent {
            forecastStart = start
            canRecoverForecast = false
        }
    }

    mutating func update(_ sample: BatterySample) {
        guard sample.isValid else { return }
        if let lastSample, sample.date < lastSample.date { return }
        defer {
            lastSample = sample
            hasContinuousObservation = true
        }
        guard sample.onBattery else {
            session = nil
            historyFloor = sample.date
            forecastStart = nil
            canRecoverForecast = false
            return
        }
        let increased = lastSample.map { sample.percent > $0.percent } ?? false
        if forecastStart == nil || increased {
            forecastStart = sample
        }
        if session == nil || increased {
            let observed = hasContinuousObservation && lastSample?.onBattery == false
            let origin: SessionOrigin = observed ? .observed : .monitoring
            if observed || (increased && hasContinuousObservation) {
                historyFloor = sample.date
                canRecoverForecast = false
            } else if let lastSample {
                historyFloor = max(historyFloor ?? .distantPast, lastSample.date)
            }
            session = DischargeSession(start: sample, origin: origin)
        }
    }
}
