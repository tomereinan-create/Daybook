# Progress

## Status

**Phases 1 to 5 complete and green.**

CI: macOS 26.6.2, Xcode 26.6, iOS 26 SDK. All twelve test suites pass.

```
Occurrence generation ✓          Reconciling the rolling window ✓
Occurrence state ✓               Scheduling end to end ✓
Quota pacing ✓                   What a notification says ✓
Completion, routines, quotas ✓   What each surface shows ✓
Notification planning + cap ✓    The day the Today screen sees ✓
Presets are only defaults ✓      Daylight saving, midnight, time zones ✓
```

Every push runs `xcodegen generate` and `xcodebuild test` on a macOS runner.
On failure the workflow prints the compile errors and the failing test *with
its arguments*, and uploads the raw log as an artifact.

**Design prototype:** https://claude.ai/artifact/ECVu7SQq6jgksKMtdB4fpf —
twelve screens at iPhone size covering all three surfaces, the create flow,
review, settings, dark mode and Hebrew. Private to Tomer.

## Placeholders

Four values, all in `project.yml` under `settings.base`:

| Setting | Current value |
|---|---|
| `APP_NAME` | `Daybook` |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.tomereinan.daybook` |
| `APP_GROUP_ID` | `group.com.tomereinan.daybook` |
| `DEVELOPMENT_TEAM` | empty — your Apple Team ID |

Change them, run `xcodegen generate`, and everything follows. The app icon is a
flat indigo square generated as a stand-in — replace it.

## What is built

**Data model** (`Core/Model`) — orthogonal settings value types gathered in
`ItemSettings`. `PresetKind.defaultSettings(reference:calendar:)` is the only
place a preset means anything; nothing in `Core/Engine` branches on it.

**Scheduling engine** (`Core/Engine`) — pure Foundation, injectable calendar,
explicit `now` on every call. `OccurrenceGenerator`, `StateResolver`,
`QuotaPacer`, `SurfacePlanner`, `NotificationPlanner`, `CompletionService`, and
`ScheduleEngine` as the single facade.

**Storage** (`Core/Persistence`) — SwiftData `Item` and `OccurrenceRecord` in an
App Group container, projected to `Sendable` value types before the engine sees
them. `DataStore` is the only bridge.

**App** (`App`) — Today grouped by state, preset picker, create/edit form with
every setting reachable under Advanced, all-items list. English and Hebrew,
137 keys, RTL-safe, Dynamic Type, VoiceOver labels.

**Tests** (`Tests`) — nine suites, all deterministic: fixed calendars, explicit
instants, no `Date()`.

## Phase 2: notifications and alarms

**The rolling window is a diff.** `NotificationReconciler` compares the plan
against what iOS holds and returns add / remove / keep, so a reschedule is
idempotent: running it twice changes nothing the second time. That is what
makes it safe to call on launch, on every edit, on foreground and from the
background task. Fire times are part of an identifier, because the reconciler
compares identifiers and an alert whose time moved has to look like a different
request or the stale one survives at the old time.

**Completion silences its nags immediately**, not at the next refresh.

**AlarmKit**, read from the API rather than guessed. Three things worth
recording because they are not what you would assume:

- `AlarmManager.alarms` is a throwing property.
- `AlarmPresentation.Alert`'s current initialiser is iOS **26.1**, not 26.0, so
  there is an availability branch and the deprecated `stopButton` form below it.
  The deployment target stays at 26.0.
- Snooze is not a button behaviour. It is `CountdownDuration.postAlert` behind
  a `.countdown` secondary button.

A daily or weekday alarm becomes **one repeating alarm AlarmKit owns**, keyed by
the item so it is stable across days. Recurrences it cannot express weekly —
every N days, day of month — fall back to a fixed alarm per occurrence under a
derived deterministic id, so rescheduling replaces rather than stacks.

**Actions work from a cold start**: the payload carries item and slot, and the
handler resolves the occurrence from the store. **Background refresh queues its
successor before doing any work**, so the chain survives being killed mid-run.

Both schedulers sit behind protocols and the whole layer is tested against
fakes.

## Phase 3: the surfaces

**Widget extension.** A second target compiling `Core`, which is what the
`nonisolated` sweep was for: this process runs the engine off the main actor.
Large and medium Today widgets, accessory rectangular for what is next,
accessory circular for the day's progress. `AppIntentTimelineProvider` rather
than `TimelineProvider`, because only the former has genuinely `async`
requirements — the latter's async methods are wrappers over a completion
handler that is not `Sendable` and so cannot reach the store.

**Completion circles are real buttons.** `Button(intent:)` against the shared
store, so a tick works with the app closed.

**Live Activity.** Lock screen card and Dynamic Island. Current item with Done
and Snooze, the next three below, the day's count in the corner.
`LiveActivityController.refresh()` is the entire policy: it decides by itself
whether to start, update, restart or end, so launch, a completion, foreground
and the background task all just call it. It restarts at seven hours rather
than waiting for the system to kill the activity at about eight, and replaces
rather than updates a card whose day has rolled over. `ContentState` is built
in exactly one place, which is what makes phase 4's push updater a drop-in:
the server sends the same value.

**Location triggers.** `CLMonitor` reconciled like the notifications are. A
place reminder has no time, so nothing can be scheduled ahead — the region
firing is the trigger, and it raises the alert through the same content builder
as everything else. The 20-region cap is carried out to the app rather than
computed and discarded.

Both phase 1 deferrals are closed: the Place reminder preset is offered and
the location editor exists, because there is now something behind them.

### Motion, decided by frequency

Applying the design skill's frequency table rather than taste:

- A completion circle is tapped tens of times a day, so it gets no
  celebration — a symbol swap, and `.invalidatableContent()` so the tap is
  acknowledged while the timeline reloads. That latency is the only thing here
  that genuinely needs covering.
- No stagger on widget rows. Decorative, on a surface seen dozens of times a
  day.
- The Live Activity changes while the user is not looking at it, so the current
  item crossfades on identity and nothing slides.
- One free-running number animates: the done count.
- The Dynamic Island's expansion spring belongs to the system.

## What the tests caught

Three real product bugs, none of which would have been found by reading:

1. **A started timer went invisible.** A relative timer has no lead time, and
   the visibility rule was `now >= trigger - leadTime`, so a running laundry
   timer read as `.upcoming` for its whole countdown and would have dropped off
   the lock screen until the moment it fired. A started timer is now `.active`.

2. **A quota habit created mid-week produced nothing until the next week.**
   Ordinals were guarded on "is this day at or after the anchor day" before the
   frequency was consulted. A quota counts whole periods, and the week holding
   the anchor starts before the anchor, so the current week was thrown away.
   Create "Gym, three times a week" on a Tuesday and it was invisible until
   Sunday.

3. **The store could silently fall back to memory.** With the App Group
   entitlement unavailable, `DataStore` asked SwiftData for its default
   location — Application Support, which does not exist in a fresh container
   and which SwiftData will not create. Harmless in CI, data loss on a device.

Two more found by reading rather than by running: Someday and Waiting-for items
leaked into Today, and `TodayView` ran the engine six times per render.

## Phases 4 and 5

**Push updater** (`server/`) — a Cloudflare Worker that moves the card on while
the app is closed and has never been told what any item is called. The day's
items live in the activity's static attributes, which never travel; the push
carries `{currentIndex, doneCount, totalCount}`. Tests on both sides assert no
title appears in the wire format. Opt-in: with no endpoint configured the app
makes no network calls at all.

**Store readiness** (`docs/`) — privacy manifest on both targets declaring the
one required-reason API actually used, localized usage strings, the privacy
policy text, the App Store listing in both languages with a screenshot plan and
review notes, and a pre-submission checklist split by what is verified, what
needs a device, and what needs your Apple account.

**The screens that were missing** — Settings, the weekly review and onboarding.
The review's numbers are engine work with six tests of their own.

## Decisions made

1. **Settings are stored as one JSON blob** on `Item`, not thirty SwiftData
   attributes. The engine always reads the whole value and item counts are
   small. Cost: settings cannot appear in a `#Predicate`; filtering is in Swift.

