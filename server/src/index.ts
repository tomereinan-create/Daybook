import { type ApnsCredentials, type ContentState, sendUpdate, signProviderToken, updatePayload } from './apns';

/// Moves a Daybook lock screen card on while the app is closed.
///
/// What this service knows: a push token, a list of times, and an index at
/// each time. It has never seen a task title and cannot resolve an index into
/// one — the card's text lives in the activity's static attributes, on the
/// phone. Losing this database would leak nothing but a routine's shape.

interface RegisterStep {
	at: number;
	index: number;
	doneCount: number;
	totalCount: number;
}

interface RegisterBody {
	token: string;
	schedule: { steps: RegisterStep[] };
}

/** How long after its moment a push is still worth delivering. */
const EXPIRY_SECONDS = 15 * 60;
/** The card admits it is stale this long after a push lands. */
const STALE_AFTER_SECONDS = 60 * 60;
/** Apple refuses more than one new provider token per twenty minutes. */
const PROVIDER_TOKEN_TTL = 40 * 60;
/** A single cron tick will not try to send more than this. */
const BATCH_LIMIT = 200;

export default {
	async fetch(request: Request, env: Env, _ctx: ExecutionContext): Promise<Response> {
		const url = new URL(request.url);

		if (url.pathname === '/health') {
			return Response.json({ ok: true });
		}

		if (url.pathname === '/register' && request.method === 'POST') {
			try {
				return await register(request, env);
			} catch (error) {
				console.error({ message: 'register failed', error: String(error) });
				return Response.json({ error: 'registration failed' }, { status: 500 });
			}
		}

		return new Response('Not found', { status: 404 });
	},

	async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
		// The tick has to return promptly; the sending continues under
		// waitUntil rather than being abandoned halfway.
		ctx.waitUntil(deliverDue(env, Math.floor(Date.now() / 1000)));
	},
} satisfies ExportedHandler<Env>;

// MARK: - Registration

async function register(request: Request, env: Env): Promise<Response> {
	if (!(await hasValidSecret(request, env))) {
		return Response.json({ error: 'unauthorized' }, { status: 401 });
	}

	const body = (await request.json()) as RegisterBody;
	if (typeof body?.token !== 'string' || !/^[0-9a-f]{32,200}$/i.test(body.token)) {
		return Response.json({ error: 'bad token' }, { status: 400 });
	}
	const steps = Array.isArray(body.schedule?.steps) ? body.schedule.steps : [];
	if (steps.length > 100) {
		return Response.json({ error: 'too many steps' }, { status: 400 });
	}

	// The app re-registers the whole day whenever it restarts the activity, so
	// the newest registration replaces the old one outright rather than
	// merging into it.
	const statements = [
		env.DB.prepare('DELETE FROM steps WHERE token = ?').bind(body.token),
		...steps
			.filter((step) => Number.isFinite(step.at) && Number.isInteger(step.index))
			.map((step) =>
				env.DB.prepare(
					'INSERT OR REPLACE INTO steps (token, at, idx, done_count, total_count, sent_at) VALUES (?, ?, ?, ?, ?, NULL)',
				).bind(
					body.token,
					Math.floor(step.at),
					step.index,
					step.doneCount ?? 0,
					step.totalCount ?? 0,
				),
			),
	];
	await env.DB.batch(statements);

	return Response.json({ ok: true, steps: statements.length - 1 });
}

/**
 * Compared in constant time. A plain `===` on a secret leaks its length and,
 * byte by byte, its contents.
 */
async function hasValidSecret(request: Request, env: Env): Promise<boolean> {
	const provided = request.headers.get('x-daybook-key') ?? '';
	const expected = env.REGISTRATION_SECRET;
	if (provided.length !== expected.length) return false;

	const encoder = new TextEncoder();
	return crypto.subtle.timingSafeEqual(
		encoder.encode(provided).buffer as ArrayBuffer,
		encoder.encode(expected).buffer as ArrayBuffer,
	);
}

// MARK: - Delivery

export async function deliverDue(env: Env, now: number): Promise<void> {
	const due = await env.DB.prepare(
		'SELECT token, at, idx, done_count, total_count FROM steps WHERE sent_at IS NULL AND at <= ? ORDER BY at ASC LIMIT ?',
	)
		.bind(now, BATCH_LIMIT)
		.all<{ token: string; at: number; idx: number; done_count: number; total_count: number }>();

	const rows = due.results ?? [];
	if (rows.length === 0) return;

	// Several steps for one card can come due together after an outage. Only
	// the last one is true, so send that and retire the rest unsent — replaying
	// the morning at lunchtime would be worse than missing it.
	const latest = new Map<string, (typeof rows)[number]>();
	for (const row of rows) {
		const existing = latest.get(row.token);
		if (!existing || row.at > existing.at) latest.set(row.token, row);
	}

	const providerToken = await providerTokenFor(env, now);
	const credentialsMissing = providerToken === null;
	if (credentialsMissing) {
		console.error({ message: 'no APNs credentials configured; nothing sent' });
		return;
	}

	const settled: string[] = [];
	const dead: string[] = [];

	for (const row of latest.values()) {
		const state: ContentState = {
			currentIndex: row.idx,
			doneCount: row.done_count,
			totalCount: row.total_count,
		};
		const result = await sendUpdate({
			host: env.APNS_HOST,
			topic: env.APNS_TOPIC,
			deviceToken: row.token,
			providerToken,
			body: updatePayload(state, now, STALE_AFTER_SECONDS),
			expiration: row.at + EXPIRY_SECONDS,
		});

		if (result.gone) {
			dead.push(row.token);
		} else if (!result.ok) {
			console.error({ message: 'apns refused', status: result.status, reason: result.reason });
		}
		settled.push(row.token);
	}

	const statements = [
		// Everything that was due is now settled, whether it was sent or
		// superseded, so the next tick does not see it again.
		env.DB.prepare('UPDATE steps SET sent_at = ? WHERE sent_at IS NULL AND at <= ?').bind(now, now),
		...dead.map((token) => env.DB.prepare('DELETE FROM steps WHERE token = ?').bind(token)),
	];
	await env.DB.batch(statements);

	console.log({ message: 'delivered', cards: settled.length, dropped: dead.length });
}

/**
 * The signed APNs token, cached in the database rather than in a module
 * variable — a Worker isolate is too short-lived and too plural for an
 * in-memory cache to help, and request-scoped globals are how Workers leak
 * state between requests.
 */
async function providerTokenFor(env: Env, now: number): Promise<string | null> {
	const cached = await env.DB.prepare('SELECT value, expires_at FROM cache WHERE key = ?')
		.bind('apns_token')
		.first<{ value: string; expires_at: number }>();

	if (cached && cached.expires_at > now) return cached.value;

	const credentials = credentialsFrom(env);
	if (!credentials) return null;

	const token = await signProviderToken(credentials, now);
	await env.DB.prepare(
		'INSERT OR REPLACE INTO cache (key, value, expires_at) VALUES (?, ?, ?)',
	)
		.bind('apns_token', token, now + PROVIDER_TOKEN_TTL)
		.run();
	return token;
}

function credentialsFrom(env: Env): ApnsCredentials | null {
	if (!env.APNS_PRIVATE_KEY || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) return null;
	return {
		privateKeyPem: env.APNS_PRIVATE_KEY,
		keyId: env.APNS_KEY_ID,
		teamId: env.APNS_TEAM_ID,
	};
}
