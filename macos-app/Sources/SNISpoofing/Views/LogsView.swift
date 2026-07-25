import SwiftUI

struct LogsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.pageSpacing) {
            ScreenHeader(
                eyebrow: "Diagnostics",
                title: "Activity logs",
                subtitle: "Inspect listener, Xray, and connection events when something needs attention."
            ) {
                HStack(spacing: 10) {
                Toggle("Enable", isOn: Binding(
                    get: { app.settings.logsEnabled },
                    set: {
                        app.settings.logsEnabled = $0
                        app.saveSettings()
                        if !$0 { app.clearLogs() }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                Button("Clear") { app.clearLogs() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(app.logs.isEmpty)
                }
            }

            if app.settings.logsEnabled {
                TextEditor(text: .constant(joinedLogs))
                    .font(.system(size: 11.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollContentBackground(.hidden)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                            .fill(AppTheme.controlFill(for: colorScheme))
                            .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius).stroke(AppTheme.stroke(for: colorScheme)))
                            .shadow(color: AppTheme.cardShadow(for: colorScheme), radius: 18, y: 8)
                    )
            } else {
                VStack(spacing: 8) {
                    IconTile(symbol: "waveform.path.ecg", tint: AppTheme.indigo, size: 54)
                    Text("Diagnostics are quiet")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Veil doesn't capture anything when logs are off. Flip the switch above when you need to diagnose a problem.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                        .fill(AppTheme.cardFill(for: colorScheme))
                        .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius).stroke(AppTheme.stroke(for: colorScheme)))
                )
            }
        }
    }

    private var joinedLogs: String {
        app.logs.map(\.text).joined(separator: "")
    }
}
