import AppKit

@MainActor
final class AppKitDashboard: NSView {
    private let charge = NSTextField(labelWithString: "—")
    private let source = NSTextField(labelWithString: "")
    private let batteryImage = NSImageView()
    private let chargeBar = NSProgressIndicator()
    private let remaining = NSTextField(labelWithString: "—")
    private let fullDuration = NSTextField(labelWithString: "—")
    private let startLabel = NSTextField(labelWithString: "Discharge started")
    private let startValue = NSTextField(labelWithString: "—")
    private let startCharge = NSTextField(labelWithString: "—")
    private let forecastStartCharge = NSTextField(labelWithString: "—")
    private let forecastStartTime = NSTextField(labelWithString: "—")
    private let elapsed = NSTextField(labelWithString: "—")
    private let used = NSTextField(labelWithString: "—")
    private let rate = NSTextField(labelWithString: "—")
    private let explanation = NSTextField(wrappingLabelWithString: "")
    private let originNote = NSTextField(wrappingLabelWithString: "")
    private let storageNotice = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()
    private let progressRow = NSStackView()
    private let available = NSStackView()
    private let unavailable = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) { nil }

    func update(model: DashboardModel, notice: String?, isReadingHistory: Bool) {
        available.isHidden = model.sample == nil
        unavailable.isHidden = model.sample != nil
        if let sample = model.sample {
            charge.stringValue = DashboardModel.percent(sample.percent)
            source.stringValue = sample.onBattery ? "On Battery" : "External Power"
            chargeBar.doubleValue = sample.percent
            let level = Int((sample.percent / 25).rounded()) * 25
            let symbol = sample.onBattery ? "battery.\(level)percent" : "battery.100percent.bolt"
            batteryImage.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        remaining.stringValue = model.remaining
        fullDuration.stringValue = model.fullDuration
        startLabel.stringValue = model.startLabel
        startValue.stringValue = model.startValue
        startCharge.stringValue = model.startCharge
        forecastStartCharge.stringValue = model.forecastStartCharge
        forecastStartTime.stringValue = model.forecastStartTime
        elapsed.stringValue = model.elapsed
        used.stringValue = model.chargeUsed
        rate.stringValue = model.rate
        explanation.stringValue = model.explanation
        originNote.stringValue = model.originNote ?? ""
        originNote.isHidden = model.originNote == nil
        storageNotice.stringValue = notice ?? ""
        storageNotice.isHidden = notice == nil
        progressRow.isHidden = !isReadingHistory
        if isReadingHistory { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        needsLayout = true
    }

    private func configure() {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        addSubview(scroll)
        let document = FlippedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        let root = verticalStack(spacing: 24)
        root.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(root)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            root.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            root.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24)
        ])
        available.orientation = .vertical
        available.alignment = .leading
        available.spacing = 24
        root.addArrangedSubview(available)
        available.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let descriptor = NSFont.systemFont(ofSize: 40, weight: .semibold).fontDescriptor
        charge.font = NSFont(descriptor: descriptor.withDesign(.rounded) ?? descriptor, size: 40)
        source.textColor = .secondaryLabelColor
        let headerText = verticalStack(spacing: 4, views: [charge, source])
        batteryImage.contentTintColor = .controlAccentColor
        batteryImage.imageScaling = .scaleProportionallyUpOrDown
        batteryImage.setAccessibilityElement(false)
        batteryImage.widthAnchor.constraint(equalToConstant: 56).isActive = true
        batteryImage.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let header = NSStackView(views: [batteryImage, headerText])
        header.spacing = 16
        header.alignment = .centerY
        available.addArrangedSubview(header)

        chargeBar.style = .bar
        chargeBar.isIndeterminate = false
        chargeBar.maxValue = 100
        chargeBar.setAccessibilityLabel("Battery charge")
        addFullWidth(chargeBar, to: available)

        let estimates = NSStackView(views: [estimateColumn("Remaining to 0%", value: remaining), estimateColumn("100% → 0%", value: fullDuration)])
        estimates.distribution = .fillEqually
        estimates.spacing = 24
        estimates.alignment = .top
        addFullWidth(card(containing: estimates), to: available)

        let sessionTitle = NSTextField(labelWithString: "Current Session")
        sessionTitle.font = .systemFont(ofSize: 12, weight: .medium)
        let labels = [
            startLabel,
            NSTextField(labelWithString: "Starting charge"),
            NSTextField(labelWithString: "Charge at forecast start"),
            NSTextField(labelWithString: "Forecast start time"),
            NSTextField(labelWithString: "Elapsed"),
            NSTextField(labelWithString: "Charge used"),
            NSTextField(labelWithString: "Average drain")
        ]
        let values = [startValue, startCharge, forecastStartCharge, forecastStartTime, elapsed, used, rate]
        let grid = NSGridView(views: zip(labels, values).map { [$0.0, $0.1] })
        grid.rowSpacing = 14
        grid.columnSpacing = 24
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .trailing
        for label in labels { label.textColor = .secondaryLabelColor }
        for value in values {
            value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            value.isSelectable = true
        }
        let session = verticalStack(spacing: 8, views: [sessionTitle])
        addFullWidth(card(containing: grid), to: session)
        addFullWidth(session, to: available)

        let footer = verticalStack(spacing: 8)
        for label in [explanation, originNote, storageNotice] {
            label.font = .systemFont(ofSize: 12)
            label.textColor = label == storageNotice ? .labelColor : .secondaryLabelColor
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            addFullWidth(label, to: footer)
        }
        addFullWidth(footer, to: available)
        progress.style = .spinning
        progress.controlSize = .small
        progressRow.addArrangedSubview(progress)
        let historyLabel = NSTextField(labelWithString: "Reading power history…")
        historyLabel.font = .systemFont(ofSize: 11)
        historyLabel.textColor = .secondaryLabelColor
        progressRow.addArrangedSubview(historyLabel)
        progressRow.spacing = 8
        available.addArrangedSubview(progressRow)

        let emptyTitle = NSTextField(labelWithString: "Battery Unavailable")
        emptyTitle.font = .systemFont(ofSize: 20, weight: .semibold)
        let emptyText = NSTextField(wrappingLabelWithString: "No readable internal battery was found. Try refreshing the battery data.")
        emptyText.alignment = .center
        emptyText.textColor = .secondaryLabelColor
        let emptyContent = verticalStack(spacing: 12, views: [emptyTitle, emptyText])
        emptyContent.alignment = .centerX
        emptyContent.translatesAutoresizingMaskIntoConstraints = false
        unavailable.addSubview(emptyContent)
        root.addArrangedSubview(unavailable)
        NSLayoutConstraint.activate([
            unavailable.widthAnchor.constraint(equalTo: root.widthAnchor),
            unavailable.heightAnchor.constraint(equalToConstant: 420),
            emptyContent.leadingAnchor.constraint(equalTo: unavailable.leadingAnchor),
            emptyContent.trailingAnchor.constraint(equalTo: unavailable.trailingAnchor),
            emptyContent.centerYAnchor.constraint(equalTo: unavailable.centerYAnchor)
        ])
        update(model: DashboardModel(sample: nil, session: nil, forecastStart: nil), notice: nil, isReadingHistory: false)
    }

    private func estimateColumn(_ title: String, value: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        value.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        value.isSelectable = true
        return verticalStack(spacing: 8, views: [label, value])
    }

    private func verticalStack(spacing: CGFloat, views: [NSView] = []) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    private func addFullWidth(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func card(containing content: NSView) -> NSView {
        let wrapper = NSView()
        let background = NSBox()
        background.boxType = .custom
        background.borderWidth = 0
        background.cornerRadius = 12
        background.fillColor = .controlColor
        for child in [background, content] {
            child.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(child)
        }
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            background.topAnchor.constraint(equalTo: wrapper.topAnchor),
            background.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 16),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -16)
        ])
        return wrapper
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
