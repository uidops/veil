import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var tab: Tab = .dashboard

    enum Tab: String, CaseIterable, Identifiable {
        case dashboard, profiles, settings, logs, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .profiles: return "Profiles"
            case .settings: return "Settings"
            case .logs: return "Logs"
            case .about: return "About"
            }
        }
        var symbol: String {
            switch self {
            case .dashboard: return "bolt.shield"
            case .profiles: return "person.crop.rectangle.stack"
            case .settings: return "slider.horizontal.3"
            case .logs: return "doc.text"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        ZStack {
            BackgroundGradient()
            VStack(spacing: 0) {
                CommandBar(tab: $tab)
                Rectangle()
                    .fill(AppTheme.stroke(for: colorScheme))
                    .frame(height: 1)
                    .opacity(0.55)
                Group {
                    switch tab {
                    case .dashboard: DashboardView()
                    case .profiles: ProfilesView()
                    case .settings: SettingsView()
                    case .logs: LogsView()
                    case .about: AboutView()
                    }
                }
                .frame(maxWidth: 1180, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 22)
            }
        }
        .background(WindowAccessor())
    }
}

private struct CommandBar: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Binding var tab: ContentView.Tab

    var body: some View {
        HStack(spacing: 20) {
            HStack(spacing: 10) {
                VeilBrandImage(size: 34, cornerRadius: 9)
                VStack(alignment: .leading, spacing: 0) {
                    Text("VEIL")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .tracking(1.2)
                    Text("SIGNAL ROUTER")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(AppTheme.cyan)
                }
            }
            .frame(width: 142, alignment: .leading)

            HStack(spacing: 3) {
                ForEach(ContentView.Tab.allCases) { item in
                    Button { tab = item } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 11, weight: .semibold))
                            Text(item.title)
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .foregroundStyle(tab == item ? Color.primary : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(tab == item ? AppTheme.elevatedFill(for: colorScheme) : .clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(tab == item ? AppTheme.stroke(for: colorScheme) : .clear)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(AppTheme.controlFill(for: colorScheme))
            )

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.5), radius: 4)
                VStack(alignment: .leading, spacing: 0) {
                    Text(app.status.label)
                        .font(.system(size: 10.5, weight: .bold))
                        .lineLimit(1)
                    Text(app.settings.connectionMode == .tunnel ? "Tunnel" : "Proxy")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(AppTheme.cardFill(for: colorScheme)))
            .overlay(Capsule().stroke(AppTheme.stroke(for: colorScheme)))
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 12)
        .background(AppTheme.chromeFill(for: colorScheme))
    }

    private var statusColor: Color {
        switch app.status {
        case .running: return AppTheme.cyan
        case .paused: return .orange
        case .starting, .pausing, .resuming, .stopping: return .yellow
        case .error: return AppTheme.indigo
        case .stopped: return .secondary
        }
    }
}

struct BackgroundGradient: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
            Canvas { context, size in
                let step: CGFloat = 32
                var path = Path()
                stride(from: CGFloat(0), through: size.width, by: step).forEach { x in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                stride(from: CGFloat(0), through: size.height, by: step).forEach { y in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(Color.primary.opacity(colorScheme == .dark ? 0.022 : 0.028)), lineWidth: 0.5)
            }
        }
        .ignoresSafeArea()
    }
}

/// Configures the window for a standard-height hidden-title bar (traffic lights
/// float over the content, no extra drag strip). Native fullscreen is disabled so
/// the green button zooms (fills the screen in-place) instead of entering the
/// separate-Space fullscreen mode, which forced an opaque titlebar/menu strip to
/// slide over the content.
struct WindowAccessor: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            context.coordinator.attach(w)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Coordinator {
        private weak var window: NSWindow?
        private var behaviorObservation: NSKeyValueObservation?

        func attach(_ w: NSWindow) {
            window = w
            apply()
            // SwiftUI re-adds `.fullScreenPrimary` during later layout passes, so a
            // one-shot fix is racy and the green button intermittently reverts to
            // native fullscreen. Observe the property and strip it the moment it
            // reappears, keeping the zoom ("+") behavior consistent.
            behaviorObservation = w.observe(\.collectionBehavior, options: [.new]) { [weak self] win, _ in
                self?.enforceNoFullScreen(win)
            }
        }

        private func enforceNoFullScreen(_ w: NSWindow) {
            guard w.collectionBehavior.contains(.fullScreenPrimary)
                || !w.collectionBehavior.contains(.fullScreenNone) else { return }
            var b = w.collectionBehavior
            b.remove(.fullScreenPrimary)
            b.insert(.fullScreenNone)
            w.collectionBehavior = b
        }

        private func apply() {
            guard let w = window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.titlebarSeparatorStyle = .none
            w.isMovableByWindowBackground = true
            w.styleMask.insert(.fullSizeContentView)
            enforceNoFullScreen(w)
        }

        deinit { behaviorObservation?.invalidate() }
    }
}
