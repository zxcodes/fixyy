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
        revertWork?.cancel()
        item.button?.toolTip = "Fixyy — working"
        setSpinner(true)
    }

    public func showSuccess(_ message: String) {
        flash(image: StatusIcon.check(), tooltip: "Fixyy — \(message)", seconds: 1.2)
    }

    public func showError(_ error: AppError) {
        flash(image: StatusIcon.error(), tooltip: error.message, seconds: 1.2)
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
            spinner.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])

        menu.delegate = self
        item.menu = menu
        buildMenu()
    }

    private func buildMenu() {
        menu.removeAllItems()
        menu.addItem(statusRow())
        menu.addItem(.separator())
        menu.addItem(actionItem("Fix Selection", shortcut: Prefs.shared.fixShortcut.display, action: #selector(menuFix)))
        menu.addItem(actionItem("Rewrite Selection…", shortcut: Prefs.shared.rewriteShortcut.display, action: #selector(menuRewrite)))
        if let job = lastJobProvider?() {
            menu.addItem(.separator())
            let last = NSMenuItem(title: "Last: \(job.menuLabel)", action: nil, keyEquivalent: "")
            last.isEnabled = false
            menu.addItem(last)
        }
        menu.addItem(.separator())
        menu.addItem(commandItem("Settings…", key: ",", action: #selector(menuSettings)))
        menu.addItem(commandItem("Quit Fixyy", key: "q", action: #selector(menuQuit)))
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

    private func commandItem(_ title: String, key: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.command]
        item.target = self
        return item
    }

    private func actionItem(_ title: String, shortcut: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: "\(title)\t\(shortcut)", action: action, keyEquivalent: "")
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

    private func setSpinner(_ on: Bool) {
        guard let button = item.button else { return }
        if on {
            button.image = nil
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
            if button.image == nil {
                button.image = idleImage
            }
        }
    }

    private func flash(image: NSImage, tooltip: String, seconds: TimeInterval) {
        revertWork?.cancel()
        setSpinner(false)
        item.button?.image = image
        item.button?.toolTip = tooltip
        let work = DispatchWorkItem { [weak self] in
            self?.restoreIdle()
        }
        revertWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func restoreIdle() {
        setSpinner(false)
        item.button?.image = idleImage
        item.button?.toolTip = "Fixyy"
    }
}

extension StatusItemController: NSMenuDelegate {
    nonisolated public func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let front = NSWorkspace.shared.frontmostApplication
            self.captureAppBeforeMenu(front)
            self.buildMenu()
        }
    }
}
