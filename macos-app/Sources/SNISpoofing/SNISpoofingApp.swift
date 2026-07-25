import SwiftUI
import AppKit
import QuartzCore

@main
struct SNISpoofingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    /// Constant ID so the menu-bar "Open" action can reopen the singleton
    /// window after the user closes it (rather than spawning a duplicate).
    static let mainWindowID = "cloak.main"

    var body: some Scene {
        Window("Veil", id: Self.mainWindowID) {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appState.settings.preferredColorScheme)
                .tint(AppTheme.indigo)
                .frame(minWidth: 900, minHeight: 580)
                .onAppear { appDelegate.appState = appState }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .preferredColorScheme(appState.settings.preferredColorScheme)
                .tint(AppTheme.indigo)
        } label: {
            MenuBarLabel(status: appState.status)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Live-updating menu-bar icon: filled shield when connected, outline otherwise.
private struct MenuBarLabel: View {
    let status: AppState.Status

    var body: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
    }

    private var symbolName: String {
        switch status {
        case .running: return "shield.lefthalf.filled"
        case .paused: return "pause.circle"
        case .starting, .pausing, .resuming, .stopping: return "shield.lefthalf.filled.trianglebadge.exclamationmark"
        case .error: return "shield.slash"
        case .stopped: return "shield"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    override init() {
        super.init()
        Self.shared = self
    }

    /// Wired up from `SNISpoofingApp.body` so termination handlers can reach state.
    var appState: AppState?
    var isExplicitQuit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillPowerOff(_:)),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        if closingWindow.canBecomeMain && !closingWindow.isExcludedFromWindowsMenu {
            closingWindow.orderOut(nil)
            let remainingVisible = NSApp.windows.filter {
                $0 != closingWindow && $0.isVisible && $0.canBecomeMain && !$0.isExcludedFromWindowsMenu
            }
            if remainingVisible.isEmpty {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window.canBecomeMain && !window.isExcludedFromWindowsMenu {
            NSApp.setActivationPolicy(.regular)
        }
    }

    @objc private func systemWillPowerOff(_ notification: Notification) {
        isExplicitQuit = true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isExplicitQuit {
            // Hide every single window aggressively, then flush the
            // Window Server pipeline so pixels are gone before cleanup.
            hideAllWindows()

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                Task { @MainActor in
                    self?.appState?.terminateSync()
                }
                DispatchQueue.main.async {
                    sender.reply(toApplicationShouldTerminate: true)
                }
            }
            return .terminateLater
        }
        // Intercept standard Cmd+Q or Quit actions and redirect to tray mode.
        closeMainWindows()
        return .terminateCancel
    }

    /// Hides every window the app owns — no filtering. Used right before
    /// termination to guarantee no ghost windows remain on screen.
    func hideAllWindows() {
        for window in NSApp.windows {
            window.alphaValue = 0
            window.orderOut(nil)
        }
        NSApp.setActivationPolicy(.accessory)
        NSApp.hide(nil)
        // Force the Window Server to process the removal synchronously.
        CATransaction.flush()
    }

    /// Hides only the main content windows (not menu-bar panels, etc.)
    /// Used for Cmd+Q → minimize-to-tray behaviour.
    func closeMainWindows() {
        for window in NSApp.windows {
            if window.canBecomeMain && !window.isExcludedFromWindowsMenu {
                window.orderOut(nil)
                window.close()
            }
        }
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu-bar icon keeps the session alive after the window closes — user
        // explicitly quits via Cmd-Q or the Quit button in the menu-bar popover.
        false
    }

    /// Re-open the main window when the user clicks the Dock icon while no
    /// window is on-screen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.setActivationPolicy(.regular)
        return true
    }
}
