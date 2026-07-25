import SwiftUI

struct ScreenHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    init(
        eyebrow: String,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(AppTheme.indigo)
                        .frame(width: 22, height: 3)
                    Text(eyebrow.uppercased())
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .tracking(-0.6)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing()
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct IconTile: View {
    let symbol: String
    var tint: Color = AppTheme.cyan
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.40, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(tint.opacity(0.11))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                            .stroke(tint.opacity(0.20))
                    )
            )
    }
}

/// Segmented Local vs LAN binding for the SOCKS listener host.
struct ListenScopeToggle: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var exposesToLAN: Bool

    var body: some View {
        HStack(spacing: 0) {
            scopeSegment(
                title: "Local",
                icon: "laptopcomputer",
                selected: !exposesToLAN
            ) { exposesToLAN = false }

            scopeSegment(
                title: "LAN",
                icon: "wifi.router",
                selected: exposesToLAN
            ) { exposesToLAN = true }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.subtleFill(for: colorScheme))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.stroke(for: colorScheme), lineWidth: 1))
        )
    }

    private func scopeSegment(
        title: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(colorScheme == .dark ? 0.28 : 0.16) : .clear)
            )
            .foregroundStyle(selected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

/// System / Light / Dark picker that matches Cloak's card styling.
struct AppearancePicker: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var mode: AppSettings.AppearanceMode

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppSettings.AppearanceMode.allCases) { option in
                Button {
                    mode = option
                } label: {
                    Text(option.label)
                        .font(.system(size: 11, weight: mode == option ? .semibold : .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(mode == option
                                      ? Color.accentColor.opacity(colorScheme == .dark ? 0.26 : 0.14)
                                      : AppTheme.subtleFill(for: colorScheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(mode == option ? Color.accentColor.opacity(0.5) : AppTheme.faintStroke(for: colorScheme),
                                        lineWidth: 1)
                        )
                        .foregroundStyle(mode == option ? Color.accentColor : .primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
