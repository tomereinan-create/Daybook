import { describe, expect, it } from 'vitest';
import { signProviderToken, updatePayload } from '../src/apns';

/// The two things worth testing without a network: that a signed token is a
/// real, verifiable ES256 JWT, and that the push body carries numbers only.

/** A throwaway P-256 key, generated per run. Never a real one. */
async function testKeyPem(): Promise<{ pem: string; publicKey: CryptoKey }> {
	const pair = (await crypto.subtle.generateKey(
		{ name: 'ECDSA', namedCurve: 'P-256' },
		true,
		['sign', 'verify'],
	)) as CryptoKeyPair;
	const pkcs8 = (await crypto.subtle.exportKey('pkcs8', pair.privateKey)) as ArrayBuffer;
	const base64 = Buffer.from(new Uint8Array(pkcs8)).toString('base64').replace(/(.{64})/g, '$1\n');
	return {
		pem: `-----BEGIN PRIVATE KEY-----\n${base64}\n-----END PRIVATE KEY-----`,
		publicKey: pair.publicKey,
	};
}

function decodeSegment(segment: string): unknown {
	const padded = segment.replace(/-/g, '+').replace(/_/g, '/');
	return JSON.parse(Buffer.from(padded, 'base64').toString('utf8'));
}

describe('provider token', () => {
	it('is a three-part JWT with the header Apple expects', async () => {
		const { pem } = await testKeyPem();
		const token = await signProviderToken(
			{ privateKeyPem: pem, keyId: 'ABC1234567', teamId: 'TEAM123456' },
			1_790_000_000,
		);

		const parts = token.split('.');
		expect(parts).toHaveLength(3);
		expect(decodeSegment(parts[0])).toEqual({ alg: 'ES256', kid: 'ABC1234567' });
		expect(decodeSegment(parts[1])).toEqual({ iss: 'TEAM123456', iat: 1_790_000_000 });
	});

	it('produces a signature that verifies against the key', async () => {
		const { pem, publicKey } = await testKeyPem();
		const token = await signProviderToken(
			{ privateKeyPem: pem, keyId: 'K', teamId: 'T' },
			1_790_000_000,
		);

		const [header, claims, signature] = token.split('.');
		const raw = Uint8Array.from(
			Buffer.from(signature.replace(/-/g, '+').replace(/_/g, '/'), 'base64'),
		);

		// ES256 signatures are the raw r‖s pair: 64 bytes, not DER.
		expect(raw.byteLength).toBe(64);
		const verified = await crypto.subtle.verify(
			{ name: 'ECDSA', hash: 'SHA-256' },
			publicKey,
			raw,
			new TextEncoder().encode(`${header}.${claims}`),
		);
		expect(verified).toBe(true);
	});

	it('is base64url, with no padding or URL-unsafe characters', async () => {
		const { pem } = await testKeyPem();
		const token = await signProviderToken({ privateKeyPem: pem, keyId: 'K', teamId: 'T' }, 1);
		expect(token).not.toMatch(/[+/=]/);
	});
});

describe('update payload', () => {
	it('carries an index and two counts, and nothing else', () => {
		const body = JSON.parse(
			updatePayload({ currentIndex: 2, doneCount: 3, totalCount: 11 }, 1_790_000_000, 3600),
		);

		expect(body.aps.event).toBe('update');
		expect(body.aps['content-state']).toEqual({
			currentIndex: 2,
			doneCount: 3,
			totalCount: 11,
		});
		// The whole privacy claim, as an assertion: the only keys in the state
		// are numbers the server was given, never anything it could read.
		expect(Object.keys(body.aps['content-state']).sort()).toEqual([
			'currentIndex',
			'doneCount',
			'totalCount',
		]);
	});

	it('sets a stale date so a dropped push degrades into visibly stale', () => {
		const body = JSON.parse(updatePayload({ currentIndex: 0, doneCount: 0, totalCount: 1 }, 1000, 3600));
		expect(body.aps['stale-date']).toBe(4600);
		expect(body.aps.timestamp).toBe(1000);
	});
});
