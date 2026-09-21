import AppKit

@MainActor
public final class StatusItemController: NSObject {
    public var onFix: (() -> Void)?
    public var onRewrite: (() -> Void)?
    public var onSettings: (() -> Void)?
    public var onQuit: (() -> Void)?
    public var lastJobProvider: (() -> JobSummary?)?

    private let item: NSStatusItem
    private let info: ModelInfo
    private let spinner = NSProgressIndicator()
    private let spinnerSlot = StatusItemController.makeSpinnerSlot()
    private var revertWork: DispatchWorkItem?
    private let idleImage = StatusIcon.mark()
    private let menu = NSMenu()
    private var appBeforeMenu: NSRunningApplication?

    public init(info: ModelInfo) {
        self.info = info
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configure()
    }

    public func showWorking() {
        showWorking("Fixing")
    }

    public func showWorking(_ message: String) {
        revertWork?.cancel()
        appear(image: spinnerSlot, title: message, spinning: true, tooltip: "Fixyy — \(message)")
    }

    public func showSuccess(_ message: String) {
        flash(image: StatusIcon.check(), title: message, tooltip: "Fixyy — \(message)", seconds: 1.6)
    }

    public func showFixed() {
        showSuccess("Fixed")
    }

    public func showUnchanged() {
        showSuccess("Looks good")
    }

    public func showCancelled() {
        hide()
    }

    public func showError(_ error: AppError, retry: (@MainActor () -> Void)? = nil) {
        _ = retry
        flash(image: StatusIcon.error(), title: nil, tooltip: error.message, seconds: 1.6)
    }

    public func hide() {
        revertWork?.cancel()
        restoreIdle()
    }

    private func configure() {
        guard let button = item.button else { return }
        button.image = idleImage
        button.imagePosition = .imageOnly
        button.toolTip = "Fixyy"

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 6),
            spinner.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),
        ])

        menu.delegate = self
        item.menu = menu
        buildMenu()
    }

    private func buildMenu() {
        menu.removeAllItems()
        menu.addItem(statusRow())
        menu.addItem(.separator())
        menu.addItem(item("Fix Selection", shortcut: Prefs.shared.fixShortcut, action: #selector(menuFix)))
        menu.addItem(item("Rewrite Selection", shortcut: Prefs.shared.rewriteShortcut, action: #selector(menuRewrite)))
        if let job = lastJobProvider?() {
            menu.addItem(.separator())
            let last = NSMenuItem(title: "Last: \(job.menuLabel)", action: nil, keyEquivalent: "")
            last.isEnabled = false
            menu.addItem(last)
        }
        menu.addItem(.separator())
        menu.addItem(item("Settings", key: ",", modifiers: [.command], action: #selector(menuSettings)))
        menu.addItem(item("Quit Fixyy", key: "q", modifiers: [.command], action: #selector(menuQuit)))
    }

    private func captureAppBeforeMenu(_ app: NSRunningApplication?) {
        appBeforeMenu = app?.processIdentifier != ProcessInfo.processInfo.processIdentifier ? app : nil
    }

    private func statusRow() -> NSMenuItem {
        let available = info.availability == .available
        let dot = NSMutableAttributedString(
            string: "● ",
            attributes: [.foregroundColor: available ? NSColor.systemGreen : NSColor.systemRed]
        )
        dot.append(NSAttributedString(
            string: info.statusLine,
            attributes: [.foregroundColor: NSColor.labelColor]
        ))
        let row = NSMenuItem(title: "", action: available ? nil : #selector(menuStatusDetail), keyEquivalent: "")
        row.attributedTitle = dot
        row.target = self
        row.isEnabled = !available
        return row
    }

    private func item(_ title: String, shortcut: KeyShortcut, action: Selector) -> NSMenuItem {
        item(title, key: shortcut.menuKeyEquivalent, modifiers: shortcut.menuModifierMask, action: action)
    }

    private func item(_ title: String, key: String, modifiers: NSEvent.ModifierFlags, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    @objc private func menuFix() {
        appBeforeMenu?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.onFix?()
        }
    }

    @objc private func menuRewrite() {
        appBeforeMenu?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.onRewrite?()
        }
    }

    @objc private func menuSettings() {
        onSettings?()
    }

    @objc private func menuQuit() {
        onQuit?()
    }

    @objc private func menuStatusDetail() {
        switch info.availability {
        case .intelligenceOff, .modelNotReady:
            SettingsLinks.openIntelligence()
        default:
            onSettings?()
        }
    }

    private func flash(image: NSImage, title: String?, tooltip: String, seconds: TimeInterval) {
        revertWork?.cancel()
        appear(image: image, title: title, spinning: false, tooltip: tooltip)
        let work = DispatchWorkItem { [weak self] in
            self?.restoreIdle()
        }
        revertWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func restoreIdle() {
        appear(image: idleImage, title: nil, spinning: false, tooltip: "Fixyy")
    }

    private func appear(image: NSImage?, title: String?, spinning: Bool, tooltip: String) {
        guard let button = item.button else { return }
        spinner.isHidden = !spinning
        if spinning {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
        button.image = image ?? idleImage
        if let title, !title.isEmpty {
            item.length = NSStatusItem.variableLength
            button.title = title
            button.font = NSFont.menuBarFont(ofSize: 13)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
            item.length = NSStatusItem.squareLength
        }
        button.toolTip = tooltip
    }

    private static func makeSpinnerSlot() -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in true }
        image.isTemplate = true
        return image
    }
}

extension StatusItemController: HUDPresenting, NSMenuDelegate {
    nonisolated public func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let front = NSWorkspace.shared.frontmostApplication
            self.captureAppBeforeMenu(front)
            self.buildMenu()
        }
    }
}
