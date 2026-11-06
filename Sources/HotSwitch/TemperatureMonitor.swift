import Foundation

struct TemperatureSample: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

@MainActor
final class TemperatureMonitor: ObservableObject {
    @Published private(set) var temperature: Double?
    @Published private(set) var history: [TemperatureSample] = []
    @Published private(set) var topProcess: CPUHog?
    @Published private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    let fan = FanController()

    private let sensor = TemperatureSensor()
    private let processMonitor = ProcessCPUMonitor()
    private var processSampling = false
    private var cpuHog: CPUHog?
    private let interval: TimeInterval = 2
    private let maxSamples = 120
    private var timer: Timer?

    init() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        Task { await fan.refresh() }
    }

    private func sample() {
        thermalState = ProcessInfo.processInfo.thermalState
        guard let value = sensor.cpuTemperature() else { return }
        temperature = value
        history.append(TemperatureSample(date: Date(), value: value))
        if history.count > maxSamples { history.removeFirst(history.count - maxSamples) }
        fan.handle(temperature: value, cpuHog: cpuHog)
        sampleProcesses()
    }

    /// Runs `ps` off the main thread; the result is used by the next temperature sample.
    private func sampleProcesses() {
        guard !processSampling else { return }
        processSampling = true
        let threshold = fan.cpuThreshold
        Task {
            let result = await processMonitor.sample(threshold: threshold)
            topProcess = result.top
            cpuHog = result.hog
            processSampling = false
        }
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: return "正常"
        case .fair: return "偏高"
        case .serious: return "严重"
        case .critical: return "临界"
        @unknown default: return "未知"
        }
    }
}
