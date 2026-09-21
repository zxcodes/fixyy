import AppKit
import SwiftUI

@MainActor
public final class RewriteCardController {
    public var onDismiss: (() -> Void)?
    public var onJob: ((JobSummary) -> Void)?

    private var panel: NSPanel?
    private var hosting: NSHostingController<RewriteCardView>?
    private var model = RewriteCardModel()
    private var monitors: [Any] = []
    private let rewrite: RewriteService
    private let selection: SelectionHandling
    private let status: StatusItemController?
    private let info: ModelInfo
    private let countTokens: @MainActor (String) async -> Int?
    private var sourceText = ""
    private var promptTokens: Int?
    private var generateTask: Task<Void, Never>?
    private var jobStart: ContinuousClock.Instant?

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
        model.onAction = { [weak self] action in self?.perform(action) }
    }

    public var isVisible: Bool { panel?.isVisible == true }

    public func present(sourceText: String, editable: Bool, promptTokens: Int? = nil) {
        generateTask?.cancel()
        self.sourceText = sourceText
        self.promptTokens = promptTokens
        model.reset(source: sourceText, editable: editable, promptTokens: promptTokens)
        model.contextSize = info.contextSize
        model.modelLabel = "\(info.variantName) · On-device"

        let view = RewriteCardView(model: model)
        let hosting = NSHostingController(rootView: view)
        self.hosting = hosting

        let panel = makePanel()
        panel.contentViewController = hosting
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let height = min(520, screen.height * 0.6)
        let origin = SelectionAnchor.panelOrigin(width: 420, height: height)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: 420, height: height)), display: true)
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    public func presentError(_ error: AppError) {
        model.banner = error
        status?.showError(error)
        if error.opensAccessibilitySettings { SettingsLinks.openAccessibility() }
        if error.opensIntelligenceSettings { SettingsLinks.openIntelligence() }
    }

    public func cycleMode() {
        let modes = RewriteKind.modes
        let next: RewriteKind
        if let active = model.mode, let index = modes.firstIndex(of: active) {
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
        generateTask?.cancel()
        removeMonitors()
        panel?.orderOut(nil)
        onDismiss?()
    }

    enum CardAction {
        case run(RewriteKind)
        case custom(String)
        case regenerate
        case apply
        case copyResult
        case cycleView
        case bannerAction(AppError.Action)
        case close
    }

    private func perform(_ action: CardAction) {
        switch action {
        case .run(let kind): run(kind)
        case .custom(let line): run(.custom(line))
        case .regenerate: regenerate()
        case .apply: apply()
        case .copyResult: copyResult()
        case .cycleView: model.cycleView()
        case .bannerAction(let action):
            switch action {
            case .openAccessibility: SettingsLinks.openAccessibility()
            case .openIntelligence: SettingsLinks.openIntelligence()
            case .retry: retry()
            case .copyResult: copyResult()
            }
        case .close: dismiss()
        }
    }

    private func run(_ kind: RewriteKind, sampling: RewriteSampling = .automatic) {
        guard !sourceText.isEmpty else { return }
        generateTask?.cancel()
        model.banner = nil
        model.isRunning = true
        model.result = ""
        model.outputTokens = nil
        model.mode = kind
        status?.showWorking()
        jobStart = .now
        generateTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await partial in self.rewrite.stream(text: self.sourceText, kind: kind, sampling: sampling) {
                    self.model.result = partial
                }
                self.model.isRunning = false
                self.status?.hide()
                self.model.outputTokens = await self.countTokens(self.model.result) ?? self.model.result.count / 4
            } catch is CancellationError {
                self.model.isRunning = false
                self.status?.hide()
            } catch let error as AppError where error == .cancelled {
                self.model.isRunning = false
                self.status?.hide()
            } catch let error as AppError {
                self.model.isRunning = false
                self.model.banner = error
                self.status?.showError(error)
                self.report(.error(error))
            } catch {
                self.model.isRunning = false
                self.model.banner = .stalled
                self.status?.showError(.stalled)
                self.report(.error(.stalled))
            }
        }
    }

    private func regenerate() {
        let kind = model.mode ?? .clearer
        run(kind, sampling: .randomTop(50))
    }

    private func retry() {
        if let mode = model.mode {
            run(mode)
        }
    }

    private func apply() {
        let text = model.result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
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
        let text = model.result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        selection.leaveOnClipboard(text)
        status?.showSuccess("Copied")
        report(.copied)
        dismissKeepingStatus()
    }

    private func report(_ outcome: JobSummary.Outcome) {
        let latency = jobStart.map { ContinuousClock.now - $0 } ?? .zero
        onJob?(JobSummary(
            kind: .rewrite,
            promptTokens: promptTokens,
            outputTokens: model.outputTokens,
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
            switch event.keyCode {
            case 18, 19, 20, 21:
                let index = Int(event.keyCode - 18)
                let modes = RewriteKind.modes
                if index < modes.count { run(modes[index]) }
                return nil
            case 2:
                model.cycleView()
                return nil
            case 15:
                regenerate()
                return nil
            case 8:
                if fieldHasSelection() { return event }
                copyResult()
                return nil
            default:
                return event
            }
        }
        if event.keyCode == 36, !event.modifierFlags.contains(.command) {
            if fieldIsFirstResponder() { return event }
            if model.editable { apply() } else { copyResult() }
            return nil
        }
        return event
    }

    private func fieldIsFirstResponder() -> Bool {
        panel?.firstResponder is NSTextView
    }

    private func fieldHasSelection() -> Bool {
        guard let editor = panel?.firstResponder as? NSTextView else { return false }
        return editor.selectedRange().length > 0
    }

    private func removeMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    private func makePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
        panel.isMovableByWindowBackground = true
        self.panel = panel
        return panel
    }
}

