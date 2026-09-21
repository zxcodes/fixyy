import AppKit

@MainActor
public final class RewriteCardController {
    public var onDismiss: (() -> Void)?
    public var onJob: ((JobSummary) -> Void)?
    public var onSettings: (() -> Void)?

    private var panel: RewritePanel?
    private var viewController: RewriteCardViewController?
    private var monitors: [Any] = []
    private let rewrite: RewriteService
    private let selection: SelectionHandling
    private let status: StatusItemController?
    private let info: ModelInfo
    private let countTokens: @MainActor (String) async -> Int?
    private var sourceText = ""
    private var resultText = ""
    private var promptTokens: Int?
    private var outputTokens: Int?
    private var editable = true
    private var mode: RewriteKind?
    private var generateTask: Task<Void, Never>?
    private var jobStart: ContinuousClock.Instant?
    private var generationID = UUID()

    public init(
        rewrite: RewriteService,
        selection: SelectionHandling,
        status: StatusItemController? = nil,
        info: ModelInfo,
        countTokens: @escaping @MainActor (String) async -> Int? = { _ in nil }
    ) {
        self.rewrite = rewrite
        self.selection = selection
        self.status = status
        self.info = info
        self.countTokens = countTokens
    }

    public var isVisible: Bool { panel?.isVisible == true }

