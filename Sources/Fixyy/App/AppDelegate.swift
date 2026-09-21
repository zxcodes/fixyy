import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: JobCoordinator?
    private var settings: SettingsWindowController?
    private var onboarding: OnboardingWindowController?
    private var prefs: Prefs?
    private var status: StatusItemController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = Prefs.shared
        self.prefs = prefs
        let model = ModelClient()
        let info = model.info
        let selection = SelectionIO()
        let status = StatusItemController(info: info)
        self.status = status
        let hud = FixHUD(status: status)
        let budget = TokenBudget(contextSize: info.contextSize) { [weak model] text in
            guard let model else { return nil }
            return await model.tokenCount(instructions: "", prompt: text)
        }
        let fix = FixService(model: model, selection: selection, prefs: prefs, hud: hud, budget: budget)
        let rewrite = RewriteService(model: model, prefs: prefs)
        let card = RewriteCardController(
            rewrite: rewrite,
            selection: selection,
            status: status,
            info: info
        ) { [weak model] text in
            guard let model else { return nil }
            return await model.tokenCount(instructions: "", prompt: text)
        }
        let coordinator = JobCoordinator(
            fix: fix,
            rewrite: rewrite,
            selection: selection,
            model: model,
            card: card,
            budget: budget
        )
        self.coordinator = coordinator
        fix.onJob = { [weak coordinator] job in coordinator?.record(job) }
        card.onJob = { [weak coordinator] job in coordinator?.record(job) }
        let settings = SettingsWindowController(
            prefs: prefs,
            model: model,
            selection: selection,
            info: info
        ) { [weak coordinator] in coordinator?.lastJob }
        self.settings = settings
        let onboarding = OnboardingWindowController(prefs: prefs, selection: selection, info: info)
        self.onboarding = onboarding
        coordinator.onJobCompleted = { [weak onboarding] job in
            if job.kind == .fix, job.outcome == .fixed {
                onboarding?.noteFixCompleted()
            }
        }

        status.onFix = { [weak coordinator] in coordinator?.handleFix() }
        status.onRewrite = { [weak coordinator] in coordinator?.handleRewrite() }
        status.onSettings = { [weak settings] in settings?.show() }
        status.onQuit = { NSApp.terminate(nil) }
        status.lastJobProvider = { [weak coordinator] in coordinator?.lastJob }

        prefs.onShortcutsChange = { [weak self] in
            self?.registerHotkeys()
        }
        registerHotkeys()

        if !prefs.hasCompletedOnboarding || !selection.isTrusted {
            onboarding.show()
        }
    }

    private func registerHotkeys() {
        guard let prefs, let coordinator else { return }
        HotKeyCenter.shared.unregisterAll()
        var conflicts: [String: Bool] = [:]
        let fix = prefs.fixShortcut
        conflicts["fix"] = !HotKeyCenter.shared.register(keyCode: fix.keyCode, modifiers: fix.modifiers) {
            coordinator.handleFix()
        }
        let rewrite = prefs.rewriteShortcut
        conflicts["rewrite"] = !HotKeyCenter.shared.register(keyCode: rewrite.keyCode, modifiers: rewrite.modifiers) {
            coordinator.handleRewrite()
        }
        settings?.updateShortcutConflicts(conflicts)
    }
}