@MainActor
@Observable
final class RewriteCardModel {
    enum ContentView: Int, CaseIterable {
        case original
        case result
        case changes

        var title: String {
            switch self {
            case .original: "Original"
            case .result: "Result"
            case .changes: "Changes"
            }
        }
    }

    var source = ""
    var result = ""
    var custom = ""
    var isRunning = false
    var banner: AppError?
    var editable = true
    var mode: RewriteKind?
    var contentView: ContentView = .result
    var promptTokens: Int?
    var outputTokens: Int?
    var contextSize = 4096
    var modelLabel = "On-device"
    var onAction: ((RewriteCardController.CardAction) -> Void)?

    func reset(source: String, editable: Bool, promptTokens: Int?) {
        self.source = source
        self.editable = editable
        self.promptTokens = promptTokens
        result = ""
        custom = ""
        isRunning = false
        banner = nil
        mode = nil
        contentView = .result
        outputTokens = nil
    }

    func cycleView() {
        let all = ContentView.allCases
        let index = all.firstIndex(of: contentView) ?? 0
        contentView = all[(index + 1) % all.count]
    }

    var usedTokens: Int? {
        guard promptTokens != nil || outputTokens != nil else { return nil }
        return (promptTokens ?? source.count / 4) + (outputTokens ?? 0)
    }
}

struct RewriteCardView: View {
    let model: RewriteCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            modePicker
            customField
            if let banner = model.banner {
                bannerView(banner)
            }
            bodyText
            footer
        }
        .padding(16)
        .frame(width: 420)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack {
            Text("Rewrite")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                model.onAction?(.close)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: Binding(
            get: { model.mode },
            set: { newValue in if let kind = newValue { model.onAction?(.run(kind)) } }
        )) {
            ForEach(RewriteKind.modes, id: \.self) { kind in
                Text(kind.chipTitle).tag(Optional(kind))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(model.isRunning)
    }

    private var customField: some View {
        TextField("Or tell it how…", text: Binding(
            get: { model.custom },
            set: { model.custom = $0 }
        ))
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 13))
        .onSubmit {
            let line = model.custom.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return }
            model.onAction?(.custom(line))
        }
        .disabled(model.isRunning)
    }

    private func bannerView(_ error: AppError) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(error.message)
                .font(.system(size: 12))
            Spacer()
            if let action = error.action {
                Button(actionLabel(action)) { model.onAction?(.bannerAction(action)) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func actionLabel(_ action: AppError.Action) -> String {
        switch action {
        case .openAccessibility, .openIntelligence: "Open Settings"
        case .retry: "Retry"
        case .copyResult: "Copy"
        }
    }

    private var bodyText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("View", selection: Binding(
                get: { model.contentView },
                set: { model.contentView = $0 }
            )) {
                ForEach(RewriteCardModel.ContentView.allCases, id: \.self) { view in
                    Text(view.title).tag(view)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 220)

            ScrollView {
                Group {
                    if model.contentView == .changes {
                        changesText
                    } else {
                        Text(displayText)
                    }
                }
                .font(.system(size: 14))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .foregroundStyle(isPlaceholder ? Color.secondary : Color.primary)
                .opacity(model.isRunning && model.result.isEmpty ? 0.55 : 1)
            }
            .frame(minHeight: 120, maxHeight: .infinity)
        }
    }

    private var displayText: String {
        switch model.contentView {
        case .original:
            return model.source.isEmpty ? "Select some text, then pick a rewrite." : model.source
        case .result:
            if !model.result.isEmpty { return model.result }
            return model.source.isEmpty ? "Select some text, then pick a rewrite." : model.source
        case .changes:
            return model.result.isEmpty ? "Run a rewrite to see changes." : ""
        }
    }

    private var isPlaceholder: Bool {
        model.contentView != .changes && model.result.isEmpty
    }

    private var changesText: Text {
        Text(FixHUDView.diffAttributedString(TextDiff.segments(from: model.source, to: model.result)))
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.modelLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let used = model.usedTokens {
                    Text(meter(used: used, limit: model.contextSize))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.isRunning {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Regenerate") { model.onAction?(.regenerate) }
                .disabled(model.mode == nil || model.isRunning)
            if model.editable {
                Button("Copy") { model.onAction?(.copyResult) }
                    .buttonStyle(.bordered)
                    .disabled(model.result.isEmpty || model.isRunning)
                Button("Apply") { model.onAction?(.apply) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.result.isEmpty || model.isRunning)
            } else {
                Button("Copy") { model.onAction?(.copyResult) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.result.isEmpty || model.isRunning)
            }
        }
    }

    private func meter(used: Int, limit: Int) -> String {
        let filled = max(0, min(5, Int((Double(used) / Double(max(1, limit)) * 5).rounded())))
        let blocks = String(repeating: "▮", count: filled) + String(repeating: "▯", count: 5 - filled)
        return "\(blocks) \(used.formatted()) / \(limit.formatted())"
    }
}
