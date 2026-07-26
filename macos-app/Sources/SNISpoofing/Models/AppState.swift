import Foundation
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {
    enum Status: Equatable {
        case stopped
        case starting
        case running
        case pausing
        case paused
        case resuming
        case stopping
        case error(String)

        var isRunning: Bool {
            if case .running = self { return true } else { return false }
        }
        var isPaused: Bool {
            if case .paused = self { return true } else { return false }
        }
        var isSessionActive: Bool { isRunning || isPaused }
        var isTransitioning: Bool {
            switch self {
            case .starting, .pausing, .resuming, .stopping: return true
            default: return false
            }
        }
        var label: String {
            switch self {
            case .stopped: return "Disconnected"
            case .starting: return "Connecting…"
            case .running: return "Connected"
            case .pausing: return "Pausing…"
            case .paused: return "Paused"
            case .resuming: return "Resuming…"
            case .stopping: return "Disconnecting…"
            case .error(let msg): return "Error: \(msg)"
            }
        }
    }

    @Published var settings: AppSettings
    @Published var profiles: [Profile]
    /// Written to `<pythonProjectPath>/config.json` on Start.
    @Published var listenerProject: ListenerProjectConfig
    /// Whether the one-time admin escalation has installed a sudoers rule.
    @Published var privilegesInstalled: Bool = SudoPrivilege.isInstalled()

    @Published var status: Status = .stopped
    @Published var logs: [LogLine] = []
    @Published var startedAt: Date?
    @Published var pauseError: String?

    /// Measured bytes/second through the local SOCKS (updated ~1Hz while running).
    @Published var downloadBytesPerSec: Double = 0
    @Published var uploadBytesPerSec: Double = 0
    /// Cumulative RX/TX since this session’s `startedAt` (same counter source as speed).
    @Published var sessionBytesDown: UInt64 = 0
    @Published var sessionBytesUp: UInt64 = 0

    @Published var egressIP: String?
    @Published var egressCountry: String?
    @Published var egressCity: String?
    @Published var egressLat: Double?
    @Published var egressLon: Double?
    @Published var egressLookupMessage: String?

    @Published var profilePingResults: [UUID: RealPingService.Result] = [:]
    @Published var profilePingingIDs: Set<UUID> = []
    @Published var isPingBatchRunning = false
    @Published var updateState: AppUpdateState = .idle
    @Published var isFailingOver = false
    @Published var failoverMessage: String?
    @Published var consecutiveHealthFailures = 0
    @Published var isRecoveringNetwork = false
    @Published var networkRecoveryMessage: String?
    @Published var routeIntegrityMessage: String?
    @Published var isRestoringNetworkState = false

    private let store = ConfigStore()
    private let python = PythonListener()
    private let xray = XrayCoreManager()
    private let packetTunnel = PacketTunnelManager()
    private let updater = AppUpdateService.shared
    private let networkMonitor = NetworkChangeMonitor()
    /// Tracks whether we flipped the system SOCKS proxy on (must be flipped back off on stop).
    private var systemProxyActive = false
    /// Tracks whether we started the NetworkExtension packet tunnel.
    private var tunnelActive = false
    /// True when we started the Python listener only for Profiles ping (not full VPN).
    private var listenerStartedForPingOnly = false
    private var sessionBaselineRx: UInt64 = 0
    private var sessionBaselineTx: UInt64 = 0
    private var pingBatchToken: UUID?
    private var pingBatchTask: Task<Void, Never>?
    private var failoverTask: Task<Void, Never>?
    private var networkRecoveryTask: Task<Void, Never>?
    private var routeWatchdogTask: Task<Void, Never>?
    private var routeRepairFailures = 0
    private var networkRecoveryPending = false
    private var recoverAfterWake = false
    private var physicalNetworkAvailable = true
    private var ignoreNetworkChangesUntil = Date.distantPast
    private var networkRecoveryAttempts = 0
    private static let maxConcurrentPingWorkers = 4

    init() {
        self.settings = store.loadSettings() ?? .default
        self.profiles = store.loadProfiles()
        self.listenerProject = store.loadListenerProjectConfig() ?? .default
        self.profilePingResults = store.loadPingResults()

        python.onLog = { [weak self] line in
            Task { @MainActor in self?.appendLog(line, prefix: "") }
        }
        xray.onLog = { [weak self] line in
            Task { @MainActor in self?.appendLog(line, prefix: "") }
        }
        networkMonitor.onEvent = { [weak self] event in
            Task { @MainActor in self?.handleNetworkEvent(event) }
        }

        if store.loadActiveNetworkSession() != nil {
            isRestoringNetworkState = true
            Task { @MainActor [weak self] in self?.recoverStaleNetworkState() }
        }

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await self?.checkForUpdates(silent: true)
        }
    }

    private func appendLog(_ line: LogLine, prefix: String) {
        guard settings.logsEnabled else { return }
        let l = LogLine(timestamp: line.timestamp, stream: line.stream, text: prefix + line.text)
        if logs.count > 5000 { logs.removeFirst(1000) }
        logs.append(l)
    }

    /// Synchronous best-effort shutdown for app termination paths where async
    /// `stop()` would race the process exit. Tears down xray + python and
    /// removes TUN routes if they were applied.
    @MainActor
    func terminateSync() {
        failoverTask?.cancel()
        failoverTask = nil
        networkRecoveryTask?.cancel()
        networkRecoveryTask = nil
        routeWatchdogTask?.cancel()
        routeWatchdogTask = nil
        networkMonitor.cancel()
        var networkClean = true
        if systemProxyActive {
            if case .failed = SystemProxy.disable() { networkClean = false }
            systemProxyActive = false
        }
        if tunnelActive {
            networkClean = packetTunnel.stopAndReport() && networkClean
            tunnelActive = false
        }
        if networkClean { store.clearActiveNetworkSession() }
        xray.stopSync()
        python.stop()
        // Belt-and-suspenders: kill any orphaned listener spawned via sudo
        // wrapper (the user's macOS reported a leftover python heating up
        // the machine after a previous version's window was closed).
        SudoPrivilege.killLeftoverListener()
    }

    func saveSettings() { store.saveSettings(settings) }
    func saveProfiles() { store.saveProfiles(profiles) }
    func saveListenerProject() { store.saveListenerProjectConfig(listenerProject) }

    var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func checkForUpdates(silent: Bool = false) async {
        if case .checking = updateState { return }
        if !silent { updateState = .checking }
        do {
            let release = try await updater.latestRelease()
            if updater.isNewer(release.version, than: currentAppVersion) {
                updateState = .available(release)
            } else if !silent {
                updateState = .upToDate(currentAppVersion)
            }
        } catch {
            if !silent {
                updateState = .failed(error.localizedDescription)
            }
        }
    }

    func downloadAvailableUpdate() async {
        guard case .available(let release) = updateState else { return }
        updateState = .downloading(release, 0)
        do {
            let fileURL = try await updater.downloadDMG(for: release) { [weak self] progress in
                Task { @MainActor in
                    self?.updateState = .downloading(release, progress)
                }
            }
            updateState = .downloaded(fileURL)
            NSWorkspace.shared.open(fileURL)
        } catch is CancellationError {
            updateState = .available(release)
        } catch {
            updateState = .failed(error.localizedDescription)
        }
    }

    func cancelUpdateDownload() {
        guard case .downloading(let release, _) = updateState else { return }
        updater.cancelDownload()
        updateState = .available(release)
    }

    var activeProfile: Profile? {
        guard let id = settings.activeProfileID else { return nil }
        return profiles.first(where: { $0.id == id })
    }

    func upsert(_ profile: Profile) {
        if let i = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[i] = profile
        } else {
            profiles.append(profile)
            if settings.activeProfileID == nil {
                settings.activeProfileID = profile.id
                saveSettings()
            }
        }
        saveProfiles()
        refreshFailoverAfterProfileChange()
    }

    func delete(profileID id: UUID) {
        profiles.removeAll { $0.id == id }
        profilePingResults.removeValue(forKey: id)
        persistPingResults()
        if settings.activeProfileID == id {
            settings.activeProfileID = profiles.first?.id
            saveSettings()
        }
        saveProfiles()
        refreshFailoverAfterProfileChange()
    }

    /// Profiles with no successful ping (failed, untested, or missing ms).
    var profilesWithoutSuccessfulPing: [Profile] {
        profiles.filter { profilePingResults[$0.id]?.millis == nil }
    }

    @discardableResult
    func deleteProfilesWithoutSuccessfulPing() -> Int {
        let doomed = profilesWithoutSuccessfulPing.map(\.id)
        guard !doomed.isEmpty else { return 0 }
        for id in doomed {
            delete(profileID: id)
        }
        return doomed.count
    }

    func setActive(_ id: UUID) {
        guard !isFailingOver, !isRecoveringNetwork else { return }
        settings.activeProfileID = id
        saveSettings()
    }

    @discardableResult
    func importFromURL(_ raw: String) throws -> Profile {
        let p = try ProfileImporter.importFrom(raw)
        upsert(p)
        return p
    }

    struct ImportSummary {
        var added: Int
        var duplicates: Int
        var failed: [String]
        var firstAddedID: UUID?
        var totalParsed: Int { added + duplicates }
    }

    /// Bulk-import every URI we can find in `raw`, skipping ones that are
    /// already in the library (same kind + server + port + secret + SNI).
    /// The first imported profile becomes active if no profile is set yet.
    @discardableResult
    func importMany(from raw: String) -> ImportSummary {
        let parse = ProfileImporter.importMany(from: raw)
        var added = 0
        var duplicates = 0
        var firstAddedID: UUID?
        for parsed in parse.profiles {
            let isDuplicate = profiles.contains { existing in
                existing.kind == parsed.kind
                    && existing.server == parsed.server
                    && existing.serverPort == parsed.serverPort
                    && existing.tls.serverName == parsed.tls.serverName
                    && existing.uuid == parsed.uuid
                    && existing.password == parsed.password
            }
            if isDuplicate {
                duplicates += 1
                continue
            }
            profiles.append(parsed)
            if firstAddedID == nil { firstAddedID = parsed.id }
            added += 1
        }
        if added > 0 {
            if settings.activeProfileID == nil, let id = firstAddedID {
                settings.activeProfileID = id
                saveSettings()
            }
            saveProfiles()
            refreshFailoverAfterProfileChange()
        }
        return ImportSummary(
            added: added,
            duplicates: duplicates,
            failed: parse.errors,
            firstAddedID: firstAddedID
        )
    }

    /// Inline rename — keeps focus and existing selection state in the view.
    func rename(profileID id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let idx = profiles.firstIndex(where: { $0.id == id }), !trimmed.isEmpty else { return }
        profiles[idx].name = trimmed
        saveProfiles()
    }

    func start() async {
        listenerStartedForPingOnly = false
        pauseError = nil
        if !isFailingOver { failoverMessage = nil }
        if !isRecoveringNetwork {
            networkRecoveryMessage = nil
            networkRecoveryAttempts = 0
        }
        saveSettings()
        saveProfiles()
        saveListenerProject()

        guard let profile = activeProfile else {
            status = .error("No profile selected. Import one in Profiles.")
            return
        }

        let wantedSocks = settings.listenPort
        let freeSocks = PortAvailability.firstAvailable(
            preferred: wantedSocks,
            host: settings.listenHost,
            range: 2079 ... 21_999
        )
        if freeSocks != wantedSocks {
            settings.listenPort = freeSocks
            saveSettings()
        }
        let wantedHTTP = settings.httpPort == settings.listenPort ? settings.listenPort + 1000 : settings.httpPort
        let freeHTTP = PortAvailability.firstAvailable(
            preferred: wantedHTTP,
            host: settings.listenHost,
            range: 3079 ... 31_999
        )
        if freeHTTP != settings.httpPort {
            settings.httpPort = freeHTTP
            saveSettings()
        }

        status = .starting

        do {
            // One admin prompt installs both helpers (listener + proxy toggle).
            if !SudoPrivilege.isInstalled() {
                try SudoPrivilege.install()
                privilegesInstalled = true
            }

            // Reap any orphan cloak-core left behind by a previous crash/force-quit
            // — otherwise the new listener fails to bind LISTEN_PORT (EADDRINUSE)
            // and xray ends up dialing the dead orphan, producing a wall of EOFs.
            SudoPrivilege.killLeftoverListener()

            try python.start(config: listenerProject)

            try await awaitListenerReady()

            let xdata = try XrayOutboundBuilder.generate(
                settings: settings,
                profile: profile,
                bridge: listenerProject,
                directInterface: try tunnelDirectInterface()
            )
            let cfgURL = try store.writeGeneratedXrayConfig(xdata)

            try xray.start(configURL: cfgURL)

            // Give xray a beat to open its SOCKS port before flipping the
            // system proxy onto it — otherwise the first wave of system
            // traffic races the listener coming up and looks like a failure.
            try await Task.sleep(nanoseconds: 400_000_000)

            // Wait for xray's local SOCKS port to start accepting connections
            // before flipping the system proxy onto it. We intentionally do NOT
            // gate the connection on an end-to-end HTTP probe: slow paths (e.g.
            // SNI-spoofing through Cloudflare) can take seconds for the first
            // request, and a strict pre-flight probe made healthy-but-slow
            // profiles fail to connect (regressed in 1.1.5). Live reachability is
            // shown by the dashboard ping instead.
            let socksProbeHost = settings.resolvedSocksHostForLocalClient
            let socksProbePort = UInt16(clamping: settings.listenPort)
            var xrayPortReady = false
            for _ in 0 ..< 25 { // ~5s max
                if Task.isCancelled { break }
                if await RealPingService.ping(host: socksProbeHost, port: socksProbePort, timeout: 1).millis != nil {
                    xrayPortReady = true
                    break
                }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            guard xrayPortReady else {
                throw NSError(
                    domain: "SNISpoofing",
                    code: 41,
                    userInfo: [NSLocalizedDescriptionKey: "Xray's local proxy port didn't come up. Open Logs for details."]
                )
            }

            try activateRouting()
            // NWPath reports our own utun route takeover. Ignore that expected
            // transition so it cannot be mistaken for a physical network change.
            ignoreNetworkChangesUntil = Date().addingTimeInterval(8)

            startedAt = Date()
            if let c = NetworkCounters.totalRXTXBytes() {
                sessionBaselineRx = c.rx
                sessionBaselineTx = c.tx
            } else {
                sessionBaselineRx = 0
                sessionBaselineTx = 0
            }
            sessionBytesDown = 0
            sessionBytesUp = 0
            status = .running
            scheduleEgressRefresh()
            startBandwidthSampler()
            startFailoverMonitor()
            startRouteWatchdog()
        } catch {
            if systemProxyActive {
                SystemProxy.disableSync()
                systemProxyActive = false
            }
            if tunnelActive {
                packetTunnel.stop()
                tunnelActive = false
            }
            await stopInternal()
            status = .error(error.localizedDescription)
            startedAt = nil
            clearEgress()
        }
    }

    func stop() async {
        if !isRecoveringNetwork { cancelPendingNetworkRecovery() }
        stopRouteWatchdog()
        stopFailoverMonitor()
        if !isFailingOver { failoverMessage = nil }
        status = .stopping
        await stopInternal()
        startedAt = nil
        clearEgress()
        downloadBytesPerSec = 0
        uploadBytesPerSec = 0
        sessionBytesDown = 0
        sessionBytesUp = 0
        bandwidthTimer?.invalidate()
        bandwidthTimer = nil
        status = .stopped
    }

    func pause() async {
        guard status.isRunning else { return }
        if !isRecoveringNetwork { cancelPendingNetworkRecovery() }
        stopRouteWatchdog()
        stopFailoverMonitor()
        status = .pausing
        pauseError = nil
        // Stop intercepting traffic before closing Xray so macOS immediately
        // falls back to its normal direct connection instead of a dead proxy.
        deactivateRouting()
        await xray.stop()
        downloadBytesPerSec = 0
        uploadBytesPerSec = 0
        clearEgress()
        status = .paused
    }

    func resume() async {
        guard status.isPaused else { return }
        guard let profile = activeProfile else {
            pauseError = "The active profile is no longer available."
            return
        }

        status = .resuming
        pauseError = nil
        do {
            let xdata = try XrayOutboundBuilder.generate(
                settings: settings,
                profile: profile,
                bridge: listenerProject,
                directInterface: try tunnelDirectInterface()
            )
            let cfgURL = try store.writeGeneratedXrayConfig(xdata)
            try xray.start(configURL: cfgURL)
            try await awaitXrayReady()
            try activateRouting()
            ignoreNetworkChangesUntil = Date().addingTimeInterval(8)
            status = .running
            scheduleEgressRefresh()
            startFailoverMonitor()
            startRouteWatchdog()
        } catch {
            deactivateRouting()
            await xray.stop()
            pauseError = error.localizedDescription
            status = .paused
        }
    }

    private func stopInternal() async {
        deactivateRouting()
        await xray.stop()
        python.stop()
    }

    private func activateRouting() throws {
        if settings.connectionMode == .tunnel {
            store.saveActiveNetworkSession(tunnel: true, systemProxy: false)
            // Clear any system proxy left over from a previous proxy-mode session
            // so browsers don't bypass the TUN device and use the old HTTP proxy.
            SystemProxy.disableSync()
            systemProxyActive = false
            let params = PacketTunnelManager.StartParameters(
                connectIP: listenerProject.CONNECT_IP,
                socksHost: "127.0.0.1",
                socksPort: settings.listenPort,
                logLevel: settings.logLevel == .debug || settings.logLevel == .trace ? "debug" : "info",
                excludedIPv4Routes: XrayOutboundBuilder.tunnelBypassIPv4Routes(settings)
            )
            try packetTunnel.start(parameters: params)
            tunnelActive = true
        } else if settings.useSystemProxy {
            store.saveActiveNetworkSession(tunnel: false, systemProxy: true)
            let host = settings.resolvedSocksHostForLocalClient
            switch SystemProxy.enable(host: host, socksPort: settings.listenPort, httpPort: settings.httpPort) {
            case .ok:
                systemProxyActive = true
            case .failed(let msg):
                SystemProxy.disableSync()
                throw NSError(
                    domain: "SNISpoofing",
                    code: 23,
                    userInfo: [NSLocalizedDescriptionKey: "Couldn't flip the system proxy on: \(msg)"]
                )
            }
        } else {
            store.clearActiveNetworkSession()
        }
    }

    private func tunnelDirectInterface() throws -> String? {
        guard settings.connectionMode == .tunnel, settings.bypassEnabled else { return nil }
        guard let interface = PacketTunnelManager.defaultPhysicalInterface() else {
            throw NSError(
                domain: "SNISpoofing",
                code: 77,
                userInfo: [NSLocalizedDescriptionKey: "Veil couldn't identify the physical network interface required for Tunnel bypass rules."]
            )
        }
        return interface
    }

    private func deactivateRouting() {
        var networkClean = true
        if tunnelActive {
            networkClean = packetTunnel.stopAndReport()
            tunnelActive = false
        }
        if systemProxyActive {
            if case .failed = SystemProxy.disable() { networkClean = false }
            systemProxyActive = false
        }
        if networkClean { store.clearActiveNetworkSession() }
    }

    private func recoverStaleNetworkState() {
        guard let session = store.loadActiveNetworkSession() else {
            isRestoringNetworkState = false
            return
        }

        var clean = true
        if session.tunnel {
            if FileManager.default.isExecutableFile(atPath: SudoPrivilege.tunHelperPath) {
                clean = packetTunnel.stopAndReport() && clean
            } else {
                clean = false
            }
        }
        if session.systemProxy {
            if FileManager.default.isExecutableFile(atPath: SudoPrivilege.proxyHelperPath) {
                clean = SudoPrivilege.runProxyHelper(["disable"]) == 0 && clean
            } else {
                clean = false
            }
        }
        SudoPrivilege.killLeftoverListener()

        if clean {
            store.clearActiveNetworkSession()
            networkRecoveryMessage = "Recovered network state from the previous session."
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if self?.networkRecoveryMessage == "Recovered network state from the previous session." {
                    self?.networkRecoveryMessage = nil
                }
            }
        } else {
            networkRecoveryMessage = "Previous network state could not be fully restored. Reinstall the helper in Settings."
        }
        isRestoringNetworkState = false
    }

    private func awaitXrayReady() async throws {
        let host = settings.resolvedSocksHostForLocalClient
        let port = UInt16(clamping: settings.listenPort)
        for _ in 0 ..< 25 {
            if await RealPingService.ping(host: host, port: port, timeout: 1).millis != nil { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        throw NSError(
            domain: "SNISpoofing",
            code: 41,
            userInfo: [NSLocalizedDescriptionKey: "Xray's local proxy port didn't come up. Open Logs for details."]
        )
    }

    // MARK: - Automatic profile failover

    func configureFailoverMonitoring() {
        saveSettings()
        if settings.autoFailoverEnabled, status.isRunning {
            startFailoverMonitor()
        } else {
            stopFailoverMonitor()
            failoverMessage = nil
        }
    }

    private func startFailoverMonitor() {
        failoverTask?.cancel()
        failoverTask = nil
        consecutiveHealthFailures = 0
        guard settings.autoFailoverEnabled, status.isRunning, profiles.count > 1,
              !isFailingOver, !isRecoveringNetwork else { return }

        failoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            while !Task.isCancelled {
                guard let self else { return }
                await self.runFailoverHealthCheck()
                if Task.isCancelled || self.isFailingOver { return }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    private func stopFailoverMonitor() {
        failoverTask?.cancel()
        failoverTask = nil
        consecutiveHealthFailures = 0
    }

    private func runFailoverHealthCheck() async {
        guard settings.autoFailoverEnabled, status.isRunning, !isFailingOver else { return }
        guard profiles.count > 1, settings.activeProfileID != nil else {
            stopFailoverMonitor()
            return
        }
        let result = await RealPingService.pingViaSocks(
            proxyHost: settings.resolvedSocksHostForLocalClient,
            proxyPort: settings.listenPort,
            timeout: 6
        )

        if let activeID = settings.activeProfileID, result.millis != nil {
            profilePingResults[activeID] = result
            persistPingResults()
            consecutiveHealthFailures = 0
            failoverMessage = nil
            return
        }

        consecutiveHealthFailures += 1
        failoverMessage = "Connection check failed \(consecutiveHealthFailures)/3"
        guard consecutiveHealthFailures >= 3 else { return }
        if let activeID = settings.activeProfileID {
            profilePingResults[activeID] = result
            persistPingResults()
        }
        await performAutomaticFailover()
    }

    private func performAutomaticFailover() async {
        guard !isFailingOver, let originalID = settings.activeProfileID else { return }
        isFailingOver = true
        // Detach this operation from the monitor before stop() cancels its task.
        failoverTask = nil

        let candidates = profiles
            .filter { $0.id != originalID }
            .sorted { lhs, rhs in
                let left = profilePingResults[lhs.id]?.millis ?? Int.max
                let right = profilePingResults[rhs.id]?.millis ?? Int.max
                if left == right { return lhs.name.localizedCompare(rhs.name) == .orderedAscending }
                return left < right
            }

        await stop()

        for candidate in candidates {
            if Task.isCancelled { break }
            failoverMessage = "Trying \(candidate.name)..."
            settings.activeProfileID = candidate.id
            saveSettings()
            await start()
            guard status.isRunning else { continue }

            let result = await RealPingService.pingViaSocks(
                proxyHost: settings.resolvedSocksHostForLocalClient,
                proxyPort: settings.listenPort,
                timeout: 10
            )
            profilePingResults[candidate.id] = result
            persistPingResults()
            if result.millis != nil {
                failoverMessage = "Switched to \(candidate.name)"
                isFailingOver = false
                startFailoverMonitor()
                return
            }
            await stop()
        }

        settings.activeProfileID = originalID
        saveSettings()
        if status.isSessionActive || status.isTransitioning { await stop() }
        isFailingOver = false
        consecutiveHealthFailures = 0
        failoverMessage = "No working backup profile was found."
        status = .error("Automatic failover couldn't find a working profile.")
    }

    private func refreshFailoverAfterProfileChange() {
        guard status.isRunning else { return }
        startFailoverMonitor()
    }

    // MARK: - Physical network recovery

    func configureNetworkRecovery() {
        saveSettings()
        guard settings.networkRecoveryEnabled else {
            networkRecoveryTask?.cancel()
            networkRecoveryTask = nil
            networkRecoveryPending = false
            recoverAfterWake = false
            networkRecoveryMessage = nil
            return
        }
    }

    private func handleNetworkEvent(_ event: NetworkChangeMonitor.Event) {
        guard settings.networkRecoveryEnabled else { return }
        switch event {
        case .unavailable:
            physicalNetworkAvailable = false
            if status.isRunning || isRecoveringNetwork {
                networkRecoveryPending = true
                networkRecoveryMessage = "Waiting for a network connection..."
                stopFailoverMonitor()
            }
        case .changed(let summary):
            physicalNetworkAvailable = true
            // Route changes caused by our own stop/start are expected. A real
            // outage is tracked separately by `.unavailable`, which sets the
            // pending flag and is handled after the current recovery finishes.
            guard !isRecoveringNetwork else { return }
            guard Date() >= ignoreNetworkChangesUntil || networkRecoveryPending else { return }
            guard status.isRunning || networkRecoveryPending || recoverAfterWake else { return }
            networkRecoveryAttempts = 0
            scheduleNetworkRecovery(on: summary, delay: 2.5)
        case .willSleep:
            recoverAfterWake = status.isRunning
            if recoverAfterWake {
                networkRecoveryMessage = "Sleeping; route recovery is armed."
                stopFailoverMonitor()
            }
        case .didWake:
            guard recoverAfterWake || status.isRunning else { return }
            networkRecoveryPending = true
            networkRecoveryAttempts = 0
            networkRecoveryMessage = "Waiting for the network after wake..."
            scheduleNetworkRecovery(on: "wake", delay: 4)
        }
    }

    private func scheduleNetworkRecovery(on network: String, delay: TimeInterval) {
        networkRecoveryTask?.cancel()
        networkRecoveryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard let self, !Task.isCancelled, self.physicalNetworkAvailable else { return }
            await self.recoverConnection(on: network)
        }
    }

    private func recoverConnection(on network: String, force: Bool = false) async {
        guard (settings.networkRecoveryEnabled || force), !isRecoveringNetwork else { return }
        guard status.isRunning || networkRecoveryPending || recoverAfterWake else { return }

        isRecoveringNetwork = true
        networkRecoveryAttempts += 1
        networkRecoveryPending = false
        recoverAfterWake = false
        networkRecoveryMessage = network == "wake"
            ? "Restoring the route after wake..."
            : "Adapting the route to \(network)..."
        stopFailoverMonitor()
        ignoreNetworkChangesUntil = Date().addingTimeInterval(10)

        if status.isSessionActive || status.isTransitioning {
            await stop()
        }
        await start()

        isRecoveringNetwork = false
        if status.isRunning {
            networkRecoveryAttempts = 0
            let success = network == "wake" ? "Route restored after wake." : "Reconnected on \(network)."
            networkRecoveryMessage = success
            startFailoverMonitor()
            startRouteWatchdog()
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if self?.networkRecoveryMessage == success {
                    self?.networkRecoveryMessage = nil
                }
            }
        } else {
            networkRecoveryMessage = physicalNetworkAvailable
                ? "Network recovery failed: \(status.label)"
                : "Waiting for a network connection..."
            networkRecoveryPending = !physicalNetworkAvailable
        }

        if networkRecoveryPending, physicalNetworkAvailable {
            scheduleNetworkRecovery(on: network, delay: 2)
        } else if !status.isRunning, physicalNetworkAvailable, networkRecoveryAttempts < 3 {
            networkRecoveryPending = true
            scheduleNetworkRecovery(on: network, delay: 3)
        }
    }

    private func cancelPendingNetworkRecovery() {
        networkRecoveryTask?.cancel()
        networkRecoveryTask = nil
        networkRecoveryPending = false
        recoverAfterWake = false
        networkRecoveryAttempts = 0
        networkRecoveryMessage = nil
    }

    // MARK: - Route integrity watchdog

    private func startRouteWatchdog() {
        stopRouteWatchdog()
        guard status.isRunning, settings.connectionMode == .tunnel else { return }

        routeWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            while !Task.isCancelled {
                guard let self, self.status.isRunning, !self.isRecoveringNetwork else { return }
                let manager = self.packetTunnel
                let result = await Task.detached(priority: .utility) {
                    manager.repairRoutes()
                }.value
                guard !Task.isCancelled else { return }

                if result.ok {
                    self.routeRepairFailures = 0
                    self.routeIntegrityMessage = nil
                } else {
                    self.routeRepairFailures += 1
                    self.routeIntegrityMessage = "Tunnel route repair failed \(self.routeRepairFailures)/2"
                    if self.routeRepairFailures >= 2 {
                        self.routeWatchdogTask = nil
                        self.networkRecoveryPending = true
                        self.networkRecoveryMessage = "Rebuilding damaged tunnel routes..."
                        await self.recoverConnection(on: "route integrity", force: true)
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 12_000_000_000)
            }
        }
    }

    private func stopRouteWatchdog() {
        routeWatchdogTask?.cancel()
        routeWatchdogTask = nil
        routeRepairFailures = 0
        routeIntegrityMessage = nil
    }

    // MARK: - Bandwidth sampler

    private var bandwidthTimer: Timer?
    private var lastBytesIn: UInt64 = 0
    private var lastBytesOut: UInt64 = 0
    private var lastSampleAt: Date?

    private func startBandwidthSampler() {
        bandwidthTimer?.invalidate()
        lastBytesIn = 0
        lastBytesOut = 0
        lastSampleAt = nil
        bandwidthTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleBandwidth() }
        }
    }

    private func sampleBandwidth() {
        guard status.isRunning else { return }
        
        // Only sample and display data exchange activity if the connection is actually healthy (egress IP is resolved)
        guard egressIP != nil else {
            downloadBytesPerSec = 0
            uploadBytesPerSec = 0
            if let counters = NetworkCounters.totalRXTXBytes() {
                sessionBaselineRx = counters.rx
                sessionBaselineTx = counters.tx
                lastBytesIn = counters.rx
                lastBytesOut = counters.tx
            }
            sessionBytesDown = 0
            sessionBytesUp = 0
            lastSampleAt = Date()
            return
        }

        guard let counters = NetworkCounters.totalRXTXBytes() else { return }
        sessionBytesDown = counters.rx >= sessionBaselineRx ? counters.rx - sessionBaselineRx : 0
        sessionBytesUp = counters.tx >= sessionBaselineTx ? counters.tx - sessionBaselineTx : 0
        let now = Date()
        if let last = lastSampleAt {
            let dt = max(0.2, now.timeIntervalSince(last))
            let dIn = counters.rx > lastBytesIn ? Double(counters.rx - lastBytesIn) : 0
            let dOut = counters.tx > lastBytesOut ? Double(counters.tx - lastBytesOut) : 0
            downloadBytesPerSec = dIn / dt
            uploadBytesPerSec = dOut / dt
        }
        lastBytesIn = counters.rx
        lastBytesOut = counters.tx
        lastSampleAt = now
    }

    // MARK: - Profile ping (listener + xray through SOCKS)

    /// TCP target for probing `LISTEN_HOST` (NWConnection cannot use `0.0.0.0`).
    static func resolvedPingHost(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty || t == "0.0.0.0" || t == "*" { return "127.0.0.1" }
        if t == "localhost" { return "127.0.0.1" }
        if t == "::" { return "::1" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func persistPingResults() {
        store.savePingResults(profilePingResults)
    }

    func cancelPingBatch() {
        pingBatchToken = nil
        pingBatchTask?.cancel()
        pingBatchTask = nil
        isPingBatchRunning = false
        profilePingingIDs.removeAll()
    }

    /// Tests every profile. Uses one shared listener and multiple temporary Xray
    /// workers on separate local ports so disconnected batch probes can run in parallel.
    func startPingAllProfiles() {
        guard !status.isPaused else { return }
        cancelPingBatch()
        let token = UUID()
        pingBatchToken = token
        isPingBatchRunning = true
        profilePingingIDs = Set(profiles.map(\.id))

        pingBatchTask = Task { @MainActor in
            defer {
                if pingBatchToken == token {
                    isPingBatchRunning = false
                    profilePingingIDs.removeAll()
                    pingBatchToken = nil
                }
            }

            let list = profiles
            guard !list.isEmpty else { return }

            if status.isRunning {
                for p in list {
                    guard pingBatchToken == token, !Task.isCancelled else { break }
                    let r = await pingProfile(p)
                    profilePingResults[p.id] = r
                    profilePingingIDs.remove(p.id)
                    persistPingResults()
                }
                return
            }

            var listenerStarted = false
            defer {
                if listenerStarted, !status.isRunning {
                    python.stop()
                    listenerStartedForPingOnly = false
                }
            }

            do {
                try prepareListenerForPingBatch()
                listenerStarted = true
                try await awaitListenerReady()
            } catch {
                let err = RealPingService.Result(millis: nil, error: shortPingError(error))
                for p in list {
                    profilePingResults[p.id] = err
                    profilePingingIDs.remove(p.id)
                }
                persistPingResults()
                return
            }

            await pingProfilesViaBatch(list, token: token)
        }
    }

    func pingSingleProfile(_ profile: Profile) async {
        guard !status.isPaused else { return }
        guard !profilePingingIDs.contains(profile.id) else { return }
        profilePingingIDs.insert(profile.id)
        let r = await pingProfile(profile)
        profilePingResults[profile.id] = r
        profilePingingIDs.remove(profile.id)
        persistPingResults()
    }

    private func prepareListenerForPingBatch() throws {
        saveListenerProject()
        if !SudoPrivilege.isInstalled() {
            try SudoPrivilege.install()
            privilegesInstalled = true
        }
        if !python.isRunning() {
            SudoPrivilege.killLeftoverListener()
            try python.start(config: listenerProject)
            listenerStartedForPingOnly = true
        }
    }

    /// Ping while listener is already up (batch path): run temporary Xray workers in parallel.
    private func pingProfilesViaBatch(_ list: [Profile], token: UUID) async {
        let portPairs = temporaryPingPorts(count: list.count)
        let jobs = list.enumerated().map { offset, profile in
            (
                profile: profile,
                ports: offset < portPairs.count ? portPairs[offset] : nil
            )
        }
        let workerCount = max(1, min(Self.maxConcurrentPingWorkers, jobs.count))
        var nextJobIndex = 0
        let baseSettings = settings
        let bridge = listenerProject

        await withTaskGroup(of: (UUID, RealPingService.Result).self) { group in
            func addNextJob() {
                guard nextJobIndex < jobs.count else { return }
                let job = jobs[nextJobIndex]
                nextJobIndex += 1

                group.addTask {
                    guard let ports = job.ports else {
                        return (job.profile.id, RealPingService.Result(millis: nil, error: "no port"))
                    }
                    let result = await Self.pingProfileViaTemporaryXray(
                        profile: job.profile,
                        baseSettings: baseSettings,
                        bridge: bridge,
                        socksPort: ports.socks,
                        httpPort: ports.http
                    )
                    return (job.profile.id, result)
                }
            }

            for _ in 0 ..< workerCount {
                addNextJob()
            }

            while let (id, result) = await group.next() {
                guard pingBatchToken == token, !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                profilePingResults[id] = result
                profilePingingIDs.remove(id)
                persistPingResults()
                addNextJob()
            }
        }
    }

    private func temporaryPingPorts(count: Int) -> [(socks: Int, http: Int)] {
        guard count > 0 else { return [] }
        var out: [(socks: Int, http: Int)] = []
        var used = Set([settings.listenPort, settings.httpPort, listenerProject.LISTEN_PORT])
        var port = 32_000

        while out.count < count, port < 65_534 {
            let socks = port
            let http = port + 1
            if !used.contains(socks),
               !used.contains(http),
               PortAvailability.isAvailable(port: socks, host: "127.0.0.1"),
               PortAvailability.isAvailable(port: http, host: "127.0.0.1") {
                out.append((socks, http))
                used.insert(socks)
                used.insert(http)
            }
            port += 2
        }

        return out
    }

    nonisolated private static func pingProfileViaTemporaryXray(
        profile: Profile,
        baseSettings: AppSettings,
        bridge: ListenerProjectConfig,
        socksPort: Int,
        httpPort: Int
    ) async -> RealPingService.Result {
        let xray = XrayCoreManager()
        let cfgURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloak-xray-ping-\(profile.id.uuidString)-\(UUID().uuidString).json")
        defer {
            xray.stopSync()
            try? FileManager.default.removeItem(at: cfgURL)
        }

        do {
            var probeSettings = baseSettings
            probeSettings.listenHost = "127.0.0.1"
            probeSettings.listenPort = socksPort
            probeSettings.httpPort = httpPort
            probeSettings.useSystemProxy = false
            probeSettings.connectionMode = .proxy

            let xdata = try XrayOutboundBuilder.generate(
                settings: probeSettings,
                profile: profile,
                bridge: bridge
            )
            try xdata.write(to: cfgURL, options: .atomic)
            try xray.start(configURL: cfgURL)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return await RealPingService.pingViaSocks(proxyHost: "127.0.0.1", proxyPort: socksPort)
        } catch {
            let msg = error.localizedDescription
            return RealPingService.Result(
                millis: nil,
                error: msg.isEmpty ? "failed" : String(msg.prefix(48))
            )
        }
    }

    /// Brings up the Python listener and Xray for `profile`, measures latency through
    /// the local SOCKS hop, then tears down anything started only for this probe.
    func pingProfile(_ profile: Profile) async -> RealPingService.Result {
        if status.isPaused {
            return RealPingService.Result(millis: nil, error: "resume first")
        }
        let socksHost = settings.resolvedSocksHostForLocalClient
        let socksPort = settings.listenPort

        if status.isRunning {
            guard activeProfile?.id == profile.id else {
                return RealPingService.Result(millis: nil, error: "disconnect first")
            }
            return await RealPingService.pingViaSocks(proxyHost: socksHost, proxyPort: socksPort)
        }

        var startedListener = false
        var startedXray = false
        defer {
            if startedXray { xray.stopSync() }
            if startedListener {
                python.stop()
                listenerStartedForPingOnly = false
            }
        }

        do {
            saveListenerProject()
            if !SudoPrivilege.isInstalled() {
                try SudoPrivilege.install()
                privilegesInstalled = true
            }
            if !python.isRunning() {
                SudoPrivilege.killLeftoverListener()
                try python.start(config: listenerProject)
                listenerStartedForPingOnly = true
                startedListener = true
            }
            try await awaitListenerReady()

            let xdata = try XrayOutboundBuilder.generate(
                settings: settings,
                profile: profile,
                bridge: listenerProject
            )
            let cfgURL = try store.writeGeneratedXrayConfig(xdata)
            try xray.start(configURL: cfgURL)
            startedXray = true
            try await Task.sleep(nanoseconds: 1_200_000_000)

            return await RealPingService.pingViaSocks(proxyHost: socksHost, proxyPort: socksPort)
        } catch {
            return RealPingService.Result(millis: nil, error: shortPingError(error))
        }
    }

    private func shortPingError(_ error: Error) -> String {
        let msg = error.localizedDescription
        if msg.count > 48 { return String(msg.prefix(45)) + "…" }
        return msg.isEmpty ? "failed" : msg
    }

    private func awaitListenerReady() async throws {
        let host = listenerProject.LISTEN_HOST
        let port = listenerProject.LISTEN_PORT
        guard port > 0, port <= 65_535 else {
            throw NSError(
                domain: "SNISpoofing",
                code: 32,
                userInfo: [NSLocalizedDescriptionKey: "Local listener port is invalid."]
            )
        }

        for _ in 0 ..< 80 {
            if !python.isRunning() {
                throw NSError(
                    domain: "SNISpoofing",
                    code: 31,
                    userInfo: [NSLocalizedDescriptionKey: "Veil's local listener stopped while starting. Try again; Veil cleans up the helper before the next start."]
                )
            }
            if !PortAvailability.isAvailable(port: port, host: host) {
                try await Task.sleep(nanoseconds: 250_000_000)
                if python.isRunning() { return }
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw NSError(
            domain: "SNISpoofing",
            code: 30,
            userInfo: [NSLocalizedDescriptionKey: "Veil couldn't bring up its local listener in time. Try again; stale helpers are cleaned up automatically."]
        )
    }

    func clearLogs() { logs.removeAll() }

    func refreshEgressNow() {
        scheduleEgressRefresh()
    }

    private func clearEgress() {
        egressIP = nil
        egressCountry = nil
        egressCity = nil
        egressLat = nil
        egressLon = nil
        egressLookupMessage = nil
    }

    private func scheduleEgressRefresh() {
        egressLookupMessage = "Resolving egress…"
        egressIP = nil
        egressCountry = nil
        egressCity = nil
        egressLat = nil
        egressLon = nil
        let host = settings.resolvedSocksHostForLocalClient
        let port = settings.listenPort
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await self?.runEgressLookup(proxyHost: host, proxyPort: port)
        }
    }

    /// Restart the stack to pick up a settings change (port, proxy toggle, etc.).
    func reconnectIfRunning() async {
        guard status.isRunning, !isFailingOver, !isRecoveringNetwork else { return }
        await stop()
        await start()
    }

    private func runEgressLookup(proxyHost: String, proxyPort: Int) async {
        let maxAttempts = 2
        for attempt in 0 ..< maxAttempts {
            guard status.isRunning else { return }
            do {
                let r = try await EgressInfoService.fetchEgress(proxyHost: proxyHost, proxyPort: proxyPort)
                guard status.isRunning else { return }
                egressIP = r.ip
                egressCountry = r.country
                egressCity = r.city
                egressLat = r.latitude
                egressLon = r.longitude
                egressLookupMessage = nil
                return
            } catch {
                if attempt < maxAttempts - 1 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                } else if status.isRunning {
                    egressLookupMessage = error.localizedDescription
                }
            }
        }
    }
}

struct LogLine: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let stream: Stream
    let text: String
    enum Stream { case stdout, stderr, system }
}