2. **The engine sees only value types.** Every engine test runs without a model
   container, and the widget process will run the same code in phase 3.

3. **A recurring item is outstanding once.** When a newer occurrence arrives the
   older one closes as missed, even under "keep it until I do it" — otherwise a
   daily item set to stay until done stacks up one copy per day. One-off items
   are untouched. *Open question 1.*

4. **Roll-over keeps the occurrence's identity** — the trigger walks forward a
   day at a time rather than spawning a new row, so history stays attached.
   Note this makes roll-over a no-op for recurring items, since decision 3
   already hands the day over to the next occurrence.

5. **Quota pacing:** behind when the number still owed is at least the number of
   days left, counting today. Never on day one, never once the quota is met.

6. **An event that has started is not "missed"** — the state is `.missed` but
   `concludedNaturally` is set and Today files it under Done. *Open question 2.*

7. **Escalation stops below alarm.** Nothing silently promotes itself to a real
   alarm.

8. **Notification budget is 60, not 64.** Headroom so a snooze scheduled from
   the lock screen is never refused. Primaries and pre-alerts claim the budget
   before repeat nags; mandatory before normal.

## Deliberately not built yet

- **Location triggers.** The engine handles them and reports the 20-region
  overflow, but there is no `CLMonitor` wiring and no map picker, so the Place
  reminder preset is left out of the create flow and `.location` out of the
  editor. No control in the UI does nothing.
