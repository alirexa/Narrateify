# Local signing

The default configuration supports ad-hoc builds without a developer account. The app and its test bundle share `Config/Signing.xcconfig`, so their signing teams stay consistent.

For an installed app that needs Accessibility, repeated ad-hoc rebuilds change the code requirement macOS remembers. To use your existing Apple Development certificate:

1. Copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig`.
2. Replace `YOUR_TEAM_ID` with your own team and retain the same signing identity across updates.
3. Run `xcodegen generate`, then build or test normally.

The local file is ignored by Git. Do not commit certificates, private keys, credentials or personal team configuration. Moving from an ad-hoc app to a developer-signed app requires a fresh permission approval once; future builds should retain that code identity while the same signing requirement is used. An upstream release signed by another developer is a different identity.

After replacing an app bundle, refresh its modification time and Launch Services registration if macOS retains stale icon metadata. Keep backups outside the install location.
