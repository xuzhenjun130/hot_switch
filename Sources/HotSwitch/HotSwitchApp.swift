import SwiftUI

@main
struct HotSwitchApp: App {
    @StateObject private var monitor: TemperatureMonitor

    init() {
        SettingsDefaults.register()
        _monitor = StateObject(wrappedValue: TemperatureMonitor())
        // Hide Dock icon even when run outside the .app bundle (swift run).
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: monitor, fan: monitor.fan)
        } label: {
            MenuBarLabel(monitor: monitor, fan: monitor.fan)
        }
        .menuBarExtraStyle(.window)

        Window("HotSwitch 设置", id: "settings") {
            SettingsView(fan: monitor.fan)
        }
        .windowResizability(.contentSize)
    }
}
