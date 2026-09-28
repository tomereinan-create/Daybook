# Daybook

A personal task journal for iPhone that keeps today's items in front of you
without your having to open it: a Live Activity on the lock screen, a large
interactive widget on the first home page, and notifications and alarms that
know the difference between "worth mentioning" and "get up".

All data stays on the device. No accounts, no analytics, no network.

## Requirements

- iOS 26 (AlarmKit)
- Xcode 26, Swift 6
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — the `.xcodeproj` is
  generated, not committed

## Building

```bash
xcodegen generate
open Daybook.xcodeproj
```

Command line:

```bash
xcodebuild test -scheme Daybook -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Layout

| Path | What lives there |
|---|---|
| `Core/Model` | The orthogonal settings that describe an item, and the presets that fill them |
| `Core/Engine` | The scheduling engine: pure Foundation, injectable clock and calendar |
| `Core/Persistence` | SwiftData models, the App Group container, and the bridge to the engine's value types |
| `App` | SwiftUI screens |
| `Tests` | Engine tests. Deterministic: fixed calendars, explicit instants |

The rule the codebase is built around: **an item's behaviour comes from its
settings, never from its type.** Presets are a bag of defaults you pick at
creation and can then edit freely. Nothing in `Core/Engine` branches on
`PresetKind`.

Current state, decisions and open questions live in [PROGRESS.md](PROGRESS.md).
