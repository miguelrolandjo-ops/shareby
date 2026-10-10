'use strict';
const crypto = require('crypto');
const express = require('express');
const { pool } = require('./db');
const { ah, HttpError, isEmail } = require('./util');

const SESSION_DAYS = 30;

/**
 * Upserts the user, turns any pending invitations for their email into memberships,
 * and issues a session token. One transaction so a half-created account can't exist.
 */
async function createSession({ email, displayName, provider }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { rows: [user] } = await client.query(
      `INSERT INTO users (id, email, display_name, provider)
       VALUES ($1, lower($2), $3, $4)
       ON CONFLICT (email) DO UPDATE SET display_name = EXCLUDED.display_name
       RETURNING id, email, display_name, provider`,
      [crypto.randomUUID(), email, displayName, provider],
    );

    await client.query(
      `INSERT INTO folder_members (folder_id, user_id, role)
       SELECT inv.folder_id, $1, inv.role
       FROM invitations inv
       JOIN folders f ON f.id = inv.folder_id AND f.deleted_at IS NULL
       WHERE inv.email = $2 AND inv.accepted_at IS NULL
       ON CONFLICT DO NOTHING`,
      [user.id, user.email],
    );
    await client.query(
      `UPDATE invitations SET accepted_at = now() WHERE email = $1 AND accepted_at IS NULL`,
      [user.email],
    );

    const token = crypto.randomBytes(32).toString('base64url');
    await client.query(
      `INSERT INTO sessions (token, user_id, expires_at)
       VALUES ($1, $2, now() + make_interval(days => $3::int))`,
      [token, user.id, SESSION_DAYS],
    );
    await client.query('COMMIT');
    return { token, user };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

const authRouter = express.Router();

// Development sign-in: trusts the email it is given. Disabled unless ALLOW_DEV_AUTH=true.
authRouter.post('/dev', ah(async (req, res) => {
  if (process.env.ALLOW_DEV_AUTH !== 'true') {
    throw new HttpError(403, 'Dev sign-in is turned off on this server');
  }
  const email = String(req.body.email || '').trim();
  if (!isEmail(email)) throw new HttpError(400, 'Enter a valid email address');
  const displayName = String(req.body.display_name || '').trim().slice(0, 60) || email.split('@')[0];
  const provider = ['google', 'apple'].includes(req.body.provider) ? req.body.provider : 'dev';
  res.json(await createSession({ email, displayName, provider }));
}));

// Production Google sign-in: the app sends the ID token from google_sign_in.
authRouter.post('/google', ah(async (req, res) => {
  // Web, Android and iOS each have their own OAuth client ID: accept any of them.
  const audience = (process.env.GOOGLE_CLIENT_ID || '').split(',').map((s) => s.trim()).filter(Boolean);
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
  res.json(await createSession({ email: payload.email, displayName: payload.name || payload.email, provider: 'google' }));
}));

// Production Apple sign-in: the app sends the identity token from sign_in_with_apple.
authRouter.post('/apple', ah(async (req, res) => {
  const audience = process.env.APPLE_CLIENT_ID;
  if (!audience) throw new HttpError(501, 'Apple sign-in is not configured on this server');
  const { createRemoteJWKSet, jwtVerify } = await import('jose');
  const jwks = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));
  let payload;
  try {
    ({ payload } = await jwtVerify(String(req.body.identity_token || ''), jwks, {
      issuer: 'https://appleid.apple.com',
      audience,
    }));
  } catch {
    throw new HttpError(401, 'Apple sign-in token is invalid or expired');
  }
  if (!payload.email) throw new HttpError(401, 'Apple did not share an email for this account');
  // Apple only sends the user's name on the very first sign-in, so the app forwards it.
  const displayName = String(req.body.display_name || '').trim() || String(payload.email).split('@')[0];
  res.json(await createSession({ email: String(payload.email), displayName, provider: 'apple' }));
}));

const requireAuth = ah(async (req, _res, next) => {
  const header = req.get('authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) throw new HttpError(401, 'Sign in required');
  const { rows: [user] } = await pool.query(
    `SELECT u.id, u.email, u.display_name
     FROM sessions s JOIN users u ON u.id = s.user_id
     WHERE s.token = $1 AND s.expires_at > now()`,
    [token],
  );
  if (!user) throw new HttpError(401, 'Your session has expired — sign in again');
  req.user = user;
  next();
});

module.exports = { authRouter, requireAuth };
