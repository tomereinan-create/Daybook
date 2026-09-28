-- One row per live activity the app has registered.
--
-- There is deliberately nothing here that says what the user's day contains:
-- a push token, a time, and an index into a list this server has never seen.
CREATE TABLE IF NOT EXISTS steps (
  token       TEXT    NOT NULL,
  at          INTEGER NOT NULL,   -- unix seconds
  idx         INTEGER NOT NULL,   -- index into the activity's frozen item list
  done_count  INTEGER NOT NULL,
  total_count INTEGER NOT NULL,
  sent_at     INTEGER,            -- null until delivered
  PRIMARY KEY (token, at)
);

-- The cron's only query: what is due and not yet sent.
CREATE INDEX IF NOT EXISTS steps_due ON steps (at) WHERE sent_at IS NULL;

-- A tiny key/value table, used for the signed APNs token. Apple asks for at
-- most one new token per twenty minutes, and a Worker isolate is too
-- short-lived and too plural to cache it in memory.
CREATE TABLE IF NOT EXISTS cache (
  key        TEXT PRIMARY KEY,
  value      TEXT    NOT NULL,
  expires_at INTEGER NOT NULL
);
