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
        let budget = TokenBudget(contextSize: info.contextSize) { [weak model] text in
            guard let model else { return nil }
            return await model.tokenCount(instructions: "", prompt: text)
        }
        let fix = FixService(model: model, selection: selection, prefs: prefs, hud: status, budget: budget)
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
        card.onSettings = { [weak settings] in settings?.show() }
        installMainMenu()
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
        model.prewarm()

        if !prefs.hasCompletedOnboarding || !selection.isTrusted {
            onboarding.show()
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: "Fixyy")
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Fixyy", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettings() {
        settings?.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func registerHotkeys() {
        guard let prefs, let coordinator else { return }
        HotKeyCenter.shared.unregisterAll()
        var conflicts: [String: String] = [:]
        let fix = prefs.fixShortcut
        let rewrite = prefs.rewriteShortcut
        if fix == rewrite {
            conflicts["fix"] = "Same as Rewrite"
            conflicts["rewrite"] = "Same as Fix"
            _ = HotKeyCenter.shared.register(keyCode: fix.keyCode, modifiers: fix.modifiers) {
                coordinator.handleFix()
            }
        } else {
            if !HotKeyCenter.shared.register(keyCode: fix.keyCode, modifiers: fix.modifiers, action: {
                coordinator.handleFix()
            }) {
                conflicts["fix"] = "In use by another app"
            }
            if !HotKeyCenter.shared.register(keyCode: rewrite.keyCode, modifiers: rewrite.modifiers, action: {
                coordinator.handleRewrite()
            }) {
                conflicts["rewrite"] = "In use by another app"
            }
        }
        settings?.updateShortcutConflicts(conflicts)
    }
}
