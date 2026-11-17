import AppKit
import Combine
import Foundation
import IOKit.ps

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var sample: BatterySample?
    @Published private(set) var tracker = SessionTracker()
    @Published private(set) var isReadingHistory = false
    @Published private(set) var notice: String?

    let stateURL: URL
    private let readSample: () -> BatterySample?
    private var powerSource: CFRunLoopSource?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var isSleeping = false
    private var started = false

    static var defaultStateURL: URL {
        URL.applicationSupportDirectory.appending(path: "BatteryRun/session.json")
    }

    init(stateURL: URL = BatteryMonitor.defaultStateURL, readSample: @escaping () -> BatterySample? = { BatteryReader.read() }) {
        self.stateURL = stateURL
        self.readSample = readSample
        tracker = SessionStore.load(from: stateURL) ?? SessionTracker()
    }

    func refresh() {
        guard !isSleeping else { return }
        guard let current = readSample() else {
            sample = nil
            return
        }
        let previous = tracker.lastSample
        let previousSession = tracker.session
        sample = current
        tracker.update(current)
        if previous?.percent != current.percent || previous?.onBattery != current.onBattery || previousSession != tracker.session {
            persist()
        }
    }

    func start() {
        guard !started else { return }
        started = true
        refresh()
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 5
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isSleeping = true
                self?.tracker.markObservationGap()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isSleeping = false
                self?.tracker.markObservationGap()
                self?.refresh()
                self?.recoverHistory()
            }
        }
        recoverHistory()
    }

    func recoverHistory() {
        guard !isSleeping, !isReadingHistory, sample?.onBattery == true else { return }
        isReadingHistory = true
        Task { [weak self] in
            let records = await Task.detached(priority: .utility) {
                PowerHistoryLoader.run().map { PowerHistory.samples(from: $0, before: Date()) }
            }.value
            guard let self else { return }
            self.refresh()
            if !self.isSleeping, let records, let current = self.sample {
                self.tracker.reconcile(samples: records, current: current)
                self.persist()
            }
            self.isReadingHistory = false
        }
    }

    private func persist() {
        do {
            try SessionStore.save(tracker, to: stateURL)
            notice = nil
        } catch {
            notice = "This session could not be saved. Monitoring will continue while the app is open."
        }
    }
}

enum DurationText {
    static func string(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0, seconds < Double(Int.max) / 60 else { return "—" }
        if seconds == 0 { return "0m" }
        if seconds < 60 { return "<1m" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }
}
