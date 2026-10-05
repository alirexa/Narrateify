# App icon

The speech-bubble and waveform icon is bundled in `Resources/Assets.xcassets`, with all macOS standard and Retina sizes. No remote assets are used. The app assigns the bundled image when moving from menu-bar-only mode into the Dock.

Regenerate the PNGs and app-icon manifest with `swift scripts/make-app-icon.swift`, then run `xcodegen generate` and build normally. The script accepts an optional output appiconset directory for previewing changes.
