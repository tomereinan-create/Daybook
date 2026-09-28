# Progress

## Status

**Phase 1 (Foundation) — code complete, not yet compiled.**

Everything in this repository was written on a Windows machine. There is no
Swift toolchain, no iOS SDK and no simulator here, so nothing has been built or
run. `.github/workflows/ios.yml` runs `xcodegen generate` and `xcodebuild test`
on a macOS runner and is the intended way to verify it; see
[First build](#first-build).

## Placeholders

Four values, all in one place — `project.yml`, under `settings.base`:

| Setting | Current value |
|---|---|
| `APP_NAME` | `Daybook` |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.tomereinan.daybook` |
| `APP_GROUP_ID` | `group.com.tomereinan.daybook` |
| `DEVELOPMENT_TEAM` | empty — your Apple Team ID |

Change them, run `xcodegen generate`, and the app, entitlements and Info.plist
all follow. The app icon (`App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`)
is a flat indigo square, generated as a stand-in — replace it.

## What is built

### Data model (`Core/Model`)

Settings are orthogonal value types: `Trigger`, `Recurrence`, `Visibility`,
`Alerting`, `Dismissal`, plus priority, quiet-hours policy and steps, gathered
in `ItemSettings`. `PresetKind.defaultSettings(reference:calendar:)` is the
*only* place a preset means anything — it returns a bag of defaults and is
never consulted again. No engine code branches on the preset.

### Scheduling engine (`Core/Engine`)

Pure Foundation, no UI, no SwiftData, injectable `Calendar` and an explicit
`now` on every call.

- `OccurrenceGenerator` — recurrence to concrete occurrences. Ordinals are
  computed in closed form, so the thousandth occurrence costs what the first
  does.
- `StateResolver` — effective trigger (after snooze, manual start and
  roll-over), window end, and one of eight states.
- `QuotaPacer` — the behind-pace rule for flexible habits.
- `SurfacePlanner` — what each surface shows, in order, capped per surface.
- `NotificationPlanner` — the rolling window, pre-alerts, nags, escalation,
  quiet hours, alarm routing, and the notification budget.
- `CompletionService` — pure record transformations for done / reopen / snooze
  / start, including routine step advancement and quota tallying.
- `ScheduleEngine` — the facade every surface talks to.

### Storage (`Core/Persistence`)

SwiftData `Item` and `OccurrenceRecord`, an App Group container with a
documented fallback, and `DataStore` as the only bridge between storage and the
engine's value types.

### App (`App`)

Today screen grouped into Now / Later today / Anytime / Done / Missed, with
tap-to-complete, swipe to snooze and swipe to start. Preset picker, full
create/edit form with an Advanced section exposing every setting, and an All
items list grouped by kind. English and Hebrew throughout
(`App/Resources/Localizable.xcstrings`, 137 keys), RTL-safe layout, Dynamic
Type, VoiceOver labels on the controls that need them.

### Tests (`Tests`)

Six suites over the engine: generation, DST and time zones, state resolution,
quota pacing and routines, notification planning and the budget cap, surfaces
and day plans, presets. All deterministic — fixed calendars, fixed instants, no
`Date()` anywhere.

## Decisions made

1. **Settings are stored as one JSON blob** on `Item`, not as thirty SwiftData
   attributes. The engine always reads the whole settings value, item counts
   are small, and this keeps migrations simple. Cost: settings cannot be used
   in a `#Predicate`. Filtering happens in Swift.

2. **The engine sees only value types.** `ItemSnapshot` and
   `OccurrenceStateRecord` are `Sendable` structs projected from the SwiftData
   models. Every engine test runs without a model container, and the widget
   process will be able to run the same code later.

3. **A recurring item is outstanding once.** When a newer occurrence of the same
   item arrives, the older one closes as missed even if its `onMissed` policy
   is "keep it until I do it" — otherwise a daily "brush teeth" set to stay
   until done would stack up one unfinished copy per day. One-off items are
   untouched and really do wait forever. *This is a product decision I made;
   see open question 1.*

4. **Roll-over keeps the occurrence's identity.** Rather than generating a new
   occurrence tomorrow, the trigger walks forward a day at a time until its
   window covers the present. Completion history stays attached to one row.

5. **Quota pacing rule:** you are behind when the number of times still owed is
   at least the number of days left in the period, counting today. Three times
   a week only nudges on Friday if you have done fewer than one. Never nudges
   on day one, never once the quota is met.

6. **An event that has started is not "missed".** The engine state is `.missed`
   (its window closed without completion, which is mechanically true), but
   `concludedNaturally` is set and the Today screen files it under Done rather
   than Missed. *See open question 2.*

7. **Escalation stops below alarm.** An escalating item climbs to
   time-sensitive and stays there. Nothing silently promotes itself into a real
   alarm.

8. **Notification budget is 60, not 64.** Headroom so a snooze scheduled from
   the lock screen is never refused. Primary alerts and pre-alerts claim the
   budget before any repeat nag does; mandatory items claim it before normal
   ones.

## Deliberately not built yet

- **Location triggers.** The engine handles them end to end and
  `locationMonitoringPlan` already reports the 20-region overflow, but there is
  no `CLMonitor` wiring and no map picker, so the *Place reminder* preset is
  left out of the create flow and the `.location` field is left out of the
  editor. Both are one-line removals once phase 3 lands. Nothing in the UI
  offers a control that does nothing.
- **`afterPrevious` triggers** as a standalone kind. Routines work through
  `steps`, which covers the brief's Routine preset; chaining separate items
  comes later.
- **Settings screen, weekly review, onboarding.** Phase 5 in the brief; the
  quiet-hours value already has storage and an engine path.
- **Widget extension target.** Phase 3. The App Group and the value-type engine
  are in place so it drops in without restructuring.

## Open questions for you

1. **Recurring items that stay until done (decision 3).** I close yesterday's
   copy when today's arrives. Is that right for *every* recurring item, or do
   you want a per-item choice — "one at a time" versus "they pile up"? Piling
   up is what a strict reading of "convert to an open task that stays until
   done" implies, but it makes the widget unusable for anything daily.

2. **Events that have started (decision 6).** Right now an event that began
   without being marked done quietly moves to Done. The alternative is a
   separate "Earlier" section so Done stays honest. Which do you want to see?

3. **Quiet hours drop, they do not defer.** An item that respects quiet hours
   and is due at 02:00 gets no notification at all — it is still on the widget
   and the lock screen card. Should it instead fire at the end of quiet hours?

4. **App name and bundle ID.** `Daybook` / `com.tomereinan.daybook` are mine,
   not yours. Also: one Apple Team ID when you have it.

5. **Escalation shape.** An item at "standard" that escalates jumps to
   time-sensitive on its first nag and stays there, because there is only one
   rung between them. Do you want more rungs (for example, sound on the third
   nag), or is this enough?

## First build

You need a Mac or a GitHub repository, because nothing here can compile on
Windows.

On a Mac:

```bash
brew install xcodegen
xcodegen generate
xcodebuild test -scheme Daybook -destination 'platform=iOS Simulator,name=iPhone 17'
```

Through CI: push this repository to GitHub and the workflow runs the same three
commands on a macOS runner. Expect the first run to surface compile errors —
none of this has been through a compiler.

## Manual steps for you

- [ ] Decide the app name and bundle ID, and give me your Apple Team ID.
- [ ] Register the App Group (`group.…`) in the Apple developer portal and
      enable the App Groups capability for the app ID.
- [ ] Create the GitHub repository and push, if you want CI to verify the build.
- [ ] Replace `icon-1024.png` with a real icon.
- [ ] Nothing needs a physical device yet. Phase 2 (alarms) and phase 3 (Live
      Activity, widgets, location) both do — AlarmKit and ActivityKit cannot be
      exercised properly in the simulator.
