# ClaudeLimit

Menu bar app + macOS widget showing Claude Code usage limits
(5-hour session / weekly / per-model, e.g. Fable) — the same data as
Claude Code's `/usage` command.

## How it works

- Reads the Claude Code OAuth token from the macOS Keychain (`Claude Code-credentials`)
  with fallbacks: `~/.claude/.credentials.json` or the `CLAUDE_CODE_OAUTH_TOKEN` env var
- Calls `GET https://api.anthropic.com/api/oauth/usage` every 180 seconds
  (polling faster gets rate limited with 429)
- The menu bar shows session, weekly, and per-model usage at a glance;
  click for details (reset countdowns, plan name)
- Snapshots are cached in an App Group container for the widget to read
  (the widget never calls the API itself — the extension sandbox
  cannot access the Keychain item)

## Build

Requires Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen
cd ClaudeLimit
xcodegen generate
open ClaudeLimit.xcodeproj
```

Then in Xcode:

1. Select the `ClaudeLimit` target → Signing & Capabilities → pick your own Team (both targets)
2. Run the `ClaudeLimit` target

## After the first run

- macOS will ask for permission to access Claude Code's Keychain item → click **Always Allow**
  (if no prompt appears and the read fails, the app falls back to `~/.claude/.credentials.json`)
- Add the widget: right-click the desktop → Edit Widgets → search for "Claude Limit Usage"

## Release (DMG)

```bash
./scripts/release.sh 1.0.0
```

For a Gatekeeper-clean DMG (no warnings on other Macs), set
`SIGN_IDENTITY` (a Developer ID Application certificate) and
`NOTARY_PROFILE` (a `notarytool` keychain profile) before running —
see the header of [scripts/release.sh](scripts/release.sh) for setup.
Without them the DMG is ad-hoc signed: fine for your own machine, but
others must right-click → Open on first launch.

## Known limitations

- The endpoint is an undocumented API (community-discovered) and may change
- The access token expires after ~60 minutes and is refreshed by Claude Code itself —
  when it expires, the app shows a message asking you to run `claude` to refresh
- The widget stays fresh only while the menu bar app is running
  (recommended: add it to Login Items)
- The `User-Agent: claude-code/<version>` header is required — without it
  the endpoint rate-limits immediately

## Structure

```
ClaudeLimit/
├── project.yml                 # XcodeGen spec
├── scripts/
│   └── release.sh              # build + sign + notarize + DMG
├── App/                        # menu bar app (MenuBarExtra)
│   ├── ClaudeLimitApp.swift
│   ├── MenuContentView.swift
│   └── ClaudeLimit.entitlements
├── Widget/                     # WidgetKit extension (small + medium)
│   ├── ClaudeLimitWidget.swift
│   └── ClaudeLimitWidget.entitlements
└── Shared/                     # shared between both targets
    ├── UsageModels.swift       # models + date parsing
    ├── CredentialsProvider.swift # Keychain / file / env token
    ├── UsageAPI.swift          # /api/oauth/usage client
    └── UsageStore.swift        # App Group cache
```
