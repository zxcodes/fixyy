import Foundation
import ServiceManagement

@MainActor
public final class Prefs {
    public static let shared = Prefs()

    public var onShortcutsChange: (() -> Void)?

    private let defaults: UserDefaults
    private let styleKey = "styleNote"
    private let onboardedKey = "hasCompletedOnboarding"
    private let shortcutsKey = "shortcuts"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var styleNote: String {
        get { defaults.string(forKey: styleKey) ?? "" }
        set {
            let clipped = String(newValue.prefix(styleNoteCharacterLimit))
            defaults.set(clipped, forKey: styleKey)
        }
    }

    public var fixShortcut: KeyShortcut {
        get { shortcut(for: "fix") ?? .fixDefault }
        set { setShortcut(newValue, for: "fix") }
    }

    public var rewriteShortcut: KeyShortcut {
        get { shortcut(for: "rewrite") ?? .rewriteDefault }
        set { setShortcut(newValue, for: "rewrite") }
    }

    private func shortcut(for action: String) -> KeyShortcut? {
        guard let data = defaults.data(forKey: shortcutsKey),
              let map = try? JSONDecoder().decode([String: KeyShortcut].self, from: data)
        else { return nil }
        return map[action]
    }

    private func setShortcut(_ shortcut: KeyShortcut, for action: String) {
        var map: [String: KeyShortcut] = [:]
        if let data = defaults.data(forKey: shortcutsKey),
           let decoded = try? JSONDecoder().decode([String: KeyShortcut].self, from: data) {
            map = decoded
        }
        map[action] = shortcut
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: shortcutsKey)
        }
        onShortcutsChange?()
    }

    public var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: onboardedKey) }
        set { defaults.set(newValue, forKey: onboardedKey) }
    }

    public var launchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Login-item registration needs a bundled app; ignore in `swift run`.
        }
    }
}
