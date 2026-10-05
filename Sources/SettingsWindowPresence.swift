import AppKit
import SwiftUI

/// Settings participates in the Dock and Command-Tab until its window closes.
/// Losing focus or minimizing the window must not turn the app back into an agent.
@MainActor
final class SettingsWindowPresence: NSObject {
    static let shared = SettingsWindowPresence()
    private weak var window: NSWindow?
    private var isOpen = false

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        NotificationCenter.default.removeObserver(self)
        self.window = window
        let notifications = NotificationCenter.default
        notifications.addObserver(self, selector: #selector(didBecomeKey),
                                  name: NSWindow.didBecomeKeyNotification, object: window)
        notifications.addObserver(self, selector: #selector(willClose),
                                  name: NSWindow.willCloseNotification, object: window)
        showInDock()
    }

    func showInDock() {
        guard window != nil, !isOpen else { return }
        isOpen = true
        AppState.shared.settingsWindowOpen = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A Dock click also restores minimized Settings, rather than leaving it hidden.
    func reopen() -> Bool {
        guard isOpen, let window else { return false }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    @objc private func didBecomeKey(_ notification: Notification) {
        // SwiftUI can reuse the same NSWindow after the red close button.
        showInDock()
    }

    @objc private func willClose(_ notification: Notification) {
        isOpen = false
        AppState.shared.settingsWindowOpen = false
        NSApp.setActivationPolicy(.accessory)
    }
}

struct SettingsWindowRegistration: NSViewRepresentable {
    final class WindowView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // Avoid publishing observable state during SwiftUI's view update.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window else { return }
                SettingsWindowPresence.shared.attach(window)
            }
        }
    }

    func makeNSView(context: Context) -> WindowView { WindowView() }
    func updateNSView(_ nsView: WindowView, context: Context) {}
}
