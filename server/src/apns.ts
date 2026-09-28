/// APNs, with no dependencies.
///
/// Signing an APNs token is ES256 over a two-part JWT, and WebCrypto does all
/// of it. `crypto.subtle.sign` with ECDSA/SHA-256 returns the raw r‖s pair,
/// which is exactly what JWS ES256 wants — no DER unwrapping needed.

export interface ApnsCredentials {
	/** The contents of the .p8 file, including the PEM header and footer. */
	privateKeyPem: string;
	/** The Key ID shown next to the key in the developer portal. */
	keyId: string;
	/** The ten-character Team ID. */
	teamId: string;
}

/** What a Live Activity push carries. Numbers only, by design. */
export interface ContentState {
	currentIndex: number;
	doneCount: number;
	totalCount: number;
}

function base64UrlEncode(bytes: ArrayBuffer | Uint8Array): string {
	const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
	let binary = '';
	for (const byte of view) binary += String.fromCharCode(byte);
	return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlEncodeJson(value: unknown): string {
	return base64UrlEncode(new TextEncoder().encode(JSON.stringify(value)));
}

/** PEM to DER. The .p8 Apple hands you is PKCS#8. */
function decodePrivateKey(pem: string): Uint8Array {
	const body = pem
		.replace(/-----BEGIN [^-]+-----/, '')
		.replace(/-----END [^-]+-----/, '')
		.replace(/\s+/g, '');
	const binary = atob(body);
	const bytes = new Uint8Array(binary.length);
	for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
	return bytes;
}

/**
 * Builds a fresh provider token.
 *
 * Apple rejects a token older than an hour and refuses more than one new token
 * per twenty minutes, so the caller caches this rather than calling it per
 * push.
 */
export async function signProviderToken(
	credentials: ApnsCredentials,
	issuedAt: number,
): Promise<string> {
	const key = await crypto.subtle.importKey(
		'pkcs8',
		decodePrivateKey(credentials.privateKeyPem),
		{ name: 'ECDSA', namedCurve: 'P-256' },
		false,
		['sign'],
	);

	const header = base64UrlEncodeJson({ alg: 'ES256', kid: credentials.keyId });
	const claims = base64UrlEncodeJson({ iss: credentials.teamId, iat: issuedAt });
	const signingInput = `${header}.${claims}`;

	const signature = await crypto.subtle.sign(
		{ name: 'ECDSA', hash: 'SHA-256' },
		key,
		new TextEncoder().encode(signingInput),
	);
	return `${signingInput}.${base64UrlEncode(signature)}`;
}

/**
 * The body of a Live Activity update.
 *
 * `stale-date` is what makes the card admit it is out of date rather than keep
 * showing something wrong, and it is the reason a dropped push degrades into
 * "visibly stale" instead of "quietly lying".
 */
export function updatePayload(state: ContentState, now: number, staleAfter: number): string {
	return JSON.stringify({
		aps: {
			timestamp: now,
			event: 'update',
			'content-state': state,
			'stale-date': now + staleAfter,
		},
	});
}

export interface SendResult {
	ok: boolean;
	status: number;
	/** APNs reason string, when it refused. */
	reason?: string;
	/** True when the token is dead and the row should be dropped. */
	gone: boolean;
}

export async function sendUpdate(options: {
	host: string;
	topic: string;
	deviceToken: string;
	providerToken: string;
	body: string;
	/** Seconds since epoch after which APNs should stop trying. */
	expiration: number;
}): Promise<SendResult> {
	const response = await fetch(`${options.host}/3/device/${options.deviceToken}`, {
		method: 'POST',
		headers: {
			authorization: `bearer ${options.providerToken}`,
			'apns-topic': options.topic,
			'apns-push-type': 'liveactivity',
			'apns-priority': '10',
			'apns-expiration': String(options.expiration),
			'content-type': 'application/json',
		},
		body: options.body,
	});

	if (response.ok) {
		return { ok: true, status: response.status, gone: false };
	}

	// Bounded: an APNs error body is a single short JSON object.
	const text = await response.text();
	let reason: string | undefined;
	try {
		reason = (JSON.parse(text) as { reason?: string }).reason;
	} catch {
		reason = text.slice(0, 200);
	}

	// 410 means the activity is over or the token was replaced; 400 with
	// BadDeviceToken means it was never valid. Either way, stop trying.
	const gone =
		response.status === 410 ||
		reason === 'BadDeviceToken' ||
		reason === 'Unregistered' ||
		reason === 'ExpiredToken';

	return { ok: false, status: response.status, reason, gone };
}
