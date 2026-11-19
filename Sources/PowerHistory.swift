import Foundation

struct PowerHistory {
    private struct PowerObservation {
        let date: Date
        let onBattery: Bool
        let percent: Double?

        var sample: BatterySample? {
            percent.map { BatterySample(date: date, percent: $0, onBattery: onBattery) }
        }
    }

    private static let maximumStartupLoggingDelay: TimeInterval = 120
    private static let maximumUnplugUncertainty: TimeInterval = 60
    private var observations: [PowerObservation] = []
    private var lastWake: (date: Date, observationIndex: Int?)?
    private var lastSleep: Date?
    private var startups: [(date: Date, observation: PowerObservation?)] = []

    var samples: [BatterySample] { observations.compactMap(\.sample) }

    init(from text: String, before now: Date) {
        guard let expression = try? NSRegularExpression(
            pattern: #"\bUsing\s+(Batt|AC)\b(?:\s*\(Charge:\s*(\d{1,3})%?\))?"#,
            options: .caseInsensitive
        ) else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.isLenient = false
        var lastDate = Date.distantPast
        for line in text.split(separator: "\n") {
            let line = String(line)
            guard line.count >= 25,
                  let date = formatter.date(from: String(line.prefix(25))), date <= now, date >= lastDate else { continue }
            let event = line.dropFirst(25).split(maxSplits: 1, whereSeparator: \.isWhitespace)
            let message = (event.dropFirst().first ?? "").drop(while: \.isWhitespace)
            let isStartup = event.first == "Start" && message.hasPrefix("powerd process is started")
            let isWake = event.first == "Wake" && (message.hasPrefix("Wake from ") || message.hasPrefix("DarkWake to FullWake "))
            if isWake {
                lastWake = (date, nil)
                lastDate = date
            } else if event.first == "Sleep", message.hasPrefix("Entering Sleep state") {
                lastSleep = date
                lastWake = nil
                lastDate = date
            } else if isStartup {
                startups.append((date, nil))
                lastDate = date
            }
            guard let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let sourceRange = Range(match.range(at: 1), in: line) else { continue }
            let percent = Range(match.range(at: 2), in: line)
                .flatMap { Double(line[$0]) }
                .flatMap { (0...100).contains($0) ? $0 : nil }
            let observation = PowerObservation(date: date, onBattery: line[sourceRange].lowercased() == "batt", percent: percent)
            if isWake { lastWake = (date, observations.count) }
            if let startup = startups.indices.last, startups[startup].date == date, startups[startup].observation == nil {
                startups[startup].observation = observation
            }
            observations.append(observation)
            lastDate = date
        }
    }

    func recoverForecast(
        at current: BatterySample, bootDate: Date?, historyFloor: Date?, forecastFloor: Date?, saved: BatterySample?
    ) -> (start: BatterySample?, floor: Date?) {
        let evidenceFloor = max(historyFloor ?? .distantPast, bootDate ?? startups.last?.date ?? .distantPast)
        var startFloor = max(evidenceFloor, forecastFloor ?? .distantPast, lastSleep ?? .distantPast, lastWake?.date ?? .distantPast)
        var historicalStart = bootDate.flatMap(startupBaseline(at:))
        var previous: PowerObservation?
        var lastBatteryReading: BatterySample?
        for (index, observation) in observations.enumerated() where observation.date >= evidenceFloor {
            let sample = observation.sample
            let increased = sample.flatMap { reading in lastBatteryReading.map { reading.percent > $0.percent } } == true
            if !observation.onBattery || increased {
                startFloor = max(startFloor, observation.date)
                historicalStart = nil
            }
            let recordedUnplug = previous.map { preceding in
                let savedInInterval = saved.map { $0.date >= preceding.date && $0.date < observation.date } == true
                return !preceding.onBattery && !savedInInterval &&
                    observation.date.timeIntervalSince(preceding.date) <= Self.maximumUnplugUncertainty
            } == true
            if observation.onBattery, observation.date >= startFloor, recordedUnplug || index == lastWake?.observationIndex {
                historicalStart = sample
            }
            if !observation.onBattery {
                lastBatteryReading = nil
            } else if let sample {
                lastBatteryReading = sample
            }
            previous = observation
        }
        let floor = startFloor == .distantPast ? nil : startFloor
        let contradiction = previous.flatMap { $0.onBattery ? nil : $0.date }
            ?? lastBatteryReading.flatMap { $0.percent < current.percent ? $0.date : nil }
        if lastWake == nil, let lastSleep, lastSleep >= (bootDate ?? .distantPast) {
            historicalStart = nil
        }
        if let contradiction {
            historicalStart = nil
            if let saved, saved.date <= contradiction { return (nil, floor) }
        }
        let start = [historicalStart, saved].compactMap { $0 }.filter {
            $0.isValid && $0.onBattery && $0.date >= startFloor && $0.date <= current.date && $0.percent >= current.percent
        }.max { $0.date < $1.date }
        return (start, floor)
    }

    private func startupBaseline(at bootDate: Date) -> BatterySample? {
        guard let startup = startups.first(where: { $0.date >= bootDate }),
              startup.date.timeIntervalSince(bootDate) <= Self.maximumStartupLoggingDelay,
              let sample = startup.observation?.sample, sample.onBattery else { return nil }
        return BatterySample(date: bootDate, percent: sample.percent, onBattery: true)
    }

    static func recover(from text: String, current: BatterySample) -> DischargeSession? {
        recover(samples: PowerHistory(from: text, before: current.date).samples, current: current)
    }

    static func recover(samples: [BatterySample], current: BatterySample) -> DischargeSession? {
        guard current.isValid, current.onBattery else { return nil }
        var start: BatterySample?
        var previous: BatterySample?
        for sample in samples {
            if !sample.onBattery {
                start = nil
            } else if start == nil || previous.map({ sample.percent > $0.percent }) == true {
                start = sample
            }
            previous = sample
        }
        guard let start, let previous, previous.onBattery,
              current.percent <= previous.percent, current.date > start.date else { return nil }
        return DischargeSession(start: start, origin: .history)
    }
}