    public func present(sourceText: String, editable: Bool, promptTokens: Int? = nil) {
        generationID = UUID()
        generateTask?.cancel()
        self.sourceText = sourceText
        self.promptTokens = promptTokens
        self.editable = editable
        resultText = ""
        outputTokens = nil
        mode = nil

        let controller = RewriteCardViewController()
        controller.onCustom = { [weak self] line in self?.run(.custom(line)) }
        controller.onPreset = { [weak self] kind in self?.run(kind) }
        controller.onApply = { [weak self] in self?.apply() }
        controller.onCopy = { [weak self] in self?.copyResult() }
        controller.onRegenerate = { [weak self] in self?.regenerate() }
        controller.onClose = { [weak self] in self?.dismiss() }
        controller.onBannerAction = { [weak self] action in self?.performBanner(action) }
        self.viewController = controller

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let height = min(360, screen.height * 0.6)
        let panel = RewritePanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 420, height: height)),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = FloatingPanelBehavior.standard
        panel.contentViewController = controller
        let origin = SelectionAnchor.panelOrigin(width: 420, height: height)
        panel.setFrameOrigin(origin)
        self.panel = panel

        controller.setSourceText(sourceText)
        controller.setEditable(editable)
        controller.setBanner(nil)
        controller.setRunning(false)
        controller.setMeter(used: promptTokens, limit: info.contextSize, label: "\(info.variantName) · On-device")

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
        Task { @MainActor [weak panel, weak controller] in
            if let field = controller?.instructionField {
                panel?.makeFirstResponder(field)
            }
        }
    }

    public func presentError(_ error: AppError) {
        viewController?.setBanner(error)
        status?.showError(error)
        if error.opensAccessibilitySettings { SettingsLinks.openAccessibility() }
        if error.opensIntelligenceSettings { SettingsLinks.openIntelligence() }
    }

    public func cycleMode() {
        let modes = RewriteKind.modes
        let next: RewriteKind
        if let active = mode, let index = modes.firstIndex(of: active) {
            next = modes[(index + 1) % modes.count]
        } else {
            next = modes[0]
        }
        run(next)
    }

    public func dismiss() {
        status?.hide()
        dismissKeepingStatus()
    }

    private func dismissKeepingStatus() {
        generationID = UUID()
        generateTask?.cancel()
        removeMonitors()
        panel?.orderOut(nil)
        onDismiss?()
    }

    private func run(_ kind: RewriteKind, sampling: RewriteSampling = .automatic) {
        guard !sourceText.isEmpty else { return }
        generateTask?.cancel()
        generationID = UUID()
        let generationID = self.generationID
        mode = kind
        resultText = ""
        outputTokens = nil
        viewController?.setBanner(nil)
        viewController?.setRunning(true)
        viewController?.setSourceText(sourceText)
        status?.showWorking()
        jobStart = .now
        generateTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await partial in self.rewrite.stream(text: self.sourceText, kind: kind, sampling: sampling) {
                    guard self.generationID == generationID else { return }
                    self.resultText = partial
                    self.viewController?.setResultText(partial)
                }
                guard self.generationID == generationID else { return }
                self.viewController?.setRunning(false)
                self.status?.hide()
                self.outputTokens = await self.countTokens(self.resultText) ?? self.resultText.count / 4
                guard self.generationID == generationID else { return }
                self.updateMeter()
            } catch is CancellationError {
                guard self.generationID == generationID else { return }
                self.viewController?.setRunning(false)
                self.status?.hide()
            } catch let error as AppError where error == .cancelled {
                guard self.generationID == generationID else { return }
                self.viewController?.setRunning(false)
                self.status?.hide()
            } catch let error as AppError {
                guard self.generationID == generationID else { return }
                self.viewController?.setRunning(false)
                self.viewController?.setBanner(error)
                self.status?.showError(error)
                self.report(.error(error))
            } catch {
                guard self.generationID == generationID else { return }
                self.viewController?.setRunning(false)
                self.viewController?.setBanner(.stalled)
                self.status?.showError(.stalled)
                self.report(.error(.stalled))
            }
        }
    }

    private func regenerate() {
        run(mode ?? .clearer, sampling: .randomTop(50))
    }

    private func retry() {
        if let mode { run(mode) }
    }

    private func apply() {
        let text = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        generationID = UUID()
        generateTask?.cancel()
        Task { [weak self] in
            guard let self else { return }
            await self.selection.paste(text)
            self.status?.showSuccess("Rewritten")
            self.report(.applied)
            self.dismissKeepingStatus()
        }
    }

    private func copyResult() {
        let text = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        generationID = UUID()
        generateTask?.cancel()
        selection.leaveOnClipboard(text)
        status?.showSuccess("Copied")
        report(.copied)
        dismissKeepingStatus()
    }

    private func performBanner(_ action: AppError.Action) {
        switch action {
        case .openAccessibility: SettingsLinks.openAccessibility()
        case .openIntelligence: SettingsLinks.openIntelligence()
        case .retry: retry()
        case .copyResult: copyResult()
        }
    }

    private func updateMeter() {
        let used: Int?
        if promptTokens != nil || outputTokens != nil {
            used = (promptTokens ?? sourceText.count / 4) + (outputTokens ?? 0)
        } else {
            used = nil
        }
        viewController?.setMeter(used: used, limit: info.contextSize, label: "\(info.variantName) · On-device")
    }

    private func report(_ outcome: JobSummary.Outcome) {
        let latency = jobStart.map { ContinuousClock.now - $0 } ?? .zero
        onJob?(JobSummary(
            kind: .rewrite,
            promptTokens: promptTokens,
            outputTokens: outputTokens,
            latency: TimeInterval(latency.components.seconds) + TimeInterval(latency.components.attoseconds) / 1e18,
            outcome: outcome
        ))
    }

    private func installMonitors() {
        removeMonitors()
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.handleKey(event) ?? event
        }) {
            monitors.append(local)
        }
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            DispatchQueue.main.async { self?.dismiss() }
        }) {
            monitors.append(outside)
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard panel?.isKeyWindow == true else { return event }
        let command = event.modifierFlags.contains(.command)
        if event.keyCode == 53 {
            dismiss()
            return nil
        }
        if command {
            if event.keyCode == 43 || event.charactersIgnoringModifiers == "," {
                onSettings?()
                dismiss()
                return nil
            }
            switch event.keyCode {
            case 18, 19, 20, 21:
                let index = Int(event.keyCode - 18)
                let modes = RewriteKind.modes
                if index < modes.count { run(modes[index]) }
                return nil
            case 15:
                regenerate()
                return nil
            case 8:
                if let editor = panel?.firstResponder as? NSTextView,
                   editor.selectedRange().length > 0 {
                    return event
                }
                copyResult()
                return nil
            default:
                return event
            }
        }
        return event
    }

    private func removeMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }
}

