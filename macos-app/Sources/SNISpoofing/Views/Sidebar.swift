import SwiftUI

struct Sidebar: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Binding var tab: ContentView.Tab

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VeilBrandImage(size: 38, cornerRadius: 11)
                    .shadow(color: AppTheme.indigo.opacity(0.28), radius: 12, y: 5)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Veil")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("NETWORK CONSOLE")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(1.15)
                        .foregroundStyle(AppTheme.cyan)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 30)
            .padding(.bottom, 24)

            Text("WORKSPACE")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            VStack(spacing: 5) {
                ForEach(ContentView.Tab.allCases) { t in
                    SidebarItem(tab: t, selected: tab == t) { tab = t }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            StatusChip(status: app.status)
                .padding(.horizontal, 12)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.sidebarBackground(for: colorScheme))
    }
}

private struct SidebarItem: View {
    @Environment(\.colorScheme) private var colorScheme
    let tab: ContentView.Tab
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? AppTheme.indigo.opacity(0.18) : .clear)
                    Image(systemName: tab.symbol)
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .frame(width: 28, height: 28)
                Text(tab.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                Spacer()
                if selected {
                    Capsule()
                        .fill(AppTheme.cyan)
                        .frame(width: 3, height: 18)
                        .shadow(color: AppTheme.cyan.opacity(0.5), radius: 4)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected
                          ? AppTheme.elevatedFill(for: colorScheme)
                          : (hover ? AppTheme.hoverFill(for: colorScheme) : .clear))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(selected ? AppTheme.stroke(for: colorScheme) : .clear)
                    )
            )
            .foregroundColor(selected ? .primary : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

private struct StatusChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let status: AppState.Status
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(color.opacity(0.18)).frame(width: 26, height: 26)
                Circle().fill(color).frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.7), radius: 4)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(status.label)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Text(status.isSessionActive ? "Secure route active" : "System network")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.elevatedFill(for: colorScheme))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.faintStroke(for: colorScheme)))
        )
    }
    var color: Color {
        switch status {
        case .running: return .green
        case .starting, .pausing, .resuming, .stopping: return .yellow
        case .paused: return .orange
        case .error: return .red
        case .stopped: return .secondary
        }
    }
}
