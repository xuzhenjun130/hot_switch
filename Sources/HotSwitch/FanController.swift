import Foundation

/// Decides when to switch the fan plug on/off with hysteresis, and talks to Home Assistant.
@MainActor
final class FanController: ObservableObject {
    @Published private(set) var plugState: PlugState = .unknown
    @Published private(set) var lastError: String?
    @Published private(set) var lastAction: String?
    @Published private(set) var busy = false

    /// Consecutive samples required before switching.
    private let onSamplesRequired = 3      // ~6s at 2s interval
    private let offSamplesRequired = 15    // ~30s
    private let retryInterval: TimeInterval = 30
    private let refreshInterval: TimeInterval = 60

    private var hotCount = 0
    private var coolCount = 0
    private var lastAttempt: Date = .distantPast
    private var lastRefresh: Date = .distantPast

    private var defaults: UserDefaults { .standard }

    var autoControl: Bool {
        get { defaults.bool(forKey: SettingsKey.autoControl) }
        set { defaults.set(newValue, forKey: SettingsKey.autoControl); objectWillChange.send() }
    }
    var onThreshold: Double { defaults.double(forKey: SettingsKey.onThreshold) }
    var offThreshold: Double { min(defaults.double(forKey: SettingsKey.offThreshold), onThreshold) }
    var cpuRuleEnabled: Bool { defaults.bool(forKey: SettingsKey.cpuRuleEnabled) }
    var cpuThreshold: Double { defaults.double(forKey: SettingsKey.cpuThreshold) }
    var cpuDuration: Double { defaults.double(forKey: SettingsKey.cpuDuration) }

    private func makeClient() -> HomeAssistantClient {
        HomeAssistantClient(
            baseURL: defaults.string(forKey: SettingsKey.haURL) ?? "",
            token: TokenStore.load(),
            entityID: defaults.string(forKey: SettingsKey.entityID) ?? ""
        )
    }

    /// Feed a new temperature sample, plus the process that has stayed above the CPU threshold the longest.
    func handle(temperature: Double, cpuHog: CPUHog?) {
        if Date().timeIntervalSince(lastRefresh) > refreshInterval, !busy {
            Task { await refresh() }
        }
        guard autoControl else { hotCount = 0; coolCount = 0; return }

        let hog = cpuRuleEnabled ? cpuHog : nil
        let cpuTrigger = hog.map { $0.duration >= cpuDuration } ?? false

        if temperature >= onThreshold {
            hotCount += 1; coolCount = 0
        } else if hog != nil {
            // A busy process blocks switching off (avoids on/off flapping while it runs).
            hotCount = 0; coolCount = 0
        } else if temperature <= offThreshold {
            coolCount += 1; hotCount = 0
        } else {
            hotCount = 0; coolCount = 0
        }

        guard !busy, Date().timeIntervalSince(lastAttempt) > retryInterval || lastError == nil else { return }

        if hotCount >= onSamplesRequired, plugState != .on {
            Task { await setPower(true, reason: String(format: "温度 %.0f°C ≥ %.0f°C，自动开启", temperature, onThreshold)) }
        } else if cpuTrigger, let hog, plugState != .on {
            Task { await setPower(true, reason: String(format: "%@ CPU %.0f%% 持续 %.0f 秒，自动开启", hog.name, hog.percent, hog.duration)) }
        } else if coolCount >= offSamplesRequired, plugState == .on || plugState == .unknown {
            Task { await setPower(false, reason: String(format: "温度 %.0f°C ≤ %.0f°C，自动关闭", temperature, offThreshold)) }
        }
    }

    /// Manual control from the menu. Disables auto control so it doesn't fight the user.
    func manual(_ on: Bool) {
        autoControl = false
        Task { await setPower(on, reason: on ? "手动开启" : "手动关闭") }
    }

    func setPower(_ on: Bool, reason: String) async {
        busy = true
        lastAttempt = Date()
        defer { busy = false }
        let client = makeClient()
        do {
            try await client.setPower(on)
            lastError = nil
            lastAction = "\(Self.timeFormatter.string(from: Date())) \(reason)"
            // Give the plug a moment, then confirm the real state.
            try? await Task.sleep(for: .seconds(1))
            plugState = (try? await client.state()) ?? (on ? .on : .off)
            lastRefresh = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refresh() async {
        lastRefresh = Date()
        do {
            plugState = try await makeClient().state()
            lastError = nil
        } catch {
            plugState = .unknown
            lastError = error.localizedDescription
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