private final class RewritePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class RewriteCardViewController: NSViewController, NSTextFieldDelegate {
    var onCustom: ((String) -> Void)?
    var onPreset: ((RewriteKind) -> Void)?
    var onApply: (() -> Void)?
    var onCopy: (() -> Void)?
    var onRegenerate: (() -> Void)?
    var onClose: (() -> Void)?
    var onBannerAction: ((AppError.Action) -> Void)?

    let instructionField = NSTextField()
    let textView = NSTextView()

    private let effectView = NSVisualEffectView()
    private let scrollView = NSScrollView()
    private let bannerRow = NSStackView()
    private let bannerLabel = NSTextField(labelWithString: "")
    private let bannerButton = NSButton(title: "", target: nil, action: nil)
    private let modelLabel = NSTextField(labelWithString: "")
    private let meterLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let applyButton = NSButton(title: "Apply", target: nil, action: nil)
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let regenerateButton = NSButton(title: "Regenerate", target: nil, action: nil)
    private var bannerAction: AppError.Action?
    private var editable = true
    private var running = false
    private var hasGeneratedResult = false

    override func loadView() {
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        view = effectView
        buildLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        instructionField.delegate = self
    }

    private func buildLayout() {
        let title = NSTextField(labelWithString: "Rewrite")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .secondaryLabelColor

        let closeButton = NSButton(
            image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!,
            target: self,
            action: #selector(closeClicked)
        )
        closeButton.isBordered = false
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = .secondaryLabelColor

        let header = NSStackView(views: [title, NSView(), closeButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.setHuggingPriority(.defaultLow, for: .horizontal)

        instructionField.placeholderString = "Tell Fixyy how to rewrite…"
        instructionField.font = .systemFont(ofSize: 13)
        instructionField.bezelStyle = .roundedBezel
        instructionField.target = self
        instructionField.action = #selector(submitInstruction)
        instructionField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let sendButton = NSButton(
            image: NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Send")!,
            target: self,
            action: #selector(submitInstruction)
        )
        sendButton.isBordered = false
        sendButton.imageScaling = .scaleProportionallyDown

        let inputRow = NSStackView(views: [instructionField, sendButton])
        inputRow.orientation = .horizontal
        inputRow.spacing = 8
        inputRow.alignment = .centerY

        let presets = RewriteKind.modes.map { kind -> NSButton in
            let button = NSButton(title: kind.chipTitle, target: self, action: #selector(presetClicked(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.tag = RewriteKind.modes.firstIndex(of: kind) ?? 0
            return button
        }
        let presetRow = NSStackView(views: presets)
        presetRow.orientation = .horizontal
        presetRow.distribution = .fillEqually
        presetRow.spacing = 8

        let warning = NSImageView(
            image: NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Error")!
        )
        warning.contentTintColor = .systemOrange
        bannerLabel.font = .systemFont(ofSize: 12)
        bannerLabel.lineBreakMode = .byTruncatingTail
        bannerButton.bezelStyle = .rounded
        bannerButton.controlSize = .small
        bannerButton.target = self
        bannerButton.action = #selector(bannerClicked)
        bannerRow.orientation = .horizontal
        bannerRow.spacing = 8
        bannerRow.alignment = .centerY
        bannerRow.addArrangedSubview(warning)
        bannerRow.addArrangedSubview(bannerLabel)
        bannerRow.addArrangedSubview(NSView())
        bannerRow.addArrangedSubview(bannerButton)
        bannerRow.isHidden = true

        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

        modelLabel.font = .systemFont(ofSize: 11)
        modelLabel.textColor = .secondaryLabelColor
        meterLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        meterLabel.textColor = .secondaryLabelColor
        let leftStack = NSStackView(views: [modelLabel, meterLabel])
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 2

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        regenerateButton.bezelStyle = .rounded
        regenerateButton.controlSize = .regular
        regenerateButton.target = self
        regenerateButton.action = #selector(regenerateClicked)
        copyButton.bezelStyle = .rounded
        copyButton.target = self
        copyButton.action = #selector(copyClicked)
        applyButton.bezelStyle = .rounded
        applyButton.target = self
        applyButton.action = #selector(applyClicked)

        let footer = NSStackView(views: [leftStack, NSView(), spinner, regenerateButton, copyButton, applyButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8

        let column = NSStackView(views: [header, inputRow, presetRow, bannerRow, scrollView, footer])
        column.orientation = .vertical
        column.spacing = 10
        column.alignment = .leading
        column.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        column.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(column)

        inputRow.translatesAutoresizingMaskIntoConstraints = false
        presetRow.translatesAutoresizingMaskIntoConstraints = false
        bannerRow.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        header.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            column.topAnchor.constraint(equalTo: effectView.topAnchor),
            column.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
            header.widthAnchor.constraint(equalTo: column.widthAnchor),
            inputRow.widthAnchor.constraint(equalTo: column.widthAnchor),
            presetRow.widthAnchor.constraint(equalTo: column.widthAnchor),
            bannerRow.widthAnchor.constraint(equalTo: column.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: column.widthAnchor),
            footer.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    func setSourceText(_ text: String) {
        hasGeneratedResult = false
        textView.string = text
        updateActionButtons()
    }

    func setResultText(_ text: String) {
        hasGeneratedResult = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        textView.string = text
        textView.scrollToEndOfDocument(nil)
        updateActionButtons()
    }

    func setRunning(_ running: Bool) {
        self.running = running
        if running {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
        updateActionButtons()
    }

    func setEditable(_ editable: Bool) {
        self.editable = editable
        updateActionButtons()
    }

    func setBanner(_ error: AppError?) {
        bannerAction = error?.action
        if let error {
            bannerLabel.stringValue = error.message
            if let action = error.action {
                bannerButton.title = bannerTitle(action)
                bannerButton.isHidden = false
            } else {
                bannerButton.isHidden = true
            }
            bannerRow.isHidden = false
        } else {
            bannerRow.isHidden = true
        }
    }

    func setMeter(used: Int?, limit: Int, label: String) {
        modelLabel.stringValue = label
        if let used {
            let filled = max(0, min(5, Int((Double(used) / Double(max(1, limit)) * 5).rounded())))
            let blocks = String(repeating: "▮", count: filled) + String(repeating: "▯", count: 5 - filled)
            meterLabel.stringValue = "\(blocks) \(used.formatted()) / \(limit.formatted())"
        } else {
            meterLabel.stringValue = ""
        }
    }

    private func updateActionButtons() {
        applyButton.isHidden = !editable
        applyButton.isEnabled = hasGeneratedResult && !running
        copyButton.isEnabled = hasGeneratedResult && !running
        regenerateButton.isEnabled = !running
        if editable {
            applyButton.keyEquivalent = "\r"
            copyButton.keyEquivalent = ""
        } else {
            copyButton.keyEquivalent = "\r"
            applyButton.keyEquivalent = ""
        }
    }

    private func bannerTitle(_ action: AppError.Action) -> String {
        switch action {
        case .openAccessibility, .openIntelligence: "Open Settings"
        case .retry: "Retry"
        case .copyResult: "Copy"
        }
    }

    @objc private func submitInstruction() {
        let line = instructionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        onCustom?(line)
    }

    @objc private func presetClicked(_ sender: NSButton) {
        let modes = RewriteKind.modes
        guard sender.tag < modes.count else { return }
        onPreset?(modes[sender.tag])
    }

    @objc private func applyClicked() { onApply?() }
    @objc private func copyClicked() { onCopy?() }
    @objc private func regenerateClicked() { onRegenerate?() }
    @objc private func closeClicked() { onClose?() }
    @objc private func bannerClicked() {
        if let bannerAction { onBannerAction?(bannerAction) }
    }
}
