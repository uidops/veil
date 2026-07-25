import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var uptime: String = "0s"
    @State private var timer: Timer?
    @State private var lanIPv4: String?
    @State private var copiedLan = false

    var body: some View {
        GeometryReader { geo in
            let scale = dashboardScale(for: geo.size)
            VStack(alignment: .leading, spacing: 14) {
                dashboardHeader
                vpnHeroGrid
                dashboardSection("Network", detail: "Local access and routing mode")
                if let lan = lanIPv4 {
                    HStack(alignment: .top, spacing: 10) {
                        lanCard(lan).frame(maxWidth: .infinity, alignment: .top)
                        SystemProxyCard().frame(maxWidth: .infinity, alignment: .top)
                    }
                } else {
                    SystemProxyCard()
                }
            }
            .padding(.bottom, 4)
            .frame(width: geo.size.width / scale, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
        }
        .onAppear {
            startTimer()
            refreshLanIP()
        }
        .onDisappear { stopTimer() }
        .onChange(of: app.startedAt) { _ in tick() }
    }

    /// Keep the dashboard as one non-scrolling canvas and resize the complete
    /// composition, including controls and type, with the available viewport.
    private func dashboardScale(for size: CGSize) -> CGFloat {
        let widthScale = size.width / 980
        let heightScale = size.height / 690
        return min(1, max(0.58, min(widthScale, heightScale)))
    }

    // MARK: - Status card

    private var dashboardHeader: some View {
        ScreenHeader(
            eyebrow: "Private connection",
            title: "Your route, at a glance",
            subtitle: "One control for privacy. The details stay out of your way until you need them."
        ) {
            HStack(spacing: 8) {
                Circle()
                    .fill(app.status.isRunning ? Color.green : (app.status.isPaused ? Color.orange : Color.secondary))
                    .frame(width: 7, height: 7)
                Text(app.settings.connectionMode == .tunnel ? "FULL TUNNEL" : "SYSTEM PROXY")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .tracking(0.8)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(AppTheme.subtleFill(for: colorScheme)))
            .overlay(Capsule().stroke(AppTheme.faintStroke(for: colorScheme)))
        }
    }

    private var vpnHeroGrid: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                minimalVPNCard
                    .frame(maxWidth: .infinity)
                liveSessionCard
                    .frame(width: 310)
            }
            VStack(spacing: 16) {
                minimalVPNCard
                liveSessionCard
            }
        }
    }

    private var minimalVPNCard: some View {
        Card(padding: 22) {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.settings.connectionMode == .tunnel ? "FULL DEVICE" : "SYSTEM PROXY")
                            .font(.system(size: 8.5, weight: .black, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                        Text(app.activeProfile?.name ?? "No profile selected")
                            .font(.system(size: 12.5, weight: .bold))
                            .lineLimit(1)
                    }
                    Spacer()
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: connectionColor.opacity(0.45), radius: 5)
                }

                Spacer(minLength: 0)

                Button {
                    Task {
                        if app.status.isSessionActive { await app.stop() }
                        else { await app.start() }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(AppTheme.stroke(for: colorScheme), lineWidth: 1)
                            .frame(width: 158, height: 158)
                        Circle()
                            .fill(connectionColor.opacity(app.status.isSessionActive ? 0.16 : 0.08))
                            .frame(width: 138, height: 138)
                        Circle()
                            .fill(AppTheme.elevatedFill(for: colorScheme))
                            .frame(width: 106, height: 106)
                            .shadow(color: connectionColor.opacity(app.status.isSessionActive ? 0.28 : 0.10), radius: 20)
                        if app.status.isTransitioning {
                            ProgressView()
                                .controlSize(.large)
                                .tint(connectionColor)
                        } else {
                            Image(systemName: app.status.isSessionActive ? "stop.fill" : "power")
                                .font(.system(size: 31, weight: .medium))
                                .foregroundStyle(connectionColor)
                        }
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(app.status.isTransitioning || app.isFailingOver || app.isRecoveringNetwork || app.isRestoringNetworkState || (app.activeProfile == nil && !app.status.isSessionActive))
                .opacity(app.activeProfile == nil && !app.status.isSessionActive ? 0.45 : 1)

                VStack(spacing: 4) {
                    Text(app.status.label)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                    Text(minimalStatusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                if app.status.isSessionActive {
                    Button {
                        Task {
                            if app.status.isPaused { await app.resume() }
                            else { await app.pause() }
                        }
                    } label: {
                        Label(app.status.isPaused ? "Resume protected route" : "Pause and use direct internet",
                              systemImage: app.status.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(app.status.isTransitioning || app.isFailingOver || app.isRecoveringNetwork)
                } else {
                    Text("Click to connect")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(.tertiary)
                }

                Divider().opacity(0.6)

                VStack(alignment: .leading, spacing: 14) {
                    Text("CONNECTION ROUTE")
                        .font(.system(size: 10.5, weight: .black, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 12) {
                        minimalRouteNode(symbol: "laptopcomputer", label: "Mac")
                        routeChevron
                        minimalRouteNode(symbol: "cloud.fill", label: "Edge")
                        routeChevron
                        minimalRouteNode(symbol: "server.rack", label: app.activeProfile?.name ?? "Proxy")
                        routeChevron
                        minimalRouteNode(symbol: "globe", label: countryFlag)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(minHeight: 400)
        }
    }

    private var liveSessionCard: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("Live session")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Spacer()
                    Text(app.status.isRunning ? "LIVE" : "IDLE")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(app.status.isRunning ? AppTheme.cyan : Color.secondary)
                }

                HStack(spacing: 10) {
                    Text(countryFlag)
                        .font(.system(size: 25))
                        .frame(width: 38, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(AppTheme.controlFill(for: colorScheme))
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.egressIP ?? "No protected exit")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .lineLimit(1)
                        Text(app.status.isRunning ? "Protected exit" : "Connect to resolve")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 13).fill(AppTheme.controlFill(for: colorScheme)))

                Divider().opacity(0.6)

                sessionLine("Download", value: rate(app.downloadBytesPerSec), detail: formatBytes(app.sessionBytesDown), tint: .blue)
                sessionLine("Upload", value: rate(app.uploadBytesPerSec), detail: formatBytes(app.sessionBytesUp), tint: .purple)
                sessionLine("Duration", value: app.status.isSessionActive ? uptime : "--", detail: formatBytes(app.sessionBytesDown + app.sessionBytesUp), tint: AppTheme.cyan)

                Spacer(minLength: 0)

                ActivityPulseMeter(
                    downValue: app.downloadBytesPerSec,
                    upValue: app.uploadBytesPerSec,
                    peak: peakHint
                )
            }
            .frame(minHeight: 400)
        }
    }

    private func minimalRouteNode(symbol: String, label: String) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(app.status.isRunning ? AppTheme.cyan.opacity(0.12) : AppTheme.controlFill(for: colorScheme))
                    .frame(width: 50, height: 50)
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(app.status.isRunning ? AppTheme.cyan : Color.secondary)
            }
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private var routeChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(app.status.isRunning ? AppTheme.cyan.opacity(0.7) : Color.secondary.opacity(0.45))
            .offset(y: -11)
    }

    private func sessionLine(_ label: String, value: String, detail: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                Text(detail)
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var connectionColor: Color {
        switch app.status {
        case .running: return AppTheme.cyan
        case .paused: return .orange
        case .starting, .pausing, .resuming, .stopping: return .yellow
        case .error: return AppTheme.indigo
        case .stopped: return .secondary
        }
    }

    private var minimalStatusMessage: String {
        if let message = app.networkRecoveryMessage { return message }
        if let message = app.routeIntegrityMessage { return message }
        if let message = app.failoverMessage { return message }
        switch app.status {
        case .running: return "Your traffic is protected through \(app.activeProfile?.name ?? "Veil")."
        case .paused: return "Veil is ready while your normal internet connection is active."
        case .stopped: return app.activeProfile == nil ? "Choose a profile to begin." : "Ready when you are."
        case .starting: return "Preparing your private route..."
        case .pausing: return "Returning traffic to your normal connection..."
        case .resuming: return "Restoring your private route..."
        case .stopping: return "Closing the protected route..."
        case .error(let message): return message
        }
    }

    private var countryFlag: String {
        guard let country = app.egressCountry, !country.isEmpty else { return "🏳" }
        return flagEmoji(country)
    }

    private var connectionDeck: some View {
        Card(padding: 20) {
            VStack(spacing: 18) {
                HStack(alignment: .center, spacing: 16) {
                    StatusOrb(status: app.status, reduceMotion: app.settings.reduceAnimations)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(app.status.label)
                                .font(.system(size: 23, weight: .black, design: .rounded))
                                .tracking(-0.4)
                            statusTag
                        }
                        Text(secondaryLabel)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 14)
                    if app.status.isRunning {
                        compactEgress
                    }
                    if app.status.isSessionActive {
                        Button {
                            Task {
                                if app.status.isPaused { await app.resume() }
                                else { await app.pause() }
                            }
                        } label: {
                            Label(app.status.isPaused ? "Resume" : "Pause",
                                  systemImage: app.status.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 11.5, weight: .bold))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 9)
                        }
                        .buttonStyle(.bordered)
                        .disabled(app.status.isTransitioning)
                    }
                    PowerButton(isRunning: app.status.isSessionActive,
                                isBusy: app.status.isTransitioning) {
                        Task {
                            if app.status.isSessionActive { await app.stop() }
                            else { await app.start() }
                        }
                    }
                    .disabled(app.activeProfile == nil && !app.status.isSessionActive)
                    .opacity(app.activeProfile == nil && !app.status.isSessionActive ? 0.5 : 1)
                }

                Divider().opacity(0.65)

                HStack(spacing: 12) {
                    deckMetric(
                        symbol: "arrow.down.right",
                        label: "DOWNLOAD",
                        value: rate(app.downloadBytesPerSec),
                        detail: formatBytes(app.sessionBytesDown),
                        tint: .blue
                    )
                    deckMetric(
                        symbol: "arrow.up.right",
                        label: "UPLOAD",
                        value: rate(app.uploadBytesPerSec),
                        detail: formatBytes(app.sessionBytesUp),
                        tint: .purple
                    )
                    deckMetric(
                        symbol: "clock",
                        label: "SESSION",
                        value: app.status.isSessionActive ? uptime : "--",
                        detail: formatBytes(app.sessionBytesDown + app.sessionBytesUp),
                        tint: AppTheme.cyan
                    )
                    Divider().frame(height: 42)
                    ActivityPulseMeter(
                        downValue: app.downloadBytesPerSec,
                        upValue: app.uploadBytesPerSec,
                        peak: peakHint
                    )
                    .frame(minWidth: 245)
                }
            }
        }
    }

    private func dashboardSection(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(1.1)
            Text(detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
            Rectangle()
                .fill(AppTheme.stroke(for: colorScheme))
                .frame(width: 54, height: 1)
        }
        .padding(.top, 3)
        .padding(.horizontal, 2)
    }

    private var statusTag: some View {
        Text(app.status.isRunning ? "ROUTED" : (app.status.isPaused ? "DIRECT" : "STANDBY"))
            .font(.system(size: 8.5, weight: .black, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(app.status.isRunning ? AppTheme.cyan : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(AppTheme.subtleFill(for: colorScheme)))
    }

    private var compactEgress: some View {
        HStack(spacing: 9) {
            IconTile(symbol: "globe.americas.fill", tint: AppTheme.cyan, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.egressIP ?? "Resolving...")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                Text([app.egressCity, app.egressCountry].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " / "))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AppTheme.controlFill(for: colorScheme))
        )
    }

    private func deckMetric(symbol: String, label: String, value: String, detail: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            IconTile(symbol: symbol, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.controlFill(for: colorScheme))
        )
    }

    private var statusCard: some View {
        Card(padding: 18) {
            HStack(alignment: .center, spacing: 14) {
                StatusOrb(status: app.status, reduceMotion: app.settings.reduceAnimations)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.status.label)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(secondaryLabel)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 12)
                if app.status.isRunning {
                    ipColumn
                        .layoutPriority(1)
                        .padding(.trailing, 24)
                }
                if app.status.isSessionActive {
                    Button {
                        Task {
                            if app.status.isPaused { await app.resume() }
                            else { await app.pause() }
                        }
                    } label: {
                        Label(app.status.isPaused ? "Resume" : "Pause",
                              systemImage: app.status.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.bordered)
                    .disabled(app.status.isTransitioning)
                }
                PowerButton(isRunning: app.status.isSessionActive,
                            isBusy: app.status.isTransitioning) {
                    Task {
                        if app.status.isSessionActive { await app.stop() }
                        else { await app.start() }
                    }
                }
                .disabled(app.activeProfile == nil && !app.status.isSessionActive)
                .opacity(app.activeProfile == nil && !app.status.isSessionActive ? 0.5 : 1)
            }
        }
    }

    @ViewBuilder
    private var ipColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.mint)
                Text("Egress IP")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button { app.refreshEgressNow() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("Refresh egress IP")
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let ip = app.egressIP {
                    Text(verbatim: ip)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                    if let cc = app.egressCountry, !cc.isEmpty {
                        Text(countryLine(code: cc))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                } else if let msg = app.egressLookupMessage {
                    Text(msg)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Resolving…")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(minWidth: 148, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Compact bandwidth meter

    private var meterCard: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .lastTextBaseline) {
                    Text(app.status.isRunning ? "This session" : "Activity")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if app.status.isRunning {
                        Text(uptime)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(alignment: .center, spacing: 14) {
                    speedColumn(
                        icon: "arrow.down",
                        title: "Down",
                        speed: app.downloadBytesPerSec,
                        total: app.sessionBytesDown,
                        tint: .blue
                    )
                    Divider().frame(height: 26)
                    speedColumn(
                        icon: "arrow.up",
                        title: "Up",
                        speed: app.uploadBytesPerSec,
                        total: app.sessionBytesUp,
                        tint: .purple
                    )
                    Divider().frame(height: 26)
                    totalColumn
                }
                if !app.settings.reduceAnimations {
                    ActivityPulseMeter(
                        downValue: app.downloadBytesPerSec,
                        upValue: app.uploadBytesPerSec,
                        peak: peakHint
                    )
                }
            }
        }
    }

    private func speedColumn(icon: String, title: String, speed: Double, total: UInt64, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(rate(speed))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("\(title) · \(formatBytes(total))")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totalColumn: some View {
        HStack(spacing: 8) {
            Image(systemName: "sum")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 1) {
                Text(formatBytes(app.sessionBytesDown + app.sessionBytesUp))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("Total")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Roughly: where to anchor the sparkbar's "full" mark.
    private var peakHint: Double {
        max(app.downloadBytesPerSec, app.uploadBytesPerSec, 64 * 1024)  // ~512 kbps floor so we don't draw a full bar at idle
    }

    // MARK: - LAN IP

    private func lanCard(_ ip: String) -> some View {
        Card(height: 76, padding: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "wifi.router")
                    .font(.system(size: 16))
                    .foregroundStyle(.orange)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("LAN sharing")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        StatusPill(text: bindsAllInterfaces ? "On" : "Local", tint: bindsAllInterfaces ? .green : .secondary)
                    }
                    Text(verbatim: ip)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    EndpointChip(label: "SOCKS", value: "\(app.settings.listenPort)", tint: .orange)
                    EndpointChip(label: "HTTP", value: "\(app.settings.httpPort)", tint: .cyan)
                }
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString("SOCKS \(ip):\(app.settings.listenPort)\nHTTP \(ip):\(app.settings.httpPort)", forType: .string)
                    withAnimation { copiedLan = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { copiedLan = false }
                    }
                } label: {
                    Image(systemName: copiedLan ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy LAN endpoints")
            }
        }
    }

    private var bindsAllInterfaces: Bool {
        let h = app.settings.listenHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return h == "0.0.0.0" || h == "*"
    }

    // MARK: - Helpers

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in tick() }
        }
        tick()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let started = app.startedAt else {
            uptime = "0s"
            return
        }
        let dt = Int(Date().timeIntervalSince(started))
        let h = dt / 3600, m = (dt % 3600) / 60, s = dt % 60
        uptime = h > 0 ? String(format: "%dh %02dm", h, m)
              : m > 0 ? String(format: "%dm %02ds", m, s)
                      : String(format: "%ds", s)
    }

    private func refreshLanIP() {
        lanIPv4 = LanAddress.primaryIPv4String()
    }

    private var secondaryLabel: String {
        switch app.status {
        case .stopped:
            return app.activeProfile == nil
                ? "No profile selected. Import or pick one from Profiles."
                : "Profile: \(app.activeProfile?.name ?? "none")"
        case .running:
            return "Profile: \(app.activeProfile?.name ?? "none")"
        case .paused:
            return app.pauseError ?? "Veil routing and Xray are off; your normal internet connection is active."
        case .starting: return "Bringing up the bridge and Xray…"
        case .pausing: return "Stopping Xray core…"
        case .resuming: return "Starting Xray core…"
        case .stopping: return "Tearing down."
        case .error(let msg): return msg
        }
    }

    private func countryLine(code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 2 else { return trimmed }
        return trimmed.uppercased()
    }

    private func rate(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1_000 { return "0 KB/s" }
        if bytesPerSec < 1_000_000 { return String(format: "%.0f KB/s", bytesPerSec / 1_000) }
        if bytesPerSec < 1_000_000_000 { return String(format: "%.1f MB/s", bytesPerSec / 1_000_000) }
        return String(format: "%.2f GB/s", bytesPerSec / 1_000_000_000)
    }

    private func formatBytes(_ n: UInt64) -> String {
        let d = Double(n)
        if d < 1_000 { return "\(n) B" }
        if d < 1_000_000 { return String(format: "%.1f KB", d / 1_000) }
        if d < 1_000_000_000 { return String(format: "%.2f MB", d / 1_000_000) }
        return String(format: "%.2f GB", d / 1_000_000_000)
    }
}

