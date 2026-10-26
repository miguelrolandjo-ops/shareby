'use strict';
// Online-mode additions: sign-in config, signed tokens, account deletion, full resync,
// housekeeping and the Supabase lockdown. Needs DATABASE_URL and ALLOW_DEV_AUTH=true.
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { app } = require('../src/index');
const { pool, poolConfig } = require('../src/db');
const { runMaintenance } = require('../src/maintenance');
const { issueToken } = require('../src/tokens');

let server;
let base;
const run = crypto.randomBytes(3).toString('hex');
const uuid = () => crypto.randomUUID();
const iso = (msAgo = 0) => new Date(Date.now() - msAgo).toISOString();
const DAY = 86400_000;

async function call(method, route, { token, body } = {}) {
  const res = await fetch(base + route, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
}
const login = async (name) => (await call('POST', '/auth/dev', {
  body: { email: `${name}.${run}@example.com`, display_name: name },
})).body;
const op = (entity, data) => ({ op_id: uuid(), entity, data });
const item = (o = {}) => ({
  id: uuid(), folder_id: null, url: 'https://youtu.be/abc', title: 'Best ramen in Tokyo', source: 'youtube',
  status: 'confirmed', confidence: 0, created_at: iso(), updated_at: iso(), deleted_at: null, ...o,
});

before(async () => {
  await pool.query(fs.readFileSync(path.join(__dirname, '..', 'schema.sql'), 'utf8'));
  server = app.listen(0);
  base = `http://127.0.0.1:${server.address().port}`;
});
after(async () => {
  server.close();
  await pool.end();
});

test('sign-in config is public and names the available methods', async () => {
  const res = await call('GET', '/auth/config');
  assert.equal(res.status, 200);
  assert.equal(res.body.dev, true);
  assert.ok('google_client_id' in res.body);
});

test('google sign-in refuses a fake token when configured', async () => {
  process.env.GOOGLE_CLIENT_ID = 'web-id.apps.googleusercontent.com';
  const res = await call('POST', '/auth/google', { body: { id_token: 'not-a-token' } });
  assert.equal(res.status, 401);
  delete process.env.GOOGLE_CLIENT_ID;
});

test('tokens are signed: tampered, forged or expired tokens are refused', async () => {
  const a = await login('Tess');
  assert.equal((await call('GET', '/sync/pull', { token: a.token })).status, 200);
  const [v, payload, sig] = a.token.split('.');
  const evil = Buffer.from(JSON.stringify({ sub: uuid(), email: 'x@y.z', exp: 9e9 })).toString('base64url');
  assert.equal((await call('GET', '/sync/pull', { token: `${v}.${evil}.${sig}` })).status, 401);
  assert.equal((await call('GET', '/sync/pull', { token: `${v}.${payload}.AAAA` })).status, 401);
  const expired = issueToken(a.user, -1).token;
  assert.equal((await call('GET', '/sync/pull', { token: expired })).status, 401);
});

test('a device away longer than the tombstone horizon gets a full resync', async () => {
  const a = await login('Rhea');
  const keep = item();
  await call('POST', '/sync/push', { token: a.token, body: { ops: [op('item', keep)] } });
  const recent = await call('GET', `/sync/pull?since=${encodeURIComponent(iso(DAY))}`, { token: a.token });
  assert.equal(recent.body.full, false);
  const stale = await call('GET', `/sync/pull?since=${encodeURIComponent(iso(400 * DAY))}`, { token: a.token });
  assert.equal(stale.body.full, true);
  assert.ok(stale.body.items.some((i) => i.id === keep.id));
});

test('housekeeping purges old tombstones and expired invitations only', async () => {
  const a = await login('Mona');
  const old = item({ deleted_at: iso(90 * DAY), updated_at: iso(90 * DAY) });
  const fresh = item({ deleted_at: iso(DAY), updated_at: iso(DAY) });
  const live = item();
  await call('POST', '/sync/push', { token: a.token, body: { ops: [op('item', old), op('item', fresh), op('item', live)] } });
  await runMaintenance(pool);
  const { rows } = await pool.query('SELECT id FROM items WHERE id = ANY($1)', [[old.id, fresh.id, live.id]]);
  const ids = rows.map((r) => r.id);
  assert.ok(!ids.includes(old.id), 'old tombstone purged');
  assert.ok(ids.includes(fresh.id), 'recent tombstone kept so other devices learn of the delete');
  assert.ok(ids.includes(live.id));
});

test('accepted invitations are deleted, not kept as history', async () => {
  const owner = await login('Owen');
  const board = { id: uuid(), name: 'Trip', color: 1, emoji: '✈️', is_shared: true, created_at: iso(), updated_at: iso() };
  await call('POST', '/sync/push', { token: owner.token, body: { ops: [op('folder', board)] } });
  const email = `newbie.${run}@example.com`;
  assert.equal((await call('POST', `/folders/${board.id}/invites`, { token: owner.token, body: { email } })).body.status, 'pending');
  const newbie = await call('POST', '/auth/dev', { body: { email } });
  const { rows } = await pool.query('SELECT 1 FROM invitations WHERE email = $1', [email]);
  assert.equal(rows.length, 0);
  const pulled = await call('GET', '/sync/pull', { token: newbie.body.token });
  assert.ok(pulled.body.accessible_folder_ids.includes(board.id));
});

test('deleting an account removes its data and its token stops working', async () => {
  const a = await login('Dora');
  const b = await login('Finn');
  const board = { id: uuid(), name: 'Gifts', color: 1, emoji: '🎁', is_shared: true, created_at: iso(), updated_at: iso() };
  await call('POST', '/sync/push', { token: a.token, body: { ops: [op('folder', board), op('item', item())] } });
  await call('POST', `/folders/${board.id}/invites`, { token: a.token, body: { email: b.user.email } });
  await call('POST', '/sync/push', { token: b.token, body: { ops: [op('item', item({ folder_id: board.id }))] } });

  assert.equal((await call('DELETE', '/account', { token: a.token })).status, 200);
  assert.equal((await call('GET', '/sync/pull', { token: a.token })).status, 401);
  const { rows } = await pool.query('SELECT count(*)::int AS n FROM items WHERE owner_id = $1 OR folder_id = $2', [a.user.id, board.id]);
  assert.equal(rows[0].n, 0);
  const friend = await call('GET', '/sync/pull', { token: b.token });
  assert.ok(!friend.body.accessible_folder_ids.includes(board.id), 'friends lose the deleted owner\'s board');
});

test('tables live outside Supabase\'s public API schema and API roles get nothing', async () => {
  const { rows } = await pool.query(
    `SELECT table_schema FROM information_schema.tables WHERE table_name = 'items' AND table_schema <> 'information_schema'`);
  assert.deepEqual(rows.map((r) => r.table_schema), ['shareby']);
  const { rows: [perm] } = await pool.query(
    `SELECT has_table_privilege('anon', 'shareby.items', 'SELECT') AS anon_read,
            (SELECT relrowsecurity FROM pg_class WHERE oid = 'shareby.items'::regclass) AS rls`);
  assert.deepEqual(perm, { anon_read: false, rls: true });
});

test('hosted databases get SSL; sslmode in the URL cannot override it', () => {
  const cfg = poolConfig({ DATABASE_URL: 'postgresql://u:p@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres?sslmode=require' });
  assert.deepEqual(cfg.ssl, { rejectUnauthorized: false });
  assert.ok(!cfg.connectionString.includes('sslmode'));
  assert.equal(poolConfig({ DATABASE_URL: 'postgres://u:p@localhost/db' }).ssl, false);
});
