'use strict';
const crypto = require('crypto');
const express = require('express');
const { pool } = require('./db');
const { ah, HttpError, isEmail } = require('./util');
const { issueToken, verifyToken } = require('./tokens');

/** GOOGLE_CLIENT_ID: comma-separated OAuth client IDs. The FIRST must be the Web client ID. */
const googleClientIds = () => (process.env.GOOGLE_CLIENT_ID || '').split(',').map((s) => s.trim()).filter(Boolean);
const devAuthOn = () => process.env.ALLOW_DEV_AUTH === 'true';

/**
 * Upserts the user, turns any pending invitations for their email into memberships
 * (and deletes them), then issues a signed session token. One transaction so a
 * half-created account can't exist.
 */
async function createSession({ email, displayName, provider }) {
  const client = await pool.connect();
  let user;
  try {
    await client.query('BEGIN');
    ({ rows: [user] } = await client.query(
      `INSERT INTO users (id, email, display_name, provider)
       VALUES ($1, lower($2), $3, $4)
       ON CONFLICT (email) DO UPDATE SET display_name = EXCLUDED.display_name, provider = EXCLUDED.provider
       RETURNING id, email, display_name, provider`,
      [crypto.randomUUID(), email, displayName, provider],
    ));
    await client.query(
      `WITH accepted AS (
         DELETE FROM invitations WHERE email = $2 RETURNING folder_id, role
       )
       INSERT INTO folder_members (folder_id, user_id, role)
       SELECT a.folder_id, $1, a.role FROM accepted a
       JOIN folders f ON f.id = a.folder_id AND f.deleted_at IS NULL
       ON CONFLICT DO NOTHING`,
      [user.id, user.email],
    );
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
  knownUsers.set(user.id, Date.now());
  const { token, expiresAt } = issueToken(user);
  return { token, expires_at: expiresAt.toISOString(), user };
}

const authRouter = express.Router();

/** Public: which sign-in methods this server offers. The apps and web read it before sign-in. */
authRouter.get('/config', (_req, res) => {
  res.set('Cache-Control', 'public, max-age=300').json({
    google_client_id: googleClientIds()[0] || null,  // Web client ID: GIS on the web, serverClientId on Android
    apple: Boolean(process.env.APPLE_CLIENT_ID),
    dev: devAuthOn(),
  });
});

// Development sign-in: trusts the email it is given. Disabled unless ALLOW_DEV_AUTH=true.
authRouter.post('/dev', ah(async (req, res) => {
  if (!devAuthOn()) throw new HttpError(403, 'Dev sign-in is turned off on this server');
  const email = String(req.body.email || '').trim();
  if (!isEmail(email)) throw new HttpError(400, 'Enter a valid email address');
  const displayName = String(req.body.display_name || '').trim().slice(0, 60) || email.split('@')[0];
  const provider = ['google', 'apple'].includes(req.body.provider) ? req.body.provider : 'dev';
  res.json(await createSession({ email, displayName, provider }));
}));

// Google sign-in: the app / web page sends the ID token it got from Google.
authRouter.post('/google', ah(async (req, res) => {
  const audience = googleClientIds();
  if (!audience.length) throw new HttpError(501, 'Google sign-in is not configured on this server');
  const { OAuth2Client } = require('google-auth-library');
  let payload;
  try {
    const ticket = await new OAuth2Client().verifyIdToken({ idToken: String(req.body.id_token || ''), audience });
    payload = ticket.getPayload();
  } catch {
    throw new HttpError(401, 'Google sign-in token is invalid or expired');
  }
  if (!payload || !payload.email || !payload.email_verified) {
    throw new HttpError(401, 'Your Google account email is not verified');
  }
  const displayName = String(payload.name || payload.email.split('@')[0]).slice(0, 60);
  res.json(await createSession({ email: payload.email, displayName, provider: 'google' }));
}));

// Apple sign-in: the app sends the identity token from sign_in_with_apple.
authRouter.post('/apple', ah(async (req, res) => {
  const audience = process.env.APPLE_CLIENT_ID;
  if (!audience) throw new HttpError(501, 'Apple sign-in is not configured on this server');
  const { createRemoteJWKSet, jwtVerify } = await import('jose');
  const jwks = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));
  let payload;
  try {
    ({ payload } = await jwtVerify(String(req.body.identity_token || ''), jwks, {
      issuer: 'https://appleid.apple.com',
      audience: audience.split(',').map((s) => s.trim()),
    }));
  } catch {
    throw new HttpError(401, 'Apple sign-in token is invalid or expired');
  }
  if (!payload.email) throw new HttpError(401, 'Apple did not share an email for this account');
  // Apple only sends the user's name on the very first sign-in, so the app forwards it.
  const displayName = String(req.body.display_name || '').trim().slice(0, 60) || String(payload.email).split('@')[0];
  res.json(await createSession({ email: String(payload.email), displayName, provider: 'apple' }));
}));

/**
 * Tokens are verified without a database round trip. The only lookup is "does this account
 * still exist" (it may have been deleted), cached for a few minutes per user.
 */
const knownUsers = new Map();
const KNOWN_TTL_MS = 5 * 60_000;

const requireAuth = ah(async (req, _res, next) => {
  const header = req.get('authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) throw new HttpError(401, 'Sign in required');
  const claims = verifyToken(token);
  if (!claims) throw new HttpError(401, 'Your session has expired. Sign in again.');

  const seen = knownUsers.get(claims.id);
  if (!seen || Date.now() - seen > KNOWN_TTL_MS) {
    const { rows: [user] } = await pool.query('SELECT email FROM users WHERE id = $1', [claims.id]);
    if (!user) {
      knownUsers.delete(claims.id);
      throw new HttpError(401, 'This account no longer exists. Sign in again.');
    }
    if (knownUsers.size > 10_000) knownUsers.clear();
    knownUsers.set(claims.id, Date.now());
  }
  req.user = { id: claims.id, email: claims.email };
  next();
});

/**
 * Permanently deletes the signed-in account (required by Google Play and the App Store for
 * apps with sign-in): their folders, boards they own, their links and memberships.
 * Pins they added to friends' boards are removed too. Devices keep their local copy.
 */
const accountRouter = express.Router();
accountRouter.delete('/', ah(async (req, res) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // Their own links, plus everything on boards they own (friends lose those boards).
    await client.query(
      'DELETE FROM items WHERE owner_id = $1 OR folder_id IN (SELECT id FROM folders WHERE owner_id = $1)',
      [req.user.id]);
    await client.query('DELETE FROM folders WHERE owner_id = $1', [req.user.id]);
    await client.query('DELETE FROM users WHERE id = $1', [req.user.id]);
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
  knownUsers.delete(req.user.id);
  res.json({ status: 'deleted' });
}));

module.exports = { authRouter, accountRouter, requireAuth, createSession };
