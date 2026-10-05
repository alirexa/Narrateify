import AppKit
import Carbon.HIToolbox

/// Captures the user's current text selection from *any* application by
/// synthesizing a ⌘C keystroke and reading the general pasteboard.
///
/// This is the most reliable cross-app technique on macOS. It requires
/// Accessibility permission (to post keyboard events to other apps).
enum TextCapture {
    private static var previousApplication: NSRunningApplication?
    private static var activationObserver: NSObjectProtocol?

    static func trackSourceApplications() {
        guard activationObserver == nil else { return }
        remember(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { notification in
            remember(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
    }

    private static func remember(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular else { return }
        previousApplication = app
    }

    static func selectedText(completion: @escaping (String?) -> Void) {
        guard AXIsProcessTrusted() else {
            // Report missing access in-app; permission dialogs are explicit actions.
            completion(nil)
            return
        }

        remember(NSWorkspace.shared.frontmostApplication)
        guard let source = previousApplication, !source.isTerminated else {
            completion(nil)
            return
        }
        // Reading through Accessibility avoids moving focus or touching the clipboard
        // when the source app exposes its selection. Web views may need the fallback.
        let application = AXUIElementCreateApplication(source.processIdentifier)
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
            var selection: CFTypeRef?
            let element = focused as! AXUIElement
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selection) == .success,
               let text = selection as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                completion(text)
                return
            }
        }

        // Settings makes Narrateify a regular app. A menu click can therefore
        // focus Narrateify; return to the source before sending Command-C.
        source.activate(options: [.activateIgnoringOtherApps])

        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount

        // Small delay lets the physically-held hotkey modifiers (⌃⌥) release
        // before we post the synthetic ⌘C, avoiding modifier interference.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier else {
                completion(nil)
                return
            }
            simulateCommandC()

            // Give the frontmost app a moment to write to the pasteboard.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if pasteboard.changeCount != previousChangeCount {
                    completion(pasteboard.string(forType: .string))
                } else {
                    completion(nil) // nothing was copied (no selection)
                }
            }
        }
    }

    private static func simulateCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cKey = CGKeyCode(kVK_ANSI_C)

        let down = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false)
        up?.flags = .maskCommand

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