Nothing is deferred any more. Location triggers landed in phase 3 and the
Settings, review and onboarding screens in phase 5, so there is no control in
the app that does nothing.

The honest gap is different: **the surfaces have never been run.** The engine
has 13 test suites; the widgets, the Live Activity, AlarmKit and CoreLocation
have code that compiles against the right APIs and follows the documented
contracts, which is a weaker claim. Only a physical device closes that, and
`docs/CHECKLIST.md` lists exactly what to try.

## Open questions for you

1. **Recurring items that stay until done (decision 3).** Close yesterday's copy
   when today's arrives, always? Or a per-item choice?
2. **Events that have started (decision 6).** Quietly move to Done, or a
   separate "Earlier" section so Done stays honest?
3. **Quiet hours drop, they do not defer.** Should a 02:00 alert instead fire
   when quiet hours end?
4. **App name, bundle ID, Apple Team ID.**
5. **Escalation shape.** Standard jumps straight to time-sensitive on the first
   nag, because there is only one rung between them. More rungs?

## Tooling

Design and Swift skills are vendored in `.agents/skills` (`skills-lock.json`
pins them); reinstall with `npx skills add emilkowalski/skills`. The
`.claude/skills` symlinks are machine-specific and not committed.

## Manual steps for you

- [ ] Decide the app name and bundle ID, and give me your Apple Team ID.
- [ ] Register the App Group in the Apple developer portal and enable the App
      Groups capability for the app ID.
- [ ] Replace `icon-1024.png` with a real icon.
- [ ] Enable three capabilities on the app ID and target: **App Groups**,
      **Background Modes** (Background fetch), **Time Sensitive Notifications**.
- [ ] Check whether AlarmKit needs a request-only entitlement from Apple. One
      source says it does; Apple's own documentation only mentions
      `NSAlarmKitUsageDescription`, which is already in Info.plist. Worth
      settling before submission rather than at review.
- [ ] **A physical device is now needed** to exercise phase 2 properly.
      Notifications can be faked in the simulator; AlarmKit ringing through
      silent mode, a Focus breaking through, and background refresh actually
      firing cannot.
