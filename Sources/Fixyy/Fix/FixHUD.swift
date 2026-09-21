import AppKit
import SwiftUI

@MainActor
public final class FixHUD: HUDPresenting {
    private var panel: NSPanel?
    private var hosting: NSHostingController<FixHUDView>?
    private let model = FixHUDModel()
    private let status: StatusItemController?
    private var showWork: DispatchWorkItem?
    private var dismissWork: DispatchWorkItem?
    private var monitors: [Any] = []

    public init(status: StatusItemController? = nil) {
        self.status = status
        model.onHover = { [weak self] inside in self?.hover(inside) }
    }

    public var undoVisible: Bool {
        guard panel?.isVisible == true, case .fixed = model.state else { return false }
        return true
    }

    public func showWorking() {
        cancelTimers()
        status?.showWorking()
        let work = DispatchWorkItem { [weak self] in
            self?.present(.working)
        }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    public func showFixed(diff: [TextDiff.Segment], undo: @escaping @MainActor () -> Void) {
        cancelTimers()
        status?.showSuccess("Fixed")
        model.undo = undo
        present(.fixed(diff))
        scheduleDismiss(after: 3.5)
    }

    public func showUnchanged() {
        cancelTimers()
        status?.showSuccess("Looks good")
        present(.unchanged)
        scheduleDismiss(after: 1.2)
    }

    public func showCancelled() {
        cancelTimers()
        status?.hide()
        present(.cancelled)
        scheduleDismiss(after: 0.8)
    }

    public func showError(_ error: AppError, retry: (@MainActor () -> Void)? = nil) {
        cancelTimers()
        status?.showError(error)
        model.retry = retry
        present(.failure(error))
        scheduleDismiss(after: 4)
    }

    public func hide() {
        cancelTimers()
        removeMonitors()
        panel?.orderOut(nil)
        model.state = .idle
        model.undo = nil
        model.retry = nil
        status?.hide()
    }

    private func present(_ state: FixHUDModel.State) {
        switch state {
        case .fixed, .failure:
            break
        default:
            model.undo = nil
            model.retry = nil
        }
        model.state = state
        if hosting == nil {
            hosting = NSHostingController(rootView: FixHUDView(model: model))
        }
        let panel = makePanel()
        if panel.contentViewController == nil {
            panel.contentViewController = hosting
        }
        let size = panel.contentView?.fittingSize ?? NSSize(width: 260, height: 64)
        let width = max(180, min(size.width, 480))
        let height = max(44, min(size.height, 200))
        let origin = SelectionAnchor.panelOrigin(width: width, height: height)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
        panel.orderFrontRegardless()
        installMonitors()
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func hover(_ inside: Bool) {
        guard case .fixed = model.state, panel?.isVisible == true else { return }
        if inside {
            dismissWork?.cancel()
            dismissWork = nil
        } else if dismissWork == nil {
            scheduleDismiss(after: 3.5)
        }
    }

    private func cancelTimers() {
        showWork?.cancel()
        showWork = nil
        dismissWork?.cancel()
        dismissWork = nil
    }

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        if let esc = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == 53 {
                DispatchQueue.main.async { self?.hide() }
            }
        }) {
            monitors.append(esc)
        }
    }

    private func removeMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    private func makePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 64),
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
        self.panel = panel
        return panel
    }
}

@MainActor
@Observable
final class FixHUDModel {
    enum State {
        case idle
        case working
        case fixed([TextDiff.Segment])
        case unchanged
        case cancelled
        case failure(AppError)
    }

    var state: State = .idle
    var undo: (@MainActor () -> Void)?
    var retry: (@MainActor () -> Void)?
    var onHover: ((Bool) -> Void)?
}

struct FixHUDView: View {
    let model: FixHUDModel

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onHover { model.onHover?($0) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .working:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Fixing")
                    .font(.system(size: 13))
            }
        case .fixed(let segments):
            HStack(alignment: .top, spacing: 12) {
                diffText(segments)
                    .font(.system(size: 13))
                    .lineLimit(3)
                    .truncationMode(.tail)
                Button {
                    model.undo?()
                } label: {
                    HStack(spacing: 4) {
                        Text("Undo")
                        Text("⌘Z")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        case .unchanged:
            Label("Looks good", systemImage: "checkmark.seal")
                .font(.system(size: 13))
        case .cancelled:
            Text("Cancelled")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        case .failure(let error):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error.message)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                if let action = error.action, action != .retry || model.retry != nil {
                    Button(actionTitle(error)) { runAction(error) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    private func diffText(_ segments: [TextDiff.Segment]) -> Text {
        Text(Self.diffAttributedString(segments))
    }

    static func diffAttributedString(_ segments: [TextDiff.Segment]) -> AttributedString {
        var result = AttributedString()
        for segment in segments {
            var part = AttributedString(" " + segment.text)
            switch segment {
            case .equal:
                break
            case .inserted:
                part.foregroundColor = .green
            case .removed:
                part.foregroundColor = .red
                part.strikethroughStyle = .single
            }
            result += part
        }
        return result
    }

    private func actionTitle(_ error: AppError) -> String {
        switch error.action {
        case .openAccessibility: "Open Settings"
        case .openIntelligence: "Open Settings"
        case .retry: "Retry"
        case .copyResult: "Copy"
        case nil: ""
        }
    }

    private func runAction(_ error: AppError) {
        switch error.action {
        case .openAccessibility: SettingsLinks.openAccessibility()
        case .openIntelligence: SettingsLinks.openIntelligence()
        case .retry: model.retry?()
        default: break
        }
    }
}
