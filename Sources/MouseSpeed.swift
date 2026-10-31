import Foundation
import IOKit.hid

enum Failure: Error, CustomStringConvertible {
    case message(String)
    var description: String { switch self { case .message(let s): return s } }
}

protocol HIDRequesting {
    func request(slot: UInt8, feature: UInt8, function: UInt8, params: [UInt8], attempts: Int) throws -> [UInt8]
}

extension HIDRequesting {
    func request(slot: UInt8, feature: UInt8, function: UInt8, params: [UInt8] = []) throws -> [UInt8] {
        try request(slot: slot, feature: feature, function: function, params: params, attempts: 3)
    }
}

final class HIDConnection: HIDRequesting {
    let device: IOHIDDevice
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    var reports: [[UInt8]] = []
    init(_ device: IOHIDDevice) throws {
        self.device = device
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw Failure.message("Cannot open HID device: \(result). Check Input Monitoring permission.") }
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, result, _, _, _, bytes, count in
            guard result == kIOReturnSuccess, let context else { return }
            let connection = Unmanaged<HIDConnection>.fromOpaque(context).takeUnretainedValue()
            connection.reports.append(Array(UnsafeBufferPointer(start: bytes, count: count)))
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }
    deinit {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer.deallocate()
    }
    func request(slot: UInt8, feature: UInt8, function: UInt8, params: [UInt8], attempts: Int) throws -> [UInt8] {
        var lastError: Error = Failure.message("No response")
        for _ in 0..<attempts {
            do { return try exchange(slot: slot, feature: feature, function: function, params: params) }
            catch { lastError = error }
        }
        throw lastError
    }
    private func exchange(slot: UInt8, feature: UInt8, function: UInt8, params: [UInt8]) throws -> [UInt8] {
        reports.removeAll()
        let fn = (function << 4) | 0x0D
        var packet: [UInt8] = [0x10, slot, feature, fn] + params
        packet += Array(repeating: 0, count: max(0, 7 - packet.count))
        let result = packet.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(packet[0]), $0.baseAddress!, packet.count) }
        guard result == kIOReturnSuccess else { throw Failure.message("HID request failed: \(result)") }
        let deadline = Date().addingTimeInterval(0.7)
        while Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.01, true)
            for report in reports where report.count >= 7 && report[1] == slot {
                if report[2] == feature && report[3] == fn { return report }
                if report[2] == 0xFF && report[3] == feature && report[4] == fn {
                    throw Failure.message("HID++ error: \(report[5])")
                }
            }
            reports.removeAll()
        }
        throw Failure.message("HID++ response timed out (slot \(slot))")
    }
}

enum ScrollMode: String, Codable {
    case ratchet
    case freeSpin
}

struct ScrollState: CustomStringConvertible {
    let mode: UInt8
    let autoDisengage: UInt8

    func matches(_ target: ScrollMode) -> Bool {
        switch target {
        case .ratchet: return mode == 2 && autoDisengage == 255
        case .freeSpin: return mode == 1
        }
    }

    var description: String {
        if mode == 1 { return "freeSpin" }
        return autoDisengage == 255 ? "ratchet" : "smartShift(threshold=\(autoDisengage))"
    }
}

struct ScrollWheel {
    let connection: HIDRequesting
    let slot: UInt8
    let feature: UInt8
    let enhanced: Bool

    func state() throws -> ScrollState {
        let reply = try connection.request(slot: slot, feature: feature, function: enhanced ? 1 : 0)
        guard reply.count >= 6, [1, 2].contains(reply[4]) else {
            throw Failure.message("Invalid SmartShift wheel status")
        }
        return ScrollState(mode: reply[4], autoDisengage: reply[5])
    }

    func setMode(_ mode: ScrollMode) throws {
        // HID++ 0x2110 / 0x2111: mode 2 enables ratcheting; threshold 255
        // disables automatic disengagement. Zero leaves other settings unchanged:
        // byte 3 is the default threshold (0x2110) or ratchet torque (0x2111).
        let params: [UInt8] = mode == .ratchet ? [2, 255, 0] : [1, 0, 0]
        _ = try connection.request(slot: slot, feature: feature, function: enhanced ? 2 : 1, params: params)
        guard try state().matches(mode) else {
            throw Failure.message("Mouse did not retain requested scroll mode \(mode.rawValue)")
        }
    }
}

struct Mouse {
    let connection: HIDRequesting
    let slot: UInt8
    let feature: UInt8
    let identity: String
    func dpi() throws -> Int {
        let r = try connection.request(slot: slot, feature: feature, function: 2, params: [0])
        return Int(r[5]) * 256 + Int(r[6])
    }
    func setDPI(_ value: Int) throws {
        guard (100...65535).contains(value) else { throw Failure.message("Invalid DPI") }
        _ = try connection.request(slot: slot, feature: feature, function: 3,
                                   params: [0, UInt8(value >> 8), UInt8(value & 255)])
        guard try dpi() == value else { throw Failure.message("Mouse did not retain requested DPI") }
    }

    func scrollWheel() throws -> ScrollWheel? {
        // Prefer SmartShift Enhanced; older models expose only SmartShift.
        for id: UInt16 in [0x2111, 0x2110] {
            let reply = try connection.request(slot: slot, feature: 0, function: 0,
                                               params: [UInt8(id >> 8), UInt8(id & 255)])
            guard reply[4] != 0 else { continue }
            return ScrollWheel(connection: connection, slot: slot, feature: reply[4], enhanced: id == 0x2111)
        }
        return nil
    }
}

