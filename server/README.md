# daybook-push

Moves a Daybook lock screen card on while the app is closed.

## What it knows about you

A push token, a list of times, and a number at each time.

The card's text lives in the Live Activity's *attributes*, which are fixed on
the phone when the activity starts and are never transmitted again. Only
`ContentState` travels on a push, and here that is `{ currentIndex, doneCount,
totalCount }`. This service cannot resolve index 2 into "Physio exercises",
because it has never been told what any index means.

If this database leaked, it would reveal the shape of someone's day — that
something happens at 08:30 — and nothing about what.

Two tests hold that line: `test/apns.test.ts` asserts the payload's
`content-state` contains exactly those three numeric keys, and on the app side
`LiveActivityTests` encodes a registration and asserts no task title appears in
the JSON.

## Running it

You need an Apple Developer account, because APNs keys come from it.

```bash
npm install
npx wrangler d1 create daybook-push          # put the id in wrangler.jsonc
npx wrangler d1 migrations apply daybook-push --remote
```

Then the four secrets. **Do this yourself — the `.p8` is a credential and
should not pass through a chat window.**

```bash
npx wrangler secret put APNS_PRIVATE_KEY     # paste the whole .p8, BEGIN/END lines included
npx wrangler secret put APNS_KEY_ID          # the 10-character Key ID
npx wrangler secret put APNS_TEAM_ID         # your 10-character Team ID
npx wrangler secret put REGISTRATION_SECRET  # invent one; the app sends it back
```

Get the key from the developer portal: **Certificates, Identifiers & Profiles →
Keys → +**, tick **Apple Push Notifications service**, download the `.p8`. It
can only be downloaded once.

```bash
npm test          # pure helpers, no network
npm run typecheck
npx wrangler deploy
```

Point `APNS_HOST` at `https://api.sandbox.push.apple.com` in `wrangler.jsonc`
while testing against a development build; production builds need
`https://api.push.apple.com`. A token from one will be rejected by the other,
which is the most common reason a push silently does nothing.

## Cost

The free tier covers this. Cron Triggers, 100k Worker requests a day and 5m D1
row reads a day are all far beyond one person sending a handful of pushes a
day, and it would stay free well past thousands of users.

## Shape

- `POST /register` — the app sends `{ token, schedule: { steps: [...] } }` with
  an `x-daybook-key` header. A registration replaces that token's schedule
  outright, because the app re-registers the whole day whenever it restarts the
  activity.
- `GET /health` — returns `{ ok: true }`.
- Cron, every minute — sends what is due.

### Decisions worth knowing

**Only the newest due step is sent.** After an outage several steps for one
card come due together; replaying the morning at lunchtime is worse than
missing it, so the rest are retired unsent.

**The signed APNs token is cached in D1, not in memory.** Apple refuses more
than one new token per twenty minutes, and a Worker isolate is too short-lived
and too plural for an in-memory cache to help. Module-level mutable state is
also how Workers leak data between requests.

**A dead token drops its rows.** A 410, `BadDeviceToken` or `Unregistered`
means the activity is over; there is nothing to retry.

**A dropped push degrades into "visibly stale", not "quietly wrong".** Every
payload carries a `stale-date`, so a card that stops being updated says so.

## What is not here

No accounts, no analytics, no logging of tokens or times beyond Cloudflare's
own request logs. `observability` is on so a failing cron is visible; the log
lines carry counts, never tokens.
