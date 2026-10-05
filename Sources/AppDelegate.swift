import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let serviceProvider = ServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When the app is launched as the unit-test host, skip all the live
        // setup (hotkeys, onboarding, network checks) — tests only need the types.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        // Run as a background "agent" — no Dock icon, no app menu.
        // (Setting LSUIElement = YES in Info.plist does the same at launch;
        //  this is a belt-and-suspenders fallback.)
        ApplicationIcon.apply()
        NSApp.setActivationPolicy(.accessory)

        // Make the "Narrate with Narrateify" Service available in the
        // right-click → Services menu of other apps.
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()

        registerHotKeys()
        TextCapture.trackSourceApplications()

        // Onboarding offers permission controls, but launching the app must not
        // request Accessibility. Only capturing a selection needs that access.
        if !UserDefaults.standard.bool(forKey: OnboardingWindow.didOnboardKey) {
            Task { @MainActor in OnboardingWindow.showIfNeeded() }
        }

        // If the last narration used an installed local model, bring its server
        // up now so it's ready to narrate immediately.
        Task { @MainActor in AppState.shared.autoStartLastServerIfNeeded() }

        // Quietly check GitHub for a newer release in the background.
        Task { @MainActor in await AppState.shared.updateChecker.check() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Don't leave orphaned local-server processes behind.
        MainActor.assumeIsolated { AppState.shared.shutdownServers() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        !SettingsWindowPresence.shared.reopen()
    }

    private func registerHotKeys() {
        // Bindings are user-editable (Settings → General → Shortcuts) and
        // persisted; the store registers them all with HotKeyManager.
        MainActor.assumeIsolated { AppState.shared.shortcutStore.applyAll() }
    }

}