// MARK: - Building blocks

struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var alignment: Alignment = .leading
    var maxHeight: CGFloat? = nil
    var height: CGFloat? = nil
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height ?? maxHeight, alignment: alignment)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .fill(AppTheme.cardFill(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                            .stroke(AppTheme.stroke(for: colorScheme), lineWidth: 1)
                    )
                    .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 5, y: 2)
            )
    }
}

struct StatusOrb: View {
    let status: AppState.Status
    var reduceMotion: Bool = false
    @State private var pulse = false
    private var animatePulse: Bool { status.isTransitioning && !reduceMotion }
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.12)).frame(width: 58, height: 58)
                .scaleEffect(animatePulse && pulse ? 1.15 : 0.9)
                .opacity(status.isRunning ? 1 : 0.5)
                .animation(animatePulse
                           ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                           : .default, value: pulse)
            Circle().stroke(color.opacity(0.35), lineWidth: 1).frame(width: 42, height: 42)
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.45), radius: 7)
        }
        .onAppear { if animatePulse { pulse = true } }
    }
    private var color: Color {
        switch status {
        case .stopped: return .gray
        case .starting, .pausing, .resuming, .stopping: return .yellow
        case .paused: return .orange
        case .running: return .green
        case .error: return .red
        }
    }
    private var symbol: String {
        switch status {
        case .running: return "checkmark.shield.fill"
        case .paused: return "pause.fill"
        case .starting, .pausing, .resuming, .stopping: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle.fill"
        case .stopped: return "shield"
        }
    }
}

