# Accessibility access

Narrateify does not request Accessibility when it opens. Settings → General → Accessibility reports the actual permission result, rechecks it when the app becomes active, and offers **Check access** and **Open System Settings**. The onboarding Grant button remains an explicit permission action.

If the macOS switch is enabled but Narrateify reports missing access, remove the stale entry and add the installed app again. Ad-hoc rebuilds change the code identity macOS checks, so using a stable signing identity avoids that particular source of repeated approvals. Clipboard and file narration do not require selected-text Accessibility access.
