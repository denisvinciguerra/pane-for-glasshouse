import AppKit
import ServiceManagement
import SwiftUI

/// The language the app was asked to speak: stored in `AppleLanguages` of the app's own defaults
/// domain, which macOS reads at launch.
enum LanguageChoice: String, CaseIterable {
    case system, en, fr

    /// What `AppleLanguages` held when the app started.
    static let atLaunch = LanguageChoice.current()

    /// Read from the app's own domain only (the global one holds the system's list).
    static func current(_ defaults: UserDefaults = .standard) -> LanguageChoice {
        guard let id = Bundle.main.bundleIdentifier,
              let first = (defaults.persistentDomain(forName: id)?["AppleLanguages"] as? [String])?.first
        else { return .system }
        if first == "en" || first.hasPrefix("en-") { return .en }
        if first == "fr" || first.hasPrefix("fr-") { return .fr }
        return .system
    }

    /// System removes the key; the others write it.
    func apply(_ defaults: UserDefaults = .standard) {
        if self == .system {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .en: "English"
        case .fr: "Français"
        }
    }
}

/// Preferences › General: the theme, opening at login, the language and the updates.
struct GeneralPane: View {
    let model: AppModel
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @State private var language = LanguageChoice.current()
    @State private var restartError: String?
    @Environment(\.palette) private var palette

    var body: some View {
        PreferencesScroll {
            theme
            login
            languageSection
            updatesSection
        }
        .onAppear(perform: refreshLogin)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLogin()
        }
    }

    // MARK: Theme

    private var theme: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Theme")
            HStack(spacing: 6) {
                ForEach(ThemeMode.allCases, id: \.self) { mode in
                    GHButton(mode.title, selected: model.theme == mode, height: 30) { model.theme = mode }
                }
            }
        }
    }

    // MARK: Open at login

    private var login: some View {
        let enabled = loginStatus == .enabled
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Open at login")
            HStack(spacing: 6) {
                GHButton("login.on", selected: enabled, height: 30) { setLogin(true) }
                GHButton("login.off", selected: !enabled, height: 30) { setLogin(false) }
            }
            if loginStatus == .requiresApproval {
                line("Allow Pane in System Settings › General › Login Items.")
            }
            if let loginError { line(verbatim: loginError) }
        }
    }

    private func refreshLogin() { loginStatus = SMAppService.mainApp.status }

    private func setLogin(_ on: Bool) {
        loginError = nil
        do {
            if on {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if [.enabled, .requiresApproval].contains(SMAppService.mainApp.status) {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginError = error.localizedDescription
        }
        refreshLogin()
    }

    // MARK: Language

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Language")
            HStack(spacing: 6) {
                ForEach(LanguageChoice.allCases, id: \.self) { choice in
                    GHButton(choice.title, selected: language == choice, height: 30) {
                        restartError = nil
                        language = choice
                        choice.apply()
                    }
                }
            }
            if language != LanguageChoice.atLaunch {
                HStack(spacing: 12) {
                    Text("Applies when Pane restarts.")
                        .font(.manrope(10.5))
                        .foregroundStyle(palette.label)
                    Spacer(minLength: 0)
                    Button("Restart Now", action: restart)
                        .buttonStyle(TextButtonStyle())
                        .fontWeight(.semibold)
                }
                .padding(.top, 8)
                if let restartError { line(verbatim: restartError) }
            }
        }
    }

    // MARK: Updates

    private var updatesSection: some View {
        let updates = model.updates
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Updates")
            HStack(spacing: 12) {
                Text("Check automatically")
                    .font(.manrope(10.5))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    GHButton("updates.on", selected: updates.automaticallyChecks, height: 30) { updates.automaticallyChecks = true }
                    GHButton("updates.off", selected: !updates.automaticallyChecks, height: 30) { updates.automaticallyChecks = false }
                }
                .frame(width: 160)
            }
            HStack(spacing: 12) {
                Text("Version \(short) (\(build))")
                    .font(.manrope(10.5))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("Check Now") { updates.checkNow() }
                    .buttonStyle(TextButtonStyle())
                    .disabled(!updates.canCheck)
            }
            .padding(.top, 8)
        }
    }

    /// Opens a second instance, and quits this one only once it is open.
    private func restart() {
        restartError = nil
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    restartError = error.localizedDescription
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    // MARK: Lines

    private func line(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.manrope(10.5))
            .foregroundStyle(palette.label)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.top, 8)
    }

    private func line(verbatim text: String) -> some View {
        Text(verbatim: text)
            .font(.manrope(10.5))
            .foregroundStyle(palette.label)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.top, 8)
    }
}
