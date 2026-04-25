import Foundation

/// ADB bridge helper — runs `adb` commands for port forwarding.
enum ADBBridge {
    static func listDevices() -> [(serial: String, description: String)] {
        guard let output = runADB(["devices", "-l"]) else { return [] }
        var devices: [(String, String)] = []
        for line in output.split(separator: "\n") {
            let str = String(line)
            if str.starts(with: "List of") || str.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let parts = str.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2, parts[1] == "device" else { continue }
            devices.append((String(parts[0]), str))
        }
        return devices
    }

    static func resolveSerial(_ given: String?) -> String? {
        if let s = given { return s }
        let devices = listDevices()
        if devices.count == 1 { return devices[0].serial }
        if devices.isEmpty {
            Log.error("No ADB devices found")
        } else {
            Log.error("Multiple ADB devices; specify --serial")
        }
        return nil
    }

    @discardableResult
    static func forward(serial: String?, hostPort: UInt16, devicePort: UInt16) -> Bool {
        let serialArg = serial ?? resolveSerial(nil) ?? ""
        var args = [String]()
        if !serialArg.isEmpty {
            args += ["-s", serialArg]
        }
        args += ["forward", "tcp:\(hostPort)", "tcp:\(devicePort)"]
        return runADB(args) != nil
    }

    @discardableResult
    static func removeForward(serial: String?, hostPort: UInt16) -> Bool {
        let serialArg = serial ?? ""
        var args = [String]()
        if !serialArg.isEmpty {
            args += ["-s", serialArg]
        }
        args += ["forward", "--remove", "tcp:\(hostPort)"]
        return runADB(args) != nil
    }

    private static func runADB(_ args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["adb"] + args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus != 0 { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
