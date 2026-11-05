import Foundation
import Security

enum SettingsKey {
    static let haURL = "haURL"
    static let entityID = "entityID"
    static let onThreshold = "onThreshold"
    static let offThreshold = "offThreshold"
    static let autoControl = "autoControl"
    static let cpuRuleEnabled = "cpuRuleEnabled"
    static let cpuThreshold = "cpuThreshold"
    static let cpuDuration = "cpuDuration"
}

enum SettingsDefaults {
    static let haURL = "http://192.168.100.143:8123"
    static let entityID = ""
    static let onThreshold = 70.0
    static let offThreshold = 60.0
    static let autoControl = true
    static let cpuRuleEnabled = true
    static let cpuThreshold = 100.0     // % of one core
    static let cpuDuration = 30.0       // seconds

    static func register() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.haURL: haURL,
            SettingsKey.entityID: entityID,
            SettingsKey.onThreshold: onThreshold,
            SettingsKey.offThreshold: offThreshold,
            SettingsKey.autoControl: autoControl,
            SettingsKey.cpuRuleEnabled: cpuRuleEnabled,
            SettingsKey.cpuThreshold: cpuThreshold,
            SettingsKey.cpuDuration: cpuDuration,
        ])
    }
}

/// Stores the Home Assistant long-lived access token in the login Keychain.
enum TokenStore {
    private static let service = "com.sherman.HotSwitch"
    private static let account = "HomeAssistantToken"

    static func load() -> String {
        // Allow override from environment for development
        if let env = ProcessInfo.processInfo.environment["HA_TOKEN"], !env.isEmpty { return env }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ token: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !token.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