func discover() throws -> [Mouse] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x046D] as CFDictionary)
    // Opening only the vendor interface avoids claiming keyboard or pointer input.
    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
    var mice: [Mouse] = []
    for device in devices {
        let page = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? 0
        guard page >= 0xFF00 else { continue }
        let connection: HIDConnection
        do { connection = try HIDConnection(device) }
        catch { fputs("\(error)\n", stderr); continue }
        for slot: UInt8 in [1, 2, 3, 4, 5, 6, 0xFF] {
            guard let reply = try? connection.request(slot: slot, feature: 0, function: 0, params: [0x22, 0x01], attempts: 1), reply[4] != 0 else { continue }
            guard let infoFeature = try? connection.request(slot: slot, feature: 0, function: 0, params: [0, 3]), infoFeature[4] != 0,
                  let info = try? connection.request(slot: slot, feature: infoFeature[4], function: 0), info.count >= 9 else { continue }
            let identity = info[5...8].map { String(format: "%02x", $0) }.joined()
            guard identity != "00000000" else { continue }
            let mouse = Mouse(connection: connection, slot: slot, feature: reply[4], identity: identity)
            if let dpi = try? mouse.dpi(), dpi > 0 {
                mice.append(mouse)
            }
        }
    }
    return mice
}

struct Configuration: Codable {
    let identity: String
    let dpi: Int
    var scrollMode: ScrollMode? = nil
}

func restore(_ config: Configuration, on mouse: Mouse, force: Bool = false) throws {
    var wheel: ScrollWheel?
    var wheelState: ScrollState?
    if config.scrollMode != nil {
        guard let supportedWheel = try mouse.scrollWheel() else {
            throw Failure.message("Configured mouse does not support SmartShift scroll mode (0x2110/0x2111)")
        }
        wheel = supportedWheel
        wheelState = try supportedWheel.state()
    }

    let current = try mouse.dpi()
    if force || current != config.dpi {
        try mouse.setDPI(config.dpi)
        print("\(Date()): verified DPI \(current) -> \(config.dpi)")
        fflush(stdout)
    }
    if let target = config.scrollMode, let wheel, let wheelState, force || !wheelState.matches(target) {
        try wheel.setMode(target)
        print("\(Date()): verified scroll mode \(wheelState) -> \(target.rawValue)")
        fflush(stdout)
    }
}

func restore(_ config: Configuration, force: Bool = false) throws -> Bool {
    for mouse in try discover() where mouse.identity == config.identity {
        try restore(config, on: mouse, force: force)
        return true
    }
    return false
}

func runCLI() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    let command = args.first ?? "probe"
    switch command {
    case "probe", "capture":
        let mice = try discover()
        guard !mice.isEmpty else { throw Failure.message("No accessible Logitech mouse with adjustable DPI found. Wake the mouse and check Input Monitoring permission.") }
        if command == "probe" {
            for mouse in mice {
                let dpi = try mouse.dpi()
                let scroll: String
                do {
                    if let wheel = try mouse.scrollWheel() { scroll = try wheel.state().description }
                    else { scroll = "unsupported" }
                } catch {
                    scroll = "unavailable"
                    fputs("Scroll mode query failed for \(mouse.identity): \(error)\n", stderr)
                }
                print("id=\(mouse.identity) slot=\(mouse.slot) dpi=\(dpi) scroll=\(scroll)")
            }
        } else {
            guard args.count == 2, mice.count == 1 else { throw Failure.message("Usage: mouse-speed capture CONFIG.json (exactly one mouse must be connected)") }
            let config = Configuration(identity: mice[0].identity, dpi: try mice[0].dpi())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: URL(fileURLWithPath: args[1]), options: .atomic)
            print("Saved current DPI \(config.dpi)")
        }
    case "apply", "watch":
        guard args.count == 2 else { throw Failure.message("Usage: mouse-speed \(command) CONFIG.json") }
        let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        guard (100...65535).contains(config.dpi), config.identity.count == 8 else { throw Failure.message("Invalid configuration") }
        if command == "apply" {
            guard try restore(config, force: true) else { throw Failure.message("Configured mouse is not connected or accessible") }
        } else {
            // Polling also covers mouse power cycles and wake without requiring accessibility event taps.
            // Each pass reopens the device so stale handles after USB reconnect are discarded.
            var previousError: String?
            while true {
                autoreleasepool {
                    do {
                        _ = try restore(config)
                        previousError = nil
                    } catch {
                        let message = String(describing: error)
                        if message != previousError { fputs("\(Date()): \(message)\n", stderr) }
                        previousError = message
                    }
                }
                Thread.sleep(forTimeInterval: 5)
            }
        }
    default:
        throw Failure.message("Usage: mouse-speed [probe | capture CONFIG.json | apply CONFIG.json | watch CONFIG.json]")
    }
}

#if !TESTING
@main
struct MouseSpeedKeeper {
    static func main() {
        do { try runCLI() }
        catch {
            fputs("\(error)\n", stderr)
            exit(1)
        }
    }
}
#endif
