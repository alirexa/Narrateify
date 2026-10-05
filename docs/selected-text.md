# Selected-text capture

The global shortcut and menu action read the last active external application's selection. Narrateify first tries the Accessibility selected-text attribute without changing focus or the clipboard. For applications that do not expose that attribute, it brings the source forward before sending Command-C and checks that focus has returned before posting the keystroke.

This avoids copying from Narrateify itself when its Settings window is open in the Dock. Missing Accessibility access is reported by the app rather than triggering an authorization dialog during capture.
