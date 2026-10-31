import Foundation

// Simulated HID++ device: exercise restoration without accessing a real mouse.
final class TestHID: HIDRequesting {
    let featureID: UInt16?
    var mode: UInt8 = 2
    var threshold: UInt8 = 20
    var thirdByte: UInt8 = 65 // Enhanced torque, or legacy default threshold.
    var dpi = 2300
    var retainWheelWrites = true
    var failFeatureQuery = false
    var malformedStatus = false
    var calls: [(feature: UInt8, function: UInt8, params: [UInt8])] = []
    var writes: [(feature: UInt8, params: [UInt8])] = []

    init(_ featureID: UInt16? = 0x2111) { self.featureID = featureID }

    func request(slot: UInt8, feature: UInt8, function: UInt8, params: [UInt8], attempts: Int) throws -> [UInt8] {
        calls.append((feature, function, params))
        var payload: [UInt8]
        if feature == 0 {
            if failFeatureQuery { throw Failure.message("Simulated timeout") }
            let id = UInt16(params[0]) << 8 | UInt16(params[1])
            payload = [id == featureID ? 8 : 0, 0, 0]
        } else if feature == 7 {
            if function == 3 {
                writes.append((feature, params))
                dpi = Int(params[1]) << 8 | Int(params[2])
            }
            payload = [0, UInt8(dpi >> 8), UInt8(dpi & 255)]
        } else if feature == 8 {
            let readFunction: UInt8 = featureID == 0x2111 ? 1 : 0
            if function == readFunction + 1 {
                writes.append((feature, params))
                if retainWheelWrites {
                    if params[0] != 0 { mode = params[0] }
                    if params[1] != 0 { threshold = params[1] }
                    if params[2] != 0 { thirdByte = params[2] }
                }
            } else if function != readFunction {
                throw Failure.message("Unexpected wheel function \(function)")
            }
            payload = malformedStatus ? [0, 0, 0] : [mode, threshold, thirdByte]
        } else {
            throw Failure.message("Unexpected feature \(feature)")
        }
        return [0x10, slot, feature, (function << 4) | 0x0D] + payload
    }

    var mouse: Mouse { Mouse(connection: self, slot: 1, feature: 7, identity: "1234abcd") }
}

func expect(_ condition: Bool, _ message: String) throws {
    guard condition else { throw Failure.message(message) }
}

func expectFailure(_ message: String, _ body: () throws -> Void) throws {
    do { try body() }
    catch { return }
    throw Failure.message(message)
}

@main
struct ScrollModeTests {
    static func main() throws {
        let decoder = JSONDecoder()
        let oldConfig = try decoder.decode(Configuration.self, from: Data(#"{"identity":"1234abcd","dpi":2300}"#.utf8))
        try expect(oldConfig.scrollMode == nil, "Old configurations must leave the wheel unmanaged")
        let ratchet = try decoder.decode(Configuration.self, from: Data(#"{"identity":"1234abcd","dpi":2300,"scrollMode":"ratchet"}"#.utf8))
        try expect(ratchet.scrollMode == .ratchet, "Ratchet configuration must decode")
        try expectFailure("Invalid mode must be rejected before accessing hardware") {
            _ = try decoder.decode(Configuration.self, from: Data(#"{"identity":"1234abcd","dpi":2300,"scrollMode":"typo"}"#.utf8))
        }
        let captured = String(decoding: try JSONEncoder().encode(oldConfig), as: UTF8.self)
        try expect(!captured.contains("scrollMode"), "DPI-only capture must stay compatible")

        let dpiOnly = TestHID(nil)
        dpiOnly.dpi = 2200
        try restore(oldConfig, on: dpiOnly.mouse)
        try expect(dpiOnly.dpi == 2300, "DPI restoration must still work")
        try expect(dpiOnly.calls.allSatisfy { $0.feature == 7 }, "Absent scrollMode must not access wheel features")

        for id: UInt16 in [0x2111, 0x2110] {
            let device = TestHID(id)
            // Already ratcheting, but rapid scrolling would still disengage.
            try restore(ratchet, on: device.mouse)
            try expect(device.mode == 2 && device.threshold == 255, "Ratchet must disable automatic disengagement")
            try expect(device.thirdByte == 65, "Wheel torque/default threshold must be preserved")
            try expect(device.writes.count == 1 && device.writes[0].feature == 8, "Only the wheel should need a write")
            let queries = device.calls.filter { $0.feature == 0 }.map { $0.params }
            try expect(queries == (id == 0x2111 ? [[0x21, 0x11]] : [[0x21, 0x11], [0x21, 0x10]]), "Prefer Enhanced, then fall back to legacy")
            try restore(ratchet, on: device.mouse)
            try expect(device.writes.count == 1, "Unchanged state must not be rewritten")
            device.mode = 1 // Simulate a mode-button press or external change.
            try restore(ratchet, on: device.mouse)
            try expect(device.mode == 2 && device.writes.count == 2, "A later mode change must be restored")
            try restore(ratchet, on: device.mouse, force: true)
            try expect(device.writes.count == 4, "Apply must force DPI and wheel writes")

            let freeSpin = Configuration(identity: oldConfig.identity, dpi: oldConfig.dpi, scrollMode: .freeSpin)
            device.threshold = 30
            try restore(freeSpin, on: device.mouse)
            try expect(device.mode == 1 && device.threshold == 30 && device.thirdByte == 65, "Free spin must preserve threshold and torque")
            try expect(try device.mouse.scrollWheel()!.state().description == "freeSpin", "Probe must report free spin")
        }

        let unsupported = TestHID(nil)
        unsupported.dpi = 2200
        try expectFailure("An unsupported wheel must not silently succeed") {
            try restore(ratchet, on: unsupported.mouse)
        }
        try expect(unsupported.writes.isEmpty, "Validate wheel support before changing DPI")

        let timeout = TestHID()
        timeout.failFeatureQuery = true
        try expectFailure("A feature-query timeout must propagate") { try restore(ratchet, on: timeout.mouse) }
        try expect(timeout.calls.count == 1 && timeout.writes.isEmpty, "Do not mistake a timeout for an unsupported feature")

        let ignored = TestHID()
        ignored.retainWheelWrites = false
        try expectFailure("A successful write response requires matching readback") { try restore(ratchet, on: ignored.mouse) }
        let malformed = TestHID()
        malformed.malformedStatus = true
        try expectFailure("Invalid status must be rejected") { try restore(ratchet, on: malformed.mouse) }
        try expect(malformed.writes.isEmpty, "Invalid status must not cause a write")

        try expect(ScrollState(mode: 2, autoDisengage: 20).description == "smartShift(threshold=20)", "Probe must distinguish SmartShift from fixed ratchet")
        print("PASS: configuration compatibility, both SmartShift protocols, restoration, and readback failures")
    }
}
