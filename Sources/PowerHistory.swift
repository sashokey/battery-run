import Foundation

enum PowerHistory {
    static func samples(from text: String, before now: Date) -> [BatterySample] {
        guard let expression = try? NSRegularExpression(
            pattern: #"\bUsing\s+(Batt|AC)\s*\(Charge:\s*(\d{1,3})%?\)"#,
            options: .caseInsensitive
        ) else { return [] }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        formatter.isLenient = false
        var result: [BatterySample] = []
        for line in text.split(separator: "\n") {
            let line = String(line)
            guard line.count >= 25,
                  let date = formatter.date(from: String(line.prefix(25))), date <= now,
                  let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let sourceRange = Range(match.range(at: 1), in: line),
                  let chargeRange = Range(match.range(at: 2), in: line),
                  let percent = Double(line[chargeRange]) else { continue }
            let sample = BatterySample(date: date, percent: percent, onBattery: line[sourceRange].lowercased() == "batt")
            guard sample.isValid, result.last.map({ date >= $0.date }) ?? true else { continue }
            result.append(sample)
        }
        return result
    }

    static func recover(from text: String, current: BatterySample) -> DischargeSession? {
        recover(samples: samples(from: text, before: current.date), current: current)
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
