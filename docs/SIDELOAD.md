# Putting Daybook on your iPhone without an Apple Developer account

This gets the app onto your phone from Windows, for nothing. The install
expires after seven days either way. Which tool you use decides whether the
**home screen widget** works:

| Tool | Widget | Build to download |
|---|---|---|
| **AltStore** (or Impactor) | Should work — not yet confirmed on a device | `Daybook-altstore-ipa` |
| Sideloadly | Does not work | `Daybook-unsigned-ipa` |

## Why Sideloadly cannot do the widget

The widget is a second small program inside the app, and it reads your day
from storage it shares with the app (an *App Group*). Two things have to be
right, and the Diagnostics sheet in Settings shows both:

- `widget profile` must not be `none`, and `same team as app` must be `yes`.
  Sideloadly signs the app but leaves the widget without a profile, so iOS
  will not run it.
- `shared container` must be `yes`. Sideloadly does not register App Groups,
  so there is no shared storage even when the widget does run.

A free Apple ID **can** have App Groups; Apple just does not let you have
*our* name for one. AltStore and Impactor register one under a name of their
own (`group.com.tomereinan.daybook.<your team ID>`), sign the app and the
widget with it, and Daybook picks up whatever name it was given. They learn
which group to ask for from the app file itself, which is why they need the
`Daybook-altstore-ipa` build: the plain one has that information stripped
out for Sideloadly's sake.

## With AltStore (for the widget)

Once, on the PC (about fifteen minutes):

1. Install **iTunes** and **iCloud** from apple.com — the downloads on
   Apple's site, *not* the Microsoft Store versions; AltServer cannot use
   those.
2. Install **AltServer** for Windows from [altstore.io](https://altstore.io).
   It lives in the system tray.
3. Plug in the iPhone, trust the computer, and in iTunes turn on **Sync with
   this iPhone over Wi-Fi**.
4. Tray icon → **Install AltStore** → your iPhone. Enter your Apple ID.
5. On the phone: **Settings → General → VPN & Device Management** → your
   Apple ID → **Trust**. On iOS 16 and later also turn on **Settings →
   Privacy & Security → Developer Mode** and restart.

Each time:

1. From the newest green run on `main` in the repository's **Actions** tab,
   download **Daybook-altstore-ipa**, unzip it, and get
   `Daybook-sideload.ipa` onto the phone (AirDrop, iCloud Drive, or email it
   to yourself and save it to Files).
2. If an older Daybook is installed with Sideloadly, delete it first. The two
   tools sign under different names and will not replace each other.
3. Open AltStore → **My Apps** → **+** → pick `Daybook-sideload.ipa`.
4. Open Daybook once, then add the widget to the home screen.
5. Check **Settings → Diagnostics**: `shared container` should say `yes`.

AltStore refreshes the seven-day signature by itself over Wi-Fi while
AltServer is running on the PC and both are on the same network.

Limits of a free Apple ID: three sideloaded apps at once (AltStore itself is
one of them), and ten App IDs a week. Daybook uses two — the app and the
widget — and reinstalling reuses them.

**Impactor** ([github.com/khcrysalis/Impactor](https://github.com/khcrysalis/Impactor))
is the alternative that needs only iTunes, not iCloud or a tray app. Its
documentation says it registers App Groups and signs extensions the same
way; use the same `Daybook-altstore-ipa` build with it. It does not refresh
in the background, so it is reinstall-weekly like Sideloadly.

## With Sideloadly (no widget)

## What you need

- An iPhone running **iOS 26 or later**. The app will not install on anything
  older; AlarmKit does not exist before 26.
- A free Apple ID. Not a paid developer account.
- [Sideloadly](https://sideloadly.io) — free, Windows, installs over USB.
  ([AltStore](https://altstore.io) is the alternative and can refresh over
  Wi-Fi so you do not have to plug in weekly.)
- A USB cable.

## Each time (about two minutes)

1. Go to the repository's **Actions** tab and open the newest green run on
   `main`. If you just want a fresh build without changing anything, press
   **Run workflow** on the `build-and-test` workflow.
2. Download the **Daybook-unsigned-ipa** artifact from the bottom of that run's
   page. Unzip it — GitHub wraps artifacts in a zip, so you want the
   `Daybook.ipa` inside.
3. Open Sideloadly, plug in the iPhone, drag `Daybook.ipa` in.
4. Enter your Apple ID. Sideloadly signs the app with it and installs.
5. On the phone: **Settings → General → VPN & Device Management**, tap your
   Apple ID, **Trust**.

The app now works for seven days. Repeat step 1 onwards when it stops opening.

A free Apple ID can have **three** sideloaded apps at once and can register ten
app IDs a week. Daybook plus its widget extension is two of those ten each time
you reinstall, so weekly is fine and several reinstalls a day is not.

## What you will not get with Sideloadly

Sideloadly does not grant the **App Groups** entitlement, and leaves the
widget extension unsigned. The app and its widget extension are separate
processes that share your data through an App Group container, so without it
they cannot see each other's data.

The app handles this rather than breaking: the store falls back to a
process-local one, the widget shows *"Cannot read your day"*, and Settings
flags it under **What is scheduled**.

| Works | Does not |
|---|---|
| Today, create and edit, all items, weekly review, settings | Home screen widgets |
| The whole scheduling engine — recurrence, quotas, routines, timers | Lock screen Live Activity |
| Notifications, nags, escalation, snooze, actionable buttons | Time-sensitive breakthrough of a Focus |
| Place reminders, if you allow Always location | |
| Wake-up alarms, probably — AlarmKit needs only a usage string | |

So Sideloadly is fine for trying the app and finding bugs in it. For the
widget and the lock screen card, which are the product, use AltStore above.

## When you do pay the $99

Nothing about the code changes. Register the App Group and the three
capabilities in the developer portal, put your Team ID in `project.yml`, and
the same build starts working properly. At that point TestFlight is a better
delivery route than sideloading — no seven-day expiry, no cable, and I can
automate the upload.

## If something goes wrong

**"Unable to install"** — usually the seven-day profile from a previous install
is still there. Delete the app from the phone first.

**Sideloadly asks for an app-specific password** — that happens when the Apple
ID has two-factor on, which it should. Generate one at
[account.apple.com](https://account.apple.com) under Sign-In and Security.

**The app installs but immediately closes** — that is the most likely first-run
failure, and it is a real bug rather than a signing problem. Plug the phone in,
open Console.app equivalent on Windows (or use Sideloadly's log), and send me
what it says.

**Nothing has ever run.** The engine has 14 test suites behind it. The screens
have never been on a screen. Expect to find things.