struct PowerButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let isRunning: Bool
    let isBusy: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().controlSize(.small)
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Image(systemName: isRunning ? "stop.fill" : "power")
                        .font(.system(size: 13, weight: .bold))
                }
                Text(isRunning ? "Disconnect" : "Connect")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isRunning
                          ? Color.red.opacity(0.88)
                          : AppTheme.connectFill(for: colorScheme))
                    .shadow(color: isRunning
                            ? Color.red.opacity(hover ? 0.35 : 0.2)
                            : AppTheme.connectShadow(for: colorScheme),
                            radius: hover ? 10 : 6, y: 3)
            )
            .scaleEffect(hover ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: hover)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onHover { hover = $0 }
    }
}

/// Circular activity gauges that fill proportionally to current vs peak.
private struct ActivityPulseMeter: View {
    let downValue: Double
    let upValue: Double
    let peak: Double

    var body: some View {
        HStack(spacing: 14) {
            CircularActivityGauge(symbol: "arrow.down", label: "Download", value: downValue, peak: peak, tint: .blue)
            CircularActivityGauge(symbol: "arrow.up", label: "Upload", value: upValue, peak: peak, tint: .purple)
            Spacer()
            Text("LIVE ACTIVITY")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 3)
    }
}

private struct CircularActivityGauge: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var pulse = false

    let symbol: String
    let label: String
    let value: Double
    let peak: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(AppTheme.subtleFill(for: colorScheme), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: filled)
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(pulse ? 0.55 : 0.18), radius: pulse ? 7 : 2)
                    .animation(.spring(response: 0.34, dampingFraction: 0.80), value: filled)
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(tint)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(activityLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(tint)
            }
        }
        .onChange(of: value) { _ in triggerPulse() }
    }

    private var filled: CGFloat {
        guard peak > 0 else { return 0 }
        return CGFloat(min(1.0, value / peak))
    }

    private var activityLabel: String {
        if value < 1_000 { return "IDLE" }
        if filled > 0.72 { return "HIGH" }
        if filled > 0.24 { return "ACTIVE" }
        return "LOW"
    }

    private func triggerPulse() {
        guard value > 0 else {
            withAnimation(.easeOut(duration: 0.18)) { pulse = false }
            return
        }
        withAnimation(.easeOut(duration: 0.10)) { pulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeOut(duration: 0.26)) { pulse = false }
        }
    }
}

