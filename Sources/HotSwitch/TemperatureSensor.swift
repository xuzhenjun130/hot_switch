import Foundation
import CSensors

/// Reads CPU temperature via AppleSMC, with the (private) IOHIDEventSystem API as fallback.
final class TemperatureSensor {
    private static let kIOHIDEventTypeTemperature: Int64 = 15
    private static let temperatureField: Int32 = Int32(kIOHIDEventTypeTemperature << 16)

    private let client: CFTypeRef?

    init() {
        client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
        if let client {
            let matching: [String: Any] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5]
            _ = IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)
        }
    }

    /// All temperature sensors: name -> °C
    func readAll() -> [String: Double] {
        guard let client, let services = IOHIDEventSystemClientCopyServices(client) as? [CFTypeRef] else {
            return [:]
        }
        var result: [String: Double] = [:]
        for service in services {
            let name = (IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String) ?? "Unknown"
            guard let event = IOHIDServiceClientCopyEvent(service, Self.kIOHIDEventTypeTemperature, 0, 0) else { continue }
            let value = IOHIDEventGetFloatValue(event, Self.temperatureField)
            // Filter out obviously bogus readings
            guard value > 0, value < 150 else { continue }
            result[name] = max(result[name] ?? 0, value)
        }
        return result
    }

    /// CPU temperature, computed like the "Hot" app on Apple Silicon without pACC/eACC HID sensors (e.g. M4):
    /// the hottest of all SMC `T*` keys and HID temperature sensors in (0, 120) °C, ignoring `tcal`.
    func cpuTemperature() -> Double? {
        let all = readAll().filter { $0.value < 120 }
        // Hot uses only pACC/eACC HID sensors when present (M1–M3)
        let cpu = all.filter { $0.key.hasPrefix("pACC") || $0.key.hasPrefix("eACC") }
        if let v = cpu.values.max() { return v }
        var avg = 0.0, smcMax = 0.0
        let smcOK = hs_smc_cpu_temperature(&avg, &smcMax) > 0
        let hid = hidTemperature(all)
        switch (smcOK, hid) {
        case (true, let h?): return max(smcMax, h)
        case (true, nil): return smcMax
        case (false, let h): return h
        }
    }

    private func hidTemperature(_ all: [String: Double]) -> Double? {
        let tcal = all.first { $0.key.lowercased().hasSuffix("tcal") }?.value
        return all.filter { name, v in
            if name.lowercased().hasSuffix("tcal") { return false }
            if let tcal, Int((tcal * 100).rounded(.up)) == Int((v * 100).rounded(.up)) { return false }
            return true
        }.values.max()
    }
}
