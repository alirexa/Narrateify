import AppKit

enum ApplicationIcon {
    /// Agent apps can keep the generic icon when promoted into the Dock.
    /// Load our bundled icon directly instead of inheriting that cached image.
    @MainActor static func apply() {
        let icon = NSImage(named: "AppIcon") ?? Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            .flatMap { NSImage(contentsOf: $0) }
        if let icon { NSApp.applicationIconImage = icon }
    }
}
