import Foundation
import ServiceManagement
import SwiftUI
import UserNotifications

enum AppLanguage: String, CaseIterable, Identifiable {
    case korean = "ko"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .korean: return "한국어"
        case .english: return "English"
        }
    }

    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("ko") ? .korean : .english
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: HubSettings.Keys.language) ?? "") ?? systemDefault
    }
}

final class HubSettings: ObservableObject {
    enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let usageReminderEnabled = "usageReminderEnabled"
        static let reminderThreshold = "reminderThreshold"
        static let autoSwitchEnabled = "autoSwitchEnabled"
        static let autoSwitchThreshold = "autoSwitchThreshold"
        static let quotaAPIEnabled = "quotaAPIEnabled"
        static let language = "language"
    }

    private let defaults = UserDefaults.standard

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin()
        }
    }

    @Published var usageReminderEnabled: Bool {
        didSet {
            defaults.set(usageReminderEnabled, forKey: Keys.usageReminderEnabled)
            if usageReminderEnabled {
                requestNotificationPermission()
            }
        }
    }

    @Published var reminderThreshold: Int {
        didSet { defaults.set(reminderThreshold, forKey: Keys.reminderThreshold) }
    }

    @Published var autoSwitchEnabled: Bool {
        didSet { defaults.set(autoSwitchEnabled, forKey: Keys.autoSwitchEnabled) }
    }

    @Published var autoSwitchThreshold: Int {
        didSet { defaults.set(autoSwitchThreshold, forKey: Keys.autoSwitchThreshold) }
    }

    @Published var quotaAPIEnabled: Bool {
        didSet { defaults.set(quotaAPIEnabled, forKey: Keys.quotaAPIEnabled) }
    }

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var statusMessage: String?

    init() {
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        usageReminderEnabled = defaults.object(forKey: Keys.usageReminderEnabled) as? Bool ?? false
        reminderThreshold = defaults.object(forKey: Keys.reminderThreshold) as? Int ?? 10
        autoSwitchEnabled = defaults.object(forKey: Keys.autoSwitchEnabled) as? Bool ?? false
        autoSwitchThreshold = defaults.object(forKey: Keys.autoSwitchThreshold) as? Int ?? 10
        quotaAPIEnabled = defaults.object(forKey: Keys.quotaAPIEnabled) as? Bool ?? false
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? AppLanguage.systemDefault
    }

    private func applyLaunchAtLogin() {
        guard #available(macOS 13.0, *) else {
            statusMessage = L.launchAtLoginRequiresMacOS13
            return
        }
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                if let error {
                    self.statusMessage = error.localizedDescription
                } else if granted {
                    self.statusMessage = L.notificationsEnabled
                } else {
                    self.statusMessage = L.notificationsDenied
                }
            }
        }
    }
}
