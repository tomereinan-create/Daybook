# Pre-submission checklist

Three states: **done** is in the repo and verified by CI; **needs a device** is
written and compiling but has never been run by anyone; **yours** needs an
account, a decision or a credential I should not handle.

---

## Done

- [x] Privacy manifest on both targets, declaring the one required-reason API
      actually used — `NSPrivacyAccessedAPICategoryUserDefaults`, reason
      **1C8F.1** (App Group, not the `CA92.1` most examples copy).
- [x] `NSPrivacyTracking` false, no tracking domains, no collected data types.
- [x] Usage strings for all three permissions, in English and Hebrew, each
      saying what the permission buys rather than that it is required.
- [x] Every permission survivable when refused. Settings names what is lost in
      each case and offers the only useful action, which is opening iOS
      Settings.
- [x] No dead ends: four tabs, every screen reachable, no control that does
      nothing. The two phase-1 deferrals (place reminders, the location
      editor) were closed in phase 3 rather than left as stubs.
- [x] English and Hebrew throughout, 250 strings, RTL layout.
- [x] Engine covered by 13 test suites, green on every push.
- [x] Push updater is opt-in and content-free by construction, with tests
      asserting no task title appears in the wire format.
- [x] App icon: a clay-and-paper "D", 1024x1024, opaque RGB with no alpha
      channel (the App Store rejects icons that have one). Drawn as geometry
      by `scripts/icon-d.mjs`, so it re-renders cleanly at any size.

## Needs a device

Nothing in this section has ever run. It compiles against the right APIs and
follows the documented contracts, which is a weaker claim than "it works".

- [ ] **Widgets.** Add both to the first home page. Check the completion
      circle ticks with the app closed, and that the timeline redraws at the
      next trigger rather than only on the hour.
- [ ] **Live Activity.** Confirm the card appears, that Done and Snooze work
      from the lock screen without unlocking, and that it restarts rather than
      vanishing after seven hours.
- [ ] **AlarmKit.** A wake-up must ring through silent mode and through a
      Focus. This cannot be tested in the simulator at all.
- [ ] **Place reminders.** Walk into and out of a real region. Confirm Always
      is requested only after When In Use, and that refusing it leaves
      everything else working.
- [ ] **Background refresh.** Leave the phone alone for a few hours and confirm
      the day has moved on.
- [ ] **Dynamic Type at the largest accessibility sizes.** Widgets clip rather
      than scroll; check nothing important is cut off.
- [ ] **VoiceOver pass** over Today, the editor and the widgets.
- [ ] **Both themes**, on the lock screen as well as in the app.

## Yours

- [ ] **Apple Developer Program membership.** Nothing below is possible
      without it.
- [ ] **Decide the name.** `Daybook` is mine and is a common English word;
      check availability in App Store Connect before committing. It is a
      four-value change in `project.yml`.
- [ ] **Bundle ID and Team ID**, same place.
- [ ] **Register the App Group** and enable three capabilities on the app ID:
      App Groups, Background Modes (Background fetch), Time Sensitive
      Notifications.
- [ ] **Settle the AlarmKit entitlement question.** One source says Apple
      issues a specific entitlement for it; Apple's own documentation mentions
      only `NSAlarmKitUsageDescription`, which is already in place. Find out
      before review rather than during it.
- [ ] **Host the privacy policy** from `docs/PRIVACY.md` at a public URL and
      put your contact email in it. Apple requires a reachable link.
- [ ] **Screenshots** — the plan is in `docs/APP_STORE.md`. Shoot on a device;
      Live Activities and alarms do not render in the simulator.
- [ ] **Nutrition label:** answer "no" to every data collection question. That
      is accurate for the shipping configuration.
- [ ] **If you ever run a shared push server** rather than your own, the label
      changes — you would then be collecting timestamps from users. As shipped,
      push is off and points at infrastructure the user controls.

---

## Things a reviewer is likely to ask about

**"The app requests Always location."** Answer: place reminders are a listed
feature and cannot work otherwise; the app asks for When In Use first and
degrades cleanly when refused. The usage string says so.

**"What is the background mode for?"** iOS holds 64 pending notifications per
app. The app schedules a rolling window and tops it up in a
`BGAppRefreshTask`. Without it, a user with many recurring items would stop
being alerted after a day or two.

**"Why does it need AlarmKit?"** One of the twelve item types is a wake-up
alarm. It is not used for ordinary reminders, which are ordinary
notifications.

The review notes in `docs/APP_STORE.md` cover how to exercise each of these,
which is worth pasting in — two of the three cannot be reached without
instructions.
