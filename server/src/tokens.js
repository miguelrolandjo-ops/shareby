'use strict';
const crypto = require('crypto');

/**
 * Signed, stateless session tokens (HMAC-SHA256), so there is no sessions table to store,
 * grow and query on every request. Format: v1.<payload>.<signature>, both base64url.
 */
const SESSION_DAYS = 30;

let warned = false;
function secret() {
  const s = process.env.SESSION_SECRET;
  if (s && s.length >= 32) return s;
  if (process.env.NODE_ENV === 'production' && process.env.ALLOW_DEV_AUTH !== 'true') {
    throw new Error('SESSION_SECRET must be set (32+ characters) in production');
  }
  if (!warned) {
    console.warn('SESSION_SECRET is not set: using a random one, so sign-ins end when the server restarts.');
    warned = true;
  }
  process.env.SESSION_SECRET = crypto.randomBytes(32).toString('hex');
  return process.env.SESSION_SECRET;
}

const sign = (data) => crypto.createHmac('sha256', secret()).update(data).digest('base64url');

function issueToken(user, days = SESSION_DAYS) {
  const exp = Math.floor(Date.now() / 1000) + days * 86400;
  const payload = Buffer.from(JSON.stringify({ sub: user.id, email: user.email, exp })).toString('base64url');
  const body = `v1.${payload}`;
  return { token: `${body}.${sign(body)}`, expiresAt: new Date(exp * 1000) };
}

/** Returns { id, email } or null when the token is malformed, forged or expired. */
function verifyToken(token) {
  if (typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 3 || parts[0] !== 'v1') return null;
  const expected = Buffer.from(sign(`${parts[0]}.${parts[1]}`));
  const given = Buffer.from(parts[2]);
  if (expected.length !== given.length || !crypto.timingSafeEqual(expected, given)) return null;
  try {
    const p = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    if (typeof p.sub !== 'string' || typeof p.exp !== 'number' || p.exp * 1000 < Date.now()) return null;
    return { id: p.sub, email: p.email };
  } catch {
    return null;
  }
}

module.exports = { issueToken, verifyToken, SESSION_DAYS, secret };
