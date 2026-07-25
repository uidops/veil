import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme

    @State private var privilegeError: String?
    @State private var showAdvanced = false
    @State private var newDomain: String = ""
    @State private var domainError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.pageSpacing) {
            header
            HStack(alignment: .top, spacing: 16) {
                settingsRail
                    .frame(width: 220)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        settingsSectionLabel("Experience", detail: "Appearance and motion")
                        appearanceCard

                        settingsSectionLabel("Connection", detail: "Listener and bridge")
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 14) {
                                cloudflareCard
                                proxyCard
                            }
                            VStack(spacing: 14) {
                                cloudflareCard
                                proxyCard
                            }
                        }
                        failoverCard
                        networkRecoveryCard

                        settingsSectionLabel("Traffic policy", detail: "Direct-routing exceptions")
                        routingCard

                        if showAdvanced {
                            settingsSectionLabel("System", detail: "Diagnostics and privileges")
                            advancedSection
                        }
                    }
                    .padding(.horizontal, 1)
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear {
            app.privilegesInstalled = SudoPrivilege.isInstalled()
        }
        .onDisappear { addCustomDomain() }
    }

    // MARK: - Sections

    private var settingsRail: some View {
        Card(alignment: .topLeading, maxHeight: .infinity, padding: 16) {
            VStack(alignment: .leading, spacing: 15) {
                Text("CONFIGURATION")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(.tertiary)

                settingsRailRow(
                    symbol: "circle.lefthalf.filled",
                    title: "Appearance",
                    value: app.settings.appearanceMode.label,
                    tint: .orange
                )
                settingsRailRow(
                    symbol: app.settings.connectionMode.systemImage,
                    title: "Route mode",
                    value: app.settings.connectionMode.label,
                    tint: AppTheme.cyan
                )
                settingsRailRow(
                    symbol: "network",
                    title: "Local access",
                    value: app.settings.exposesToLAN ? "LAN" : "This Mac",
                    tint: .blue
                )
                settingsRailRow(
                    symbol: "arrow.triangle.branch",
                    title: "Bypass",
                    value: app.settings.bypassEnabled ? "Enabled" : "Disabled",
                    tint: .purple
                )
                settingsRailRow(
                    symbol: "arrow.triangle.2.circlepath",
                    title: "Auto failover",
                    value: app.settings.autoFailoverEnabled ? "Monitoring" : "Disabled",
                    tint: .pink
                )
                settingsRailRow(
                    symbol: "wifi.router",
                    title: "Network recovery",
                    value: app.settings.networkRecoveryEnabled ? "Armed" : "Disabled",
                    tint: AppTheme.cyan
                )

                Divider().opacity(0.6)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
                } label: {
                    HStack {
                        Label(showAdvanced ? "Hide advanced" : "Advanced", systemImage: "gearshape.2")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(AppTheme.controlFill(for: colorScheme))
                    )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Circle()
                        .fill(app.privilegesInstalled ? AppTheme.cyan : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(app.privilegesInstalled ? "Helper ready" : "Permission needed")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func settingsRailRow(symbol: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            IconTile(symbol: symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 11.5, weight: .bold))
                    .lineLimit(1)
            }
        }
    }

    private func settingsSectionLabel(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(1)
            Text(detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private var appearanceCard: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 17))
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Appearance")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: 16)
                        HStack(spacing: 7) {
                            Text("Reduce animations")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Toggle("", isOn: Binding(
                                get: { app.settings.reduceAnimations },
                                set: {
                                    app.settings.reduceAnimations = $0
                                    app.saveSettings()
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                        .help("Stops the moving dots and map pulse to save power.")
                    }
                    AppearancePicker(mode: Binding(
                        get: { app.settings.appearanceMode },
                        set: {
                            app.settings.appearanceMode = $0
                            app.saveSettings()
                        }
                    ))
                    Text("Choose light or dark, or follow your Mac's system setting.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        ScreenHeader(
            eyebrow: "Preferences",
            title: "Settings",
            subtitle: "Shape how Veil looks, listens, and routes your traffic."
        )
    }

    private var cloudflareCard: some View {
        Card(maxHeight: .infinity) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Cloudflare config", systemImage: "doc.text")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("Restore default") {
                        app.listenerProject.FAKE_SNI = ListenerProjectConfig.factoryRestore.FAKE_SNI
                        app.listenerProject.CONNECT_IP = ListenerProjectConfig.factoryRestore.CONNECT_IP
                        app.saveListenerProject()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }

                cloudflareField(
                    title: "Fake SNI",
                    hint: "Domain presented in the TLS handshake.",
                    text: fakeSNIBinding
                )
                cloudflareField(
                    title: "Connect IP",
                    hint: "Cloudflare edge IP to connect through.",
                    text: connectIPBinding
                )

                Text("Veil manages the remaining listener settings automatically.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func cloudflareField(title: String, hint: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.controlFill(for: colorScheme))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.stroke(for: colorScheme)))
                )
            Text(hint)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
        }
    }

    private var fakeSNIBinding: Binding<String> {
        Binding(
            get: { app.listenerProject.FAKE_SNI },
            set: {
                app.listenerProject.FAKE_SNI = $0
                app.saveListenerProject()
            }
        )
    }

    private var connectIPBinding: Binding<String> {
        Binding(
            get: { app.listenerProject.CONNECT_IP },
            set: {
                app.listenerProject.CONNECT_IP = $0
                app.saveListenerProject()
            }
        )
    }

    private var proxyCard: some View {
        Card(alignment: .topLeading, maxHeight: .infinity) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 17))
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Local proxy listeners")
                        .font(.system(size: 13, weight: .semibold))
                    ListenScopeToggle(exposesToLAN: Binding(
                        get: { app.settings.exposesToLAN },
                        set: { enabled in
                            var s = app.settings
                            s.setExposesToLAN(enabled)
                            app.settings = s
                            app.saveSettings()
                            Task { await app.reconnectIfRunning() }
                        }
                    ))
                    Text(app.settings.exposesToLAN
                         ? "Other devices on your network can use these ports."
                         : "Only this Mac can use these ports.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .top, spacing: 10) {
                        portField(title: "SOCKS", text: proxyPortBinding)
                        portField(title: "HTTP", text: httpPortBinding)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var failoverCard: some View {
        Card {
            HStack(alignment: .center, spacing: 14) {
                IconTile(symbol: "arrow.triangle.2.circlepath", tint: .pink, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Automatic profile failover")
                        .font(.system(size: 13, weight: .semibold))
                    Text("After three failed health checks, Veil tries backup profiles in latency order and keeps the first working route.")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message = app.failoverMessage {
                        Text(message)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(app.isFailingOver ? Color.orange : AppTheme.cyan)
                    } else if app.settings.autoFailoverEnabled, app.profiles.count < 2 {
                        Text("Add at least two profiles to use failover.")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 12)
                Toggle("", isOn: Binding(
                    get: { app.settings.autoFailoverEnabled },
                    set: {
                        app.settings.autoFailoverEnabled = $0
                        app.configureFailoverMonitoring()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    private var networkRecoveryCard: some View {
        Card {
            HStack(alignment: .center, spacing: 14) {
                IconTile(symbol: "wifi.router", tint: AppTheme.cyan, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Network change recovery")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Detects Wi-Fi, Ethernet, hotspot, sleep, and wake changes, then cleans stale routes and reconnects after the network stabilizes.")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message = app.networkRecoveryMessage {
                        Text(message)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(app.isRecoveringNetwork ? Color.orange : AppTheme.cyan)
                    } else if let message = app.routeIntegrityMessage {
                        Text(message)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 12)
                Toggle("", isOn: Binding(
                    get: { app.settings.networkRecoveryEnabled },
                    set: {
                        app.settings.networkRecoveryEnabled = $0
                        app.configureNetworkRecovery()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    private func portField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppTheme.controlFill(for: colorScheme))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.stroke(for: colorScheme)))
                )
        }
    }

    private var permissionsCard: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: app.privilegesInstalled ? "checkmark.shield.fill" : "lock.shield")
                    .font(.system(size: 17))
                    .foregroundStyle(app.privilegesInstalled ? .green : .orange)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Helper permission")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if app.privilegesInstalled {
                            Button("Revoke") {
                                do {
                                    try SudoPrivilege.uninstall()
                                    app.privilegesInstalled = SudoPrivilege.isInstalled()
                                    privilegeError = nil
                                } catch {
                                    privilegeError = error.localizedDescription
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Button("Grant…") {
                                do {
                                    try SudoPrivilege.install()
                                    app.privilegesInstalled = true
                                    privilegeError = nil
                                } catch {
                                    privilegeError = error.localizedDescription
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    Text(app.privilegesInstalled
                         ? "Granted. Connect and toggle the system proxy without a password prompt."
                         : "Veil needs one-time admin permission to run the SNI listener and toggle the macOS SOCKS proxy.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let e = privilegeError {
                        Label(e, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            advancedCard
            permissionsCard
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var routingCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Routing / Bypass", systemImage: "arrow.triangle.branch")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Toggle("", isOn: bypassEnabledBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                Text("Selected domains skip the proxy and connect directly. Applies on the next Connect.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if app.settings.bypassEnabled {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 8),
                            count: GeositeCatalog.categories.count
                        ),
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(GeositeCatalog.categories) { cat in
                            geositeChip(cat)
                        }
                    }

                    customDomainsSection
                }
            }
        }
    }

    private func geositeChip(_ cat: GeositeCategory) -> some View {
        let selected = app.settings.bypassGeosites.contains(cat.id)
        return Button {
            toggleGeosite(cat.id)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                Text(cat.label)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.15) : AppTheme.controlFill(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selected ? Color.accentColor.opacity(0.5) : AppTheme.stroke(for: colorScheme))
                    )
            )
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .help(cat.detail)
    }

    private var customDomainsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom domains & IPs")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            PlainTextField(
                text: $newDomain,
                placeholder: "e.g. example.com, 192.168.1.1 or 10.0.0.0/8",
                onSubmit: { addCustomDomain() }
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.controlFill(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(domainError == nil ? AppTheme.stroke(for: colorScheme) : Color.red.opacity(0.6))
                    )
            )
            .onChange(of: newDomain) { _ in domainError = nil }

            if let domainError {
                Text(domainError)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }

            if !app.settings.bypassDomains.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(app.settings.bypassDomains, id: \.self) { domain in
                        DomainPill(domain: domain, colorScheme: colorScheme) {
                            removeCustomDomain(domain)
                        }
                    }
                }
            }
        }
    }

    private var bypassEnabledBinding: Binding<Bool> {
        Binding(
            get: { app.settings.bypassEnabled },
            set: {
                app.settings.bypassEnabled = $0
                app.saveSettings()
            }
        )
    }

    private func toggleGeosite(_ id: String) {
        var selected = app.settings.bypassGeosites
        if let idx = selected.firstIndex(of: id) {
            selected.remove(at: idx)
        } else {
            selected.append(id)
        }
        app.settings.bypassGeosites = selected
        app.saveSettings()
    }

    private func addCustomDomain() {
        let entry = newDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty else { return }
        guard isValidBypassEntry(entry) else {
            domainError = "“\(entry)” isn’t a valid domain or rule."
            return
        }
        if !app.settings.bypassDomains.contains(entry) {
            app.settings.bypassDomains.append(entry)
            app.saveSettings()
        }
        newDomain = ""
        domainError = nil
    }

    private func removeCustomDomain(_ domain: String) {
        app.settings.bypassDomains.removeAll { $0 == domain }
        app.saveSettings()
    }

    /// Accepts an Xray rule prefix (`domain:`/`geosite:`/`geoip:`/`full:`/`regexp:`/
    /// `keyword:`/`ext:`) with a non-empty value, a CIDR or literal IP address, or a
    /// plain hostname with at least one dot and a 2+ letter TLD. Rejects bare
    /// tokens like "g".
    private func isValidBypassEntry(_ entry: String) -> Bool {
        let prefixes = ["domain:", "full:", "geosite:", "geoip:", "regexp:", "keyword:", "ext:"]
        for prefix in prefixes where entry.lowercased().hasPrefix(prefix) {
            return entry.count > prefix.count
        }
        if XrayOutboundBuilder.isIPRule(entry) { return XrayOutboundBuilder.isValidIPRule(entry) }
        let pattern = "^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$"
        return entry.range(of: pattern, options: .regularExpression) != nil
    }

    private var advancedCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Advanced", systemImage: "gearshape.2")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                HStack {
                    Text("xray log level")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { app.settings.logLevel },
                        set: {
                            app.settings.logLevel = $0
                            app.saveSettings()
                        }
                    )) {
                        ForEach(AppSettings.LogLevel.allCases) { lvl in
                            Text(lvl.rawValue.capitalized).tag(lvl)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 160)
                    Spacer()
                }
                Text("Only takes effect on the next Connect. Use \"debug\" to surface every xray dispatch line.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Compact field helper

    private func compactField(label: String, text: Binding<String>, monospaced: Bool, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: monospaced ? .monospaced : .default))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(width: width)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppTheme.controlFill(for: colorScheme))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.stroke(for: colorScheme)))
                )
        }
    }

    private var proxyPortBinding: Binding<String> {
        Binding(
            get: { String(app.settings.listenPort) },
            set: {
                let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                if let v = Int(t), v > 0, v <= 65_535 {
                    app.settings.listenPort = v
                    app.saveSettings()
                }
            }
        )
    }

    private var httpPortBinding: Binding<String> {
        Binding(
            get: { String(app.settings.httpPort) },
            set: {
                let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                if let v = Int(t), v > 0, v <= 65_535 {
                    app.settings.httpPort = v
                    app.saveSettings()
                }
            }
        )
    }
}