struct SystemProxyCard: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Card(height: 76, padding: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: app.settings.connectionMode.systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(.cyan)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        Text("Routing")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                        Spacer()
                        modePicker
                            .frame(width: 116)
                    }
                    HStack(alignment: .center, spacing: 6) {
                        RouteSummaryChip(text: app.settings.connectionMode == .tunnel
                                         ? "Packet tunnel"
                                         : (app.settings.useSystemProxy ? "HTTP/S + SOCKS" : "Manual apps"))
                        if app.settings.connectionMode == .proxy && app.settings.useSystemProxy {
                            RouteSummaryChip(text: "System on")
                        }
                        Spacer(minLength: 0)
                        if app.settings.connectionMode == .proxy {
                            proxyToggle
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
    }

    private var modePicker: some View {
        Picker("", selection: Binding(
            get: { app.settings.connectionMode },
            set: {
                app.settings.connectionMode = $0
                app.saveSettings()
                Task { await app.reconnectIfRunning() }
            }
        )) {
            ForEach(AppSettings.ConnectionMode.allCases) { mode in
                Label(mode.label, systemImage: mode.systemImage).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
    }

    private var proxyToggle: some View {
        Toggle("", isOn: Binding(
            get: { app.settings.useSystemProxy },
            set: {
                app.settings.useSystemProxy = $0
                app.saveSettings()
                Task { await app.reconnectIfRunning() }
            }
        ))
        .toggleStyle(.switch)
        .labelsHidden()
    }
}

private struct EndpointChip: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }
}

private struct StatusPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}

private struct RouteSummaryChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
    }
}
