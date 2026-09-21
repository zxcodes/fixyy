import AppKit
import SwiftUI

@MainActor
public final class RewriteCardController: NSObject, NSWindowDelegate {
    public var onDismiss: (() -> Void)?
    public var onJob: ((JobSummary) -> Void)?
    public var onSettings: (() -> Void)?

    private var window: NSWindow?
    private let model = RewriteWindowModel()
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
    private var tearingDown = false

    private static let defaultSize = NSSize(width: 560, height: 460)

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
        super.init()
        model.onSubmit = { [weak self] line in self?.run(.custom(line)) }
        model.onPreset = { [weak self] kind in self?.run(kind) }
        model.onApply = { [weak self] in self?.apply() }
        model.onCopy = { [weak self] in self?.copyResult() }
        model.onRegenerate = { [weak self] in self?.regenerate() }
        model.onBannerAction = { [weak self] action in self?.performBanner(action) }
        model.onClose = { [weak self] in self?.dismiss() }
    }

    public var isVisible: Bool { window?.isVisible == true }

    public func present(sourceText: String, editable: Bool, promptTokens: Int? = nil) {
        generationID = UUID()
        generateTask?.cancel()
        self.sourceText = sourceText
        self.promptTokens = promptTokens
        self.editable = editable
        resultText = ""
        outputTokens = nil
        mode = nil

        model.instruction = ""
        model.bodyText = sourceText
        model.editable = editable
        model.hasResult = false
        model.running = false
        model.banner = nil
        model.mode = nil
        model.setMeter(used: promptTokens, limit: info.contextSize, label: "\(info.variantName) · On-device")
        model.focusToken = UUID()

        if window == nil {
            let hosting = NSHostingController(rootView: RewriteView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Rewrite"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.minSize = NSSize(width: 520, height: 380)
            window.setContentSize(Self.defaultSize)
            let origin = SelectionAnchor.panelOrigin(width: Self.defaultSize.width, height: Self.defaultSize.height)
            window.setFrameOrigin(origin)
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    public func presentError(_ error: AppError) {
        model.banner = error
        status?.showError(error)
        if error.opensAccessibilitySettings { SettingsLinks.openAccessibility() }
        if error.opensIntelligenceSettings { SettingsLinks.openIntelligence() }
    }

    public func dismiss() {
        status?.hide()
        teardown(orderOut: true)
    }

    public func windowWillClose(_ notification: Notification) {
        status?.hide()
        teardown(orderOut: false)
    }

    private func dismissKeepingStatus() {
        teardown(orderOut: true)
    }

    private func teardown(orderOut: Bool) {
        guard !tearingDown else { return }
        tearingDown = true
        generationID = UUID()
        generateTask?.cancel()
        if orderOut {
            window?.orderOut(nil)
        }
        selection.reactivateSourceApp()
        onDismiss?()
        tearingDown = false
    }

    private func run(_ kind: RewriteKind, sampling: RewriteSampling = .automatic) {
        guard !sourceText.isEmpty else { return }
        generateTask?.cancel()
        generationID = UUID()
        let generationID = self.generationID
        mode = kind
        resultText = ""
        outputTokens = nil
        model.banner = nil
        model.running = true
        model.hasResult = false
        model.mode = kind
        model.bodyText = sourceText
        status?.showWorking()
        jobStart = .now
        generateTask = Task { [weak self] in
            guard let self else { return }
            do {
                var lastPublish = ContinuousClock.now.advanced(by: Duration.seconds(-1))
                for try await partial in self.rewrite.stream(text: self.sourceText, kind: kind, sampling: sampling) {
                    guard self.generationID == generationID else { return }
                    self.resultText = partial
                    let now = ContinuousClock.now
                    if now - lastPublish >= Duration.milliseconds(80) {
                        lastPublish = now
                        self.model.bodyText = partial
                        self.model.hasResult = !partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                }
                guard self.generationID == generationID else { return }
                self.model.bodyText = self.resultText
                self.model.hasResult = !self.resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                self.model.running = false
                self.status?.hide()
                self.outputTokens = await self.countTokens(self.resultText) ?? self.resultText.count / 4
                guard self.generationID == generationID else { return }
                self.updateMeter()
            } catch is CancellationError {
                guard self.generationID == generationID else { return }
                self.model.running = false
                self.status?.hide()
            } catch let error as AppError where error == .cancelled {
                guard self.generationID == generationID else { return }
                self.model.running = false
                self.status?.hide()
            } catch let error as AppError {
                guard self.generationID == generationID else { return }
                self.model.running = false
                self.model.banner = error
                self.status?.showError(error)
                self.report(.error(error))
            } catch {
                guard self.generationID == generationID else { return }
                self.model.running = false
                self.model.banner = .stalled
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
        model.setMeter(used: used, limit: info.contextSize, label: "\(info.variantName) · On-device")
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
}

@MainActor
@Observable
final class RewriteWindowModel {
    var instruction = ""
    var bodyText = ""
    var running = false
    var editable = true
    var hasResult = false
    var banner: AppError?
    var meterLabel = ""
    var meterUsed: Int?
    var meterLimit = 0
    var mode: RewriteKind?
    var focusToken = UUID()

    var onSubmit: ((String) -> Void)?
    var onPreset: ((RewriteKind) -> Void)?
    var onApply: (() -> Void)?
    var onCopy: (() -> Void)?
    var onRegenerate: (() -> Void)?
    var onBannerAction: ((AppError.Action) -> Void)?
    var onClose: (() -> Void)?

    var canSubmit: Bool {
        !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func submit() {
        let line = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        onSubmit?(line)
    }

    func setMeter(used: Int?, limit: Int, label: String) {
        meterUsed = used
        meterLimit = limit
        meterLabel = label
    }

    func bannerTitle(_ action: AppError.Action) -> String {
        switch action {
        case .openAccessibility, .openIntelligence: "Open Settings"
        case .retry: "Retry"
        case .copyResult: "Copy"
        }
    }
}

private struct RewriteView: View {
    @Bindable var model: RewriteWindowModel
    @FocusState private var instructionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            inputRow
            presetRow
            if let banner = model.banner {
                bannerRow(banner)
            }
            bodyPane
            footer
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 360)
        .onAppear { instructionFocused = true }
        .onChange(of: model.focusToken) { _, _ in instructionFocused = true }
        .background {
            Button("Close") { model.onClose?() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Tell Fixyy how to rewrite…", text: $model.instruction)
                .textFieldStyle(.roundedBorder)
                .focused($instructionFocused)
                .onSubmit { model.submit() }
            Button(action: { model.submit() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .disabled(!model.canSubmit || model.running)
            .help("Rewrite")
        }
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(RewriteKind.modes.enumerated()), id: \.element) { index, kind in
                let selected = model.mode == kind
                Button(kind.chipTitle) { model.onPreset?(kind) }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .tint(selected ? Color.accentColor : nil)
                    .frame(maxWidth: .infinity)
                    .disabled(model.running && !selected)
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }

    private func bannerRow(_ error: AppError) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(error.message)
                .font(.callout)
            Spacer(minLength: 8)
            if let action = error.action {
                Button(model.bannerTitle(action)) { model.onBannerAction?(action) }
            }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var bodyPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(model.bodyText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .id("body")
            }
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: model.bodyText) { _, _ in
                if model.running {
                    proxy.scrollTo("body", anchor: .bottom)
                }
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.meterLabel)
                    .foregroundStyle(.secondary)
                if let used = model.meterUsed {
                    Text("\(used.formatted()) / \(model.meterLimit.formatted())")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
            Spacer(minLength: 12)
            if model.running {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Regenerate") { model.onRegenerate?() }
                .disabled(model.running)
                .keyboardShortcut("r", modifiers: .command)
            Button("Copy") { model.onCopy?() }
                .disabled(!model.hasResult || model.running)
            if model.editable {
                Button("Apply") { model.onApply?() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.hasResult || model.running)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