// LabeledField was kept by older callers — keep the type around so any other
// view that still references it compiles. New code uses the inline compact
// field above instead.
struct LabeledField: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let hint: String
    @Binding var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(hint).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(width: 120, alignment: .leading)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.controlFill(for: colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppTheme.stroke(for: colorScheme), lineWidth: 1)
                        )
                )
        }
    }
}

/// A removable domain tag. The × turns red on hover.
struct DomainPill: View {
    let domain: String
    let colorScheme: ColorScheme
    let onRemove: () -> Void
    @State private var hoveringX = false

    private var isIP: Bool { XrayOutboundBuilder.isIPRule(domain) }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isIP ? "network" : "globe")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isIP ? Color.teal : Color.secondary)
            Text(domain)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(hoveringX ? Color.red : Color.secondary)
            }
            .buttonStyle(.plain)
            .onHover { hoveringX = $0 }
        }
        .padding(.leading, 9)
        .padding(.trailing, 7)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(AppTheme.controlFill(for: colorScheme))
                .overlay(Capsule().stroke(AppTheme.stroke(for: colorScheme)))
        )
    }
}

/// Simple wrapping layout — lays subviews left-to-right and wraps to a new line
/// when the proposed width is exceeded. Used for the bypass domain pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.replacingUnspecifiedDimensions().width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Plain single-line text field backed by `NSTextField`. SwiftUI's `TextField`
/// flags itself as AutoFill-eligible on macOS, which flashes the system
/// suggestion popover on first focus. Using a raw field with `contentType = nil`
/// and no completion candidates avoids that flicker.
struct PlainTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.placeholderString = placeholder
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.allowsEditingTextAttributes = false
        field.contentType = nil
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PlainTextField
        init(_ parent: PlainTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.onSubmit()
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }

        // Returning no candidates suppresses the automatic-completion popover.
        func control(_ control: NSControl, textView: NSTextView,
                     completions words: [String], forPartialWordRange charRange: NSRange,
                     indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
            []
        }
    }
}
