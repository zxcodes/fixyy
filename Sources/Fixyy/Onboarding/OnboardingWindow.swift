import AppKit
import SwiftUI

@MainActor
public final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model = OnboardingModel()
    private let prefs: Prefs
    private let selection: SelectionHandling
    private let info: ModelInfo
    private var pollTimer: Timer?

    public init(prefs: Prefs, selection: SelectionHandling, info: ModelInfo) {
        self.prefs = prefs
        self.selection = selection
        self.info = info
    }

    public func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let model = self.model
        model.selection = selection
        model.info = info
        model.onClose = { [weak self] in self?.close() }
        let hosting = NSHostingController(rootView: OnboardingView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Fixyy"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 420, height: 340))
        window.center()
        window.delegate = self
        self.window = window
        startPolling()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    public func noteFixCompleted() {
        model.fixCompleted = true
    }

    nonisolated public func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { self.finish() }
    }

    private func close() {
        finish()
        window?.close()
    }

    private func finish() {
        prefs.hasCompletedOnboarding = true
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.model.step == .accessibility else { return }
                if self.selection.isTrusted {
                    self.model.step = .intelligence
                }
            }
        }
    }
}

@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int {
        case accessibility
        case intelligence
        case tryIt
    }

    var step: Step = .accessibility
    var fixCompleted = false
    var tryText = "their going too the store tomorow, and i think its gonna rain"
    var selection: SelectionHandling?
    var info: ModelInfo?
    var onClose: (() -> Void)?

    func skip() {
        onClose?()
    }

    func next() {
        switch step {
        case .accessibility: step = .intelligence
        case .intelligence: step = .tryIt
        case .tryIt: onClose?()
        }
    }
}

struct OnboardingView: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 420, height: 340)
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .accessibility: accessibilityStep
        case .intelligence: intelligenceStep
        case .tryIt: tryItStep
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.raised")
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)
            Text("Accessibility")
                .font(.headline)
            Text("Fixyy reads your selection and pastes the fix back. That needs Accessibility permission.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Open System Settings") {
                model.selection?.requestTrustPrompt()
            }
            .controlSize(.large)
            Text("This step advances on its own once granted.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var intelligenceStep: some View {
        VStack(spacing: 12) {
            Image(systemName: "apple.intelligence")
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)
            Text("Apple Intelligence")
                .font(.headline)
            Text(intelligenceDetail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if model.info?.availability == .intelligenceOff {
                Button("Open System Settings") { SettingsLinks.openIntelligence() }
                    .controlSize(.large)
            }
        }
    }

    private var intelligenceDetail: String {
        switch model.info?.availability {
        case .available:
            "Apple Intelligence is on. Fixyy uses the on-device model — nothing leaves this Mac."
        case .modelNotReady:
            "Apple’s on-device model is still downloading. Fixyy will work once it finishes."
        case .intelligenceOff:
            "Apple Intelligence is off. Turn it on to use Fixyy."
        case .deviceNotEligible:
            "This Mac can’t run the on-device model."
        default:
            "The on-device model isn’t available."
        }
    }

    private var tryItStep: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.cursor")
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)
            Text("Try it")
                .font(.headline)
            TextField("", text: Binding(
                get: { model.tryText },
                set: { model.tryText = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 320)
            if model.fixCompleted {
                Text("That’s it.")
                    .font(.system(size: 13, weight: .medium))
                Button("Done") { model.onClose?() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            } else {
                Text("Press ⌘⇧G with this text selected")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip") { model.skip() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == model.step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            if model.step != .tryIt || !model.fixCompleted {
                Button("Next") { model.next() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }
}
