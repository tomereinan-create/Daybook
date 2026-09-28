# Putting Daybook on your iPhone without an Apple Developer account

This gets the app onto your phone from Windows, for nothing. The trade is that
the install expires after seven days and **the widgets and lock screen card
will not work**. Read "What you will not get" before spending time on it.

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

## What you will not get

Free provisioning cannot grant the **App Groups** entitlement. The app and its
widget extension are separate processes that share your data through an App
Group container, so without it they cannot see each other's data.

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

So this is worth doing to try the app and find bugs in the parts that exist.
It is not worth doing to evaluate the product, because the product is the
widget and the lock screen card, and neither will run.

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
