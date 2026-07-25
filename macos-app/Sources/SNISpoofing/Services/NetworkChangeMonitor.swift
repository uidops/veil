import Foundation
import Network
import AppKit

/// Watches the physical route independently of Veil's utun interface. A change
/// is emitted only when availability, the active physical interface, or the
/// normal default gateway changes.
final class NetworkChangeMonitor {
    enum Event {
        case unavailable
        case changed(String)
        case willSleep
        case didWake
    }

    var onEvent: ((Event) -> Void)?

    private struct Snapshot: Equatable {
        var available: Bool
        var interfaces: [String]
        var addresses: [String]
        var gateway: String

        var summary: String {
            if let first = interfaces.first { return first }
            return gateway.isEmpty ? "network" : gateway
        }
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "veil.network-change-monitor", qos: .utility)
    private var lastSnapshot: Snapshot?
    private var observers: [NSObjectProtocol] = []

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.consume(path)
        }
        monitor.start(queue: queue)

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.onEvent?(.willSleep)
        })
        observers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.onEvent?(.didWake)
        })
    }

    func cancel() {
        monitor.cancel()
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    private func consume(_ path: NWPath) {
        let snapshot = Self.snapshot(for: path)
        guard let previous = lastSnapshot else {
            lastSnapshot = snapshot
            return
        }
        guard snapshot != previous else { return }
        lastSnapshot = snapshot

        if !snapshot.available {
            onEvent?(.unavailable)
        } else {
            onEvent?(.changed(snapshot.summary))
        }
    }

    private static func snapshot(for path: NWPath) -> Snapshot {
        let physicalTypes: [NWInterface.InterfaceType] = [.wifi, .wiredEthernet, .cellular]
        let names = path.availableInterfaces
            .filter { interface in
                physicalTypes.contains(interface.type)
                    && path.usesInterfaceType(interface.type)
                    && !interface.name.hasPrefix("utun")
            }
            .map(\.name)
            .sorted()
        let route = defaultRoute()
        let routeInterface = route.interface.hasPrefix("utun") ? "" : route.interface
        let interfaces = names.isEmpty && !routeInterface.isEmpty ? [routeInterface] : names
        return Snapshot(
            available: path.status == .satisfied,
            interfaces: interfaces,
            addresses: interfaceAddresses(interfaces),
            gateway: route.gateway
        )
    }

    private static func interfaceAddresses(_ interfaces: [String]) -> [String] {
        interfaces.compactMap { interface in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
            process.arguments = [interface]
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
            let text = String(data: data, encoding: .utf8) ?? ""
            for line in text.split(separator: "\n") {
                let parts = line.split(whereSeparator: \Character.isWhitespace)
                if parts.count >= 2, parts[0] == "inet" {
                    return "\(interface)=\(parts[1])"
                }
            }
            return nil
        }
        .sorted()
    }

    private static func defaultRoute() -> (interface: String, gateway: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return ("", "") }
        } catch {
            return ("", "")
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        var interface = ""
        var gateway = ""
        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: \Character.isWhitespace)
            guard parts.count == 2 else { continue }
            if parts[0] == "interface:" { interface = String(parts[1]) }
            if parts[0] == "gateway:" { gateway = String(parts[1]) }
        }
        return (interface, gateway)
    }
}
