import AppKit
import ServiceManagement
import SwiftUI

enum SettingsChrome {
    static let radius: CGFloat = 6
}

@MainActor
public final class SettingsWindowController {
    private var window: NSWindow?
    private var model: SettingsModel?
    private var pendingConflicts: [String: String] = [:]
    private let prefs: Prefs
    private let language: LanguageGenerating
    private let selection: SelectionHandling
    private let info: ModelInfo
    private let lastJob: () -> JobSummary?

    public init(
        prefs: Prefs,
        model: LanguageGenerating,
        selection: SelectionHandling,
        info: ModelInfo,
        lastJob: @escaping () -> JobSummary? = { nil }
    ) {
        self.prefs = prefs
        self.language = model
        self.selection = selection
        self.info = info
        self.lastJob = lastJob
    }

    public func show() {
        if let window {
            model?.refreshAccessibility()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let model = SettingsModel(prefs: prefs, model: language, selection: selection, info: info, lastJob: lastJob)
        model.conflicts = pendingConflicts
        self.model = model
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Fixyy Settings"
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 500, height: 540))
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    public func updateShortcutConflicts(_ conflicts: [String: String]) {
        pendingConflicts = conflicts
        model?.conflicts = conflicts
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .about: "About"
        }
    }
}

@MainActor
@Observable
final class SettingsModel {
    var styleNote: String
    var launchesAtLogin: Bool
    var accessibilityGranted: Bool
    var conflicts: [String: String] = [:]
    var selfTest: SelfTestState = .idle
    var pane: SettingsPane = .general
    var paneHover: SettingsPane?

    let prefs: Prefs
    let language: LanguageGenerating
    let info: ModelInfo
    private let selection: SelectionHandling
    private let lastJobProvider: () -> JobSummary?

    enum SelfTestState {
        case idle
        case running
        case done(result: String, latency: TimeInterval, tokens: Int?)
        case failed(String)
    }

    init(prefs: Prefs, model: LanguageGenerating, selection: SelectionHandling, info: ModelInfo, lastJob: @escaping () -> JobSummary?) {
        self.prefs = prefs
        self.language = model
        self.selection = selection
        self.info = info
        self.lastJobProvider = lastJob
        self.styleNote = prefs.styleNote
        self.launchesAtLogin = prefs.launchesAtLogin
        self.accessibilityGranted = selection.isTrusted
    }

    var styleCountLabel: String {
        "\(styleNote.count) / \(styleNoteCharacterLimit)"
    }

    var lastJob: JobSummary? { lastJobProvider() }

    var fixShortcut: KeyShortcut { prefs.fixShortcut }
    var rewriteShortcut: KeyShortcut { prefs.rewriteShortcut }

    func persistStyle() {
        if styleNote.count > styleNoteCharacterLimit {
            styleNote = String(styleNote.prefix(styleNoteCharacterLimit))
        }
        prefs.styleNote = styleNote
    }

    func insertStyleExample(_ example: String) {
        styleNote = styleNote.isEmpty ? example : styleNote + " " + example
        persistStyle()
    }

    func toggleLogin() {
        prefs.setLaunchesAtLogin(!launchesAtLogin)
        launchesAtLogin = prefs.launchesAtLogin
    }

    func refreshAccessibility() {
        accessibilityGranted = selection.isTrusted
    }

    func openAccessibility() {
        selection.requestTrustPrompt()
        refreshAccessibility()
    }

    func openIntelligence() {
        SettingsLinks.openIntelligence()
    }

    func setShortcut(_ shortcut: KeyShortcut?, action: String) {
        let value = shortcut ?? (action == "fix" ? .fixDefault : .rewriteDefault)
        if action == "fix" {
            prefs.fixShortcut = value
        } else {
            prefs.rewriteShortcut = value
        }
    }

    func conflict(for action: String) -> String? {
        conflicts[action]
    }

    func runSelfTest() {
        selfTest = .running
        let sentence = "their going too the store tomorow, and i think its gonna rain"
        Task { [weak self] in
            guard let self else { return }
            let start = ContinuousClock.now
            do {
                let result = try await self.language.fixGrammar(text: sentence, styleNote: "")
                let latency = ContinuousClock.now - start
                let tokens = await self.language.tokenCount(instructions: "", prompt: sentence)
                self.selfTest = .done(
                    result: result.text,
                    latency: TimeInterval(latency.components.seconds) + TimeInterval(latency.components.attoseconds) / 1e18,
                    tokens: tokens
                )
            } catch let error as AppError {
                self.selfTest = .failed(error.message)
            } catch {
                self.selfTest = .failed(AppError.stalled.message)
            }
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }
}

struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Group {
            switch model.pane {
            case .general: GeneralTab(model: model)
            case .about: AboutTab(model: model)
            }
        }
        .frame(width: 500)
        .toolbar {
            ToolbarItem(placement: .principal) {
                SettingsPanePicker(model: model)
            }
        }
    }
}

