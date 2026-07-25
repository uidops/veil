import Foundation

/// Drives a root-owned utun + tun2socks bridge via the `cloak-tun` sudo helper.
///
/// This replaces an earlier NEPacketTunnelProvider implementation that needed
/// an Apple Developer ID and provisioning profile (NetworkExtension entitlements
/// can't be satisfied by ad-hoc signing). The new path:
///   1. Helper script (NOPASSWD sudo) spawns the bundled tun2socks binary,
///      creates a utun device, and rewrites the default route through it.
///   2. tun2socks bridges utun traffic to the local SOCKS proxy that xray
///      already exposes — so packets still go through the SNI-spoofed path.
///
/// No NetworkExtension entitlements required. No signing identity required.
final class PacketTunnelManager {
    struct StartParameters {
        var connectIP: String
        var socksHost: String
        var socksPort: Int
        var logLevel: String
        var excludedIPv4Routes: [String]
    }

    private static var bundledTun2socksPath: String? {
        let arch: String
        #if arch(arm64)
        arch = "arm64"
        #else
        arch = "x86_64"
        #endif
        let name = "tun2socks-\(arch)"
        if let url = Bundle.main.url(forResource: name, withExtension: nil),
           FileManager.default.isExecutableFile(atPath: url.path) {
            return url.path
        }
        return nil
    }

    /// Returns the interface used by the normal default route before utun is
    /// installed. Xray binds its direct outbound to this interface so bypassed
    /// sockets cannot be captured by tun2socks again.
    static func defaultPhysicalInterface() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: \Character.isWhitespace)
            guard parts.count == 2, parts[0] == "interface:" else { continue }
            let name = String(parts[1])
            let valid = name.allSatisfy { $0.isLetter || $0.isNumber || "._-".contains($0) }
            if valid, !name.hasPrefix("utun") { return name }
        }
        return nil
    }

    func start(parameters: StartParameters) throws {
        guard let binPath = Self.bundledTun2socksPath else {
            throw NSError(
                domain: "SNISpoofing",
                code: 75,
                userInfo: [NSLocalizedDescriptionKey: "tun2socks binary is missing from the app bundle. Rebuild Veil so Resources/tun2socks-<arch> is present."]
            )
        }
        var args: [String] = [
            "start",
            "--connect-ip", parameters.connectIP,
            "--socks-host", parameters.socksHost,
            "--socks-port", String(parameters.socksPort),
            "--bin", binPath,
            "--loglevel", parameters.logLevel,
        ]
        for route in parameters.excludedIPv4Routes {
            args.append(contentsOf: ["--exclude-ip", route])
        }
        let (status, output) = SudoPrivilege.runTunHelper(args)
        if status != 0 {
            _ = SudoPrivilege.runTunHelper(["stop"])
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = trimmed.isEmpty ? "exit \(status)" : trimmed
            throw NSError(
                domain: "SNISpoofing",
                code: 76,
                userInfo: [NSLocalizedDescriptionKey: "Couldn't bring up the packet tunnel: \(detail)"]
            )
        }
    }

    func stop() {
        _ = SudoPrivilege.runTunHelper(["stop"])
    }

    /// Synchronous teardown for app-termination paths.
    func stopSync() {
        _ = SudoPrivilege.runTunHelper(["stop"])
    }

    @discardableResult
    func stopAndReport() -> Bool {
        SudoPrivilege.runTunHelper(["stop"]).0 == 0
    }

    /// Reasserts and verifies all persisted IPv4/IPv6 tunnel and bypass routes.
    /// The root helper performs this idempotently from its own session state.
    func repairRoutes() -> (ok: Bool, detail: String) {
        let (status, output) = SudoPrivilege.runTunHelper(["repair"])
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return (status == 0, detail)
    }

    /// Best-effort check whether the helper still has tun2socks alive.
    func isRunning() -> Bool {
        let (status, output) = SudoPrivilege.runTunHelper(["status"])
        guard status == 0 else { return false }
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "running"
    }
}
