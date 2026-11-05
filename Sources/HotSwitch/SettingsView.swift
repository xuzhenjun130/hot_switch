import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var fan: FanController

    @AppStorage(SettingsKey.haURL) private var haURL = SettingsDefaults.haURL
    @AppStorage(SettingsKey.entityID) private var entityID = SettingsDefaults.entityID
    @AppStorage(SettingsKey.onThreshold) private var onThreshold = SettingsDefaults.onThreshold
    @AppStorage(SettingsKey.offThreshold) private var offThreshold = SettingsDefaults.offThreshold
    @AppStorage(SettingsKey.cpuRuleEnabled) private var cpuRuleEnabled = SettingsDefaults.cpuRuleEnabled
    @AppStorage(SettingsKey.cpuThreshold) private var cpuThreshold = SettingsDefaults.cpuThreshold
    @AppStorage(SettingsKey.cpuDuration) private var cpuDuration = SettingsDefaults.cpuDuration

    // Note: @State is a macro whose plugin ships only with Xcode, so local state lives here.
    @StateObject private var model = SettingsFormModel()

    var body: some View {
        Form {
            Section("Home Assistant") {
                TextField("地址", text: $haURL, prompt: Text("http://192.168.100.143:8123"))
                SecureField("长期访问令牌", text: $model.token)
                    .onSubmit { TokenStore.save(model.token) }
                TextField("插座 Entity ID", text: $entityID, prompt: Text("switch.xxx"))
                HStack {
                    Button("保存并测试连接") { test() }
                    if let testResult = model.testResult { Text(testResult).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section("温度阈值") {
                Stepper(value: $onThreshold, in: 40...100, step: 1) {
                    Text(String(format: "开启风扇：≥ %.0f°C", onThreshold))
                }
                Stepper(value: $offThreshold, in: 30...onThreshold, step: 1) {
                    Text(String(format: "关闭风扇：≤ %.0f°C", offThreshold))
                }
                Text("温度连续约 6 秒超过开启阈值才开启，连续约 30 秒低于关闭阈值才关闭，避免频繁开关。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("CPU 占用规则") {
                Toggle("进程 CPU 占用过高时开启风扇", isOn: $cpuRuleEnabled)
                Stepper(value: $cpuThreshold, in: 50...1000, step: 50) {
                    Text(String(format: "单个进程 CPU ≥ %.0f%%", cpuThreshold))
                }
                .disabled(!cpuRuleEnabled)
                Stepper(value: $cpuDuration, in: 4...600, step: cpuDuration < 30 ? 2 : 10) {
                    Text(String(format: "持续 %.0f 秒", cpuDuration))
                }
                .disabled(!cpuRuleEnabled)
                Text("100% = 占满一个核心。该进程回落到阈值以下后，按温度规则关闭风扇。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("通用") {
                Toggle("登录时启动", isOn: $model.launchAtLogin)
                    .onChange(of: model.launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            model.testResult = "登录启动设置失败：\(error.localizedDescription)"
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onDisappear { TokenStore.save(model.token) }
    }

    private func test() {
        TokenStore.save(model.token)
        model.testResult = "测试中…"
        Task {
            await fan.refresh()
            model.testResult = fan.lastError.map { "失败：\($0)" } ?? "成功，插座状态：\(fan.plugState.label)"
        }
    }
}

final class SettingsFormModel: ObservableObject {
    @Published var token = TokenStore.load()
    @Published var testResult: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
}