private struct SettingsPanePicker: View {
    @Bindable var model: SettingsModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SettingsPane.allCases) { pane in
                paneButton(pane)
            }
        }
        .padding(3)
        .frame(width: 186)
        .background(Color.primary.opacity(0.08), in: Capsule())
        .animation(.easeInOut(duration: 0.15), value: model.pane)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
    }

    private func paneButton(_ pane: SettingsPane) -> some View {
        let selected = model.pane == pane
        return Button {
            model.pane = pane
        } label: {
            Text(pane.title)
                .font(.system(size: 13, weight: selected ? .medium : .regular))
                .frame(maxWidth: .infinity, minHeight: 22)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background { knob(selected: selected, hovering: model.paneHover == pane) }
        .onHover { inside in
            if inside {
                model.paneHover = pane
            } else if model.paneHover == pane {
                model.paneHover = nil
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func knob(selected: Bool, hovering: Bool) -> some View {
        if selected {
            Capsule().fill(Color(nsColor: .controlColor))
        } else if hovering {
            Capsule().fill(Color.primary.opacity(0.08))
        }
    }
}

private struct GeneralTab: View {
    let model: SettingsModel

    private let examples = [
        "Keep contractions.",
        "British English, no em dashes.",
        "Match Slack tone — casual is fine.",
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { _ in model.toggleLogin() }
                ))
            }
            Section {
                permissionRow(
                    "Accessibility",
                    status: model.accessibilityGranted ? "Granted" : "Not granted",
                    ok: model.accessibilityGranted,
                    action: model.openAccessibility
                )
                permissionRow(
                    "Apple Intelligence",
                    status: model.info.availability.settingsLabel,
                    ok: model.info.availability == .available,
                    action: model.openIntelligence
                )
            }
            Section("Shortcuts") {
                shortcutRow("Fix grammar", shortcut: model.fixShortcut, action: "fix")
                shortcutRow("Rewrite", shortcut: model.rewriteShortcut, action: "rewrite")
            }
            Section("Style") {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack(alignment: .bottomTrailing) {
                        TextEditor(text: Binding(
                            get: { model.styleNote },
                            set: { model.styleNote = $0; model.persistStyle() }
                        ))
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 88, maxHeight: 120)
                        Text(model.styleCountLabel)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    .padding(6)
                    .background(
                        Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: SettingsChrome.radius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: SettingsChrome.radius, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
                    )

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(examples, id: \.self) { example in
                            Button(example) { model.insertStyleExample(example) }
                                .buttonStyle(SettingsChipStyle())
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
    }

    private func permissionRow(_ title: String, status: String, ok: Bool, action: @escaping () -> Void) -> some View {
        LabeledContent {
            Button("Open…", action: action)
        } label: {
            Text(title)
            Text(status)
                .foregroundStyle(ok ? Color.secondary : Color.red)
        }
    }

    private func shortcutRow(_ title: String, shortcut: KeyShortcut, action: String) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 4) {
                ShortcutRecorder(
                    shortcut: shortcut,
                    onCommit: { model.setShortcut($0, action: action) }
                )
                .frame(width: 128, height: 24)
                if let message = model.conflict(for: action) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

private struct AboutTab: View {
    let model: SettingsModel

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                    Text("Fixyy")
                        .font(.headline)
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .foregroundStyle(.secondary)
                    Text("On-device only. Nothing leaves this Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section("Model") {
                LabeledContent("Variant", value: model.info.variantName)
                LabeledContent("Availability", value: model.info.availability.settingsLabel)
                LabeledContent("Context size", value: "\(model.info.contextSize.formatted()) tokens")
                LabeledContent("Current locale", value: model.info.supportsCurrentLocale ? "Supported" : "Not supported")
                LabeledContent("Guardrails", value: "Content transformations")
                if !model.info.capabilities.isEmpty {
                    LabeledContent("Capabilities", value: model.info.capabilities.joined(separator: ", "))
                }
            }
            if let job = model.lastJob {
                Section("Last job") {
                    LabeledContent("Result", value: job.menuLabel)
                }
            }
            Section {
                Button("Run self-test") { model.runSelfTest() }
                    .disabled(isRunning)
                switch model.selfTest {
                case .idle:
                    EmptyView()
                case .running:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Testing the on-device model…")
                            .foregroundStyle(.secondary)
                    }
                case .done(let result, let latency, let tokens):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                Color(nsColor: .textBackgroundColor),
                                in: RoundedRectangle(cornerRadius: SettingsChrome.radius, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: SettingsChrome.radius, style: .continuous)
                                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
                            )
                        Text("\(String(format: "%.1f", latency)) s\(tokens.map { " · \($0.formatted()) tok" } ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .failed(let message):
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Button("Quit Fixyy", role: .destructive) { model.quit() }
            }
        }
        .formStyle(.grouped)
    }

    private var isRunning: Bool {
        if case .running = model.selfTest { return true }
        return false
    }
}

private struct SettingsChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: SettingsChrome.radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsChrome.radius, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
