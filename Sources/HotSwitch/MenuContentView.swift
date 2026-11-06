import SwiftUI
import Charts

struct MenuBarLabel: View {
    @ObservedObject var monitor: TemperatureMonitor
    @ObservedObject var fan: FanController

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: fan.plugState == .on ? "fan.fill" : "flame.fill")
            Text(monitor.temperature.map { String(format: "%.0f°C", $0) } ?? "--°C")
                .monospacedDigit()
        }
    }
}

struct MenuContentView: View {
    @ObservedObject var monitor: TemperatureMonitor
    @ObservedObject var fan: FanController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(icon: "flame", title: "散热压力：", value: monitor.thermalState.label)
            row(icon: "thermometer.medium", title: "温度：",
                value: monitor.temperature.map { String(format: "%.0f°C", $0) } ?? "--")
            row(icon: "cpu", title: "占用最高进程：",
                value: monitor.topProcess.map { String(format: "%@ %.0f%%", $0.name, $0.percent) } ?? "--")

            chart
                .frame(height: 140)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))

            Divider()

            fanSection

            Divider()

            HStack {
                Button("设置…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private func row(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 14))
    }

    private var chart: some View {
        Chart {
            ForEach(monitor.history) { s in
                LineMark(x: .value("Time", s.date), y: .value("Temperature", s.value))
                    .foregroundStyle(by: .value("Series", "温度"))
                    .interpolationMethod(.monotone)
            }
            RuleMark(y: .value("开启阈值", fan.onThreshold))
                .foregroundStyle(.red.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartForegroundStyleScale(["温度": Color.orange])
        .chartXAxis(.hidden)
        .chartYScale(domain: yDomain)
        .chartLegend(position: .bottom, alignment: .leading)
    }

    private var yDomain: ClosedRange<Double> {
        let values = monitor.history.map(\.value) + [fan.onThreshold]
        let lo = (values.min() ?? 30) - 5
        let hi = (values.max() ?? 80) + 5
        return lo...hi
    }

    private var fanSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "fan").frame(width: 18).foregroundStyle(.secondary)
                Text("风扇插座:").foregroundStyle(.secondary)
                Spacer()
                if fan.busy { ProgressView().controlSize(.small) }
                Text(fan.plugState.label)
                    .foregroundStyle(fan.plugState == .on ? .green : .primary)
            }
            .font(.system(size: 14))

            Toggle(isOn: Binding(get: { fan.autoControl }, set: { fan.autoControl = $0 })) {
                Text(fan.cpuRuleEnabled
                     ? String(format: "自动控制（≥%.0f°C 或进程 CPU ≥%.0f%% 持续 %.0f 秒开，≤%.0f°C 关）",
                              fan.onThreshold, fan.cpuThreshold, fan.cpuDuration, fan.offThreshold)
                     : String(format: "自动控制（≥%.0f°C 开，≤%.0f°C 关）", fan.onThreshold, fan.offThreshold))
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            HStack {
                Button("开启") { fan.manual(true) }
                Button("关闭") { fan.manual(false) }
                Button("刷新") { Task { await fan.refresh() } }
            }
            .disabled(fan.busy)

            if let action = fan.lastAction {
                Text(action).font(.caption).foregroundStyle(.secondary)
            }
            if let err = fan.lastError {
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(3)
            }
        }
    }
}
