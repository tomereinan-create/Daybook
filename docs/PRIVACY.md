# Privacy Policy — Daybook

**Last updated: 28 September 2026**

Short version: Daybook keeps everything on your phone. There is no account,
there is no analytics, and nothing you write is sent anywhere.

*(Host this at a public URL and put that URL in App Store Connect. Apple
requires a reachable privacy policy link before review.)*

## What Daybook stores

Everything you create — items, their settings, when you completed them, the
places you chose for place reminders — is stored on your device in a container
shared between the app and its widgets. It is not uploaded, backed up to a
server we control, or shared with anyone.

If you use iCloud Backup or a local encrypted backup, your Daybook data is
included in that backup, because the whole device is. That backup is between
you and Apple; we have no access to it.

## What Daybook sends

Nothing, by default. The app makes no network requests at all unless you turn
on lock screen updates.

### If you turn on lock screen updates

This is off unless you configure it, and it points at a server **you** run.

Even then, your task titles are never sent. The text on your lock screen card
is fixed on your phone when the card is created and is never transmitted again.
What the server receives is:

- an anonymous push token issued by Apple for that card,
- a list of times, and
- a number at each time saying which position the card should move to.

The server cannot turn position 2 back into "Physio exercises", because it was
never told what position 2 means. If its database were stolen, it would reveal
that something happens in your day at 08:30, and nothing at all about what.

When a card ends or its token is replaced, those rows are deleted.

## Permissions

| Permission | What it is for | If you refuse |
|---|---|---|
| Notifications | Alerting you about an item | Items still appear on your screens; nothing buzzes |
| Alarms (AlarmKit) | Ringing a wake-up through silent mode | Wake-up items become ordinary notifications |
| Location | Noticing you arrive at or leave a place | Place reminders do not fire; nothing else changes |

Your location is never stored or transmitted. iOS tells Daybook that you
crossed a boundary you chose; Daybook does not record where you were.

## Children

Daybook collects nothing, so there is nothing to collect from a child.

## Changes

If a future version of Daybook ever collects anything, this policy will be
updated before that version ships, and the App Store privacy label will change
to match.

## Contact

<!-- REPLACE: the email address you want in App Store Connect. -->
[YOUR CONTACT EMAIL]
