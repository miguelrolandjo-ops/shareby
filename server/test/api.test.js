'use strict';
// End-to-end API test against a real PostgreSQL.
// Needs DATABASE_URL and ALLOW_DEV_AUTH=true (the app is started in-process on a random port).
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { app } = require('../src/index');
const { pool } = require('../src/db');

let server;
let base;
const run = crypto.randomBytes(3).toString('hex');
const now = () => new Date().toISOString();
const uuid = () => crypto.randomUUID();

async function call(method, route, { token, body } = {}) {
  const res = await fetch(base + route, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
}
const login = async (name) => (await call('POST', '/auth/dev', {
  body: { email: `${name}.${run}@example.com`, display_name: name, provider: 'google' },
})).body;
const push = (token, ops) => call('POST', '/sync/push', { token, body: { ops } });
const pull = (token, since) => call('GET', `/sync/pull${since ? `?since=${encodeURIComponent(since)}` : ''}`, { token });

const folder = (overrides = {}) => ({
  id: uuid(), name: 'Folder', color: 0xFFE8A23D, emoji: '🍳', is_shared: false,
  created_at: now(), updated_at: now(), deleted_at: null, ...overrides,
});
const item = (overrides = {}) => ({
  id: uuid(), folder_id: null, url: 'https://www.instagram.com/reel/abc', title: 'Ayam geprek',
  source: 'instagram', thumbnail_url: null, tag: null, status: 'confirmed', suggested_folder_id: null,
  confidence: 0, created_at: now(), updated_at: now(), deleted_at: null, ...overrides,
});
const op = (entity, data) => ({ op_id: uuid(), entity, data });

let alice; let bob;
const personal = folder({ name: 'Cooking' });
const board = folder({ name: 'Weekend Inspo', is_shared: true, color: 0xFF9A7FD1, emoji: '✨' });

before(async () => {
  await pool.query(fs.readFileSync(path.join(__dirname, '..', 'schema.sql'), 'utf8'));
  server = app.listen(0);
  base = `http://127.0.0.1:${server.address().port}`;
  alice = await login('Alice');
  bob = await login('Bob');
});

after(async () => {
  server.close();
  await pool.end();
});

test('requests without a session are refused', async () => {
  const res = await call('GET', '/sync/pull');
  assert.equal(res.status, 401);
});

test('push creates folders and items, and replays are idempotent', async () => {
  const cookingItem = item({ folder_id: personal.id, tag: 'Jumat gas', status: 'new', confidence: 0.7 });
  const ops = [op('folder', personal), op('folder', board), op('item', cookingItem)];
  const first = await push(alice.token, ops);
  assert.equal(first.status, 200);
  assert.equal(first.body.applied.length, 3);
  const replay = await push(alice.token, ops);
  assert.equal(replay.body.applied.length, 3, 'replaying the same ops is safe');
  const { rows } = await pool.query('SELECT tag, status FROM items WHERE id = $1', [cookingItem.id]);
  assert.deepEqual(rows[0], { tag: 'Jumat gas', status: 'new' }, 'personal folders keep tags');
});

test('tags and auto-categorization are stripped on shared boards (DB trigger)', async () => {
  const pin = item({ folder_id: board.id, tag: 'should vanish', status: 'new', confidence: 0.9, title: 'Moodboard pastel' });
  const res = await push(alice.token, [op('item', pin)]);
  assert.equal(res.body.applied.length, 1);
  const { rows } = await pool.query('SELECT tag, status, confidence FROM items WHERE id = $1', [pin.id]);
  assert.deepEqual(rows[0], { tag: null, status: 'confirmed', confidence: 0 });
});

test('invited friend sees the shared board but never the personal folder', async () => {
  const invite = await call('POST', `/folders/${board.id}/invites`, {
    token: alice.token, body: { email: bob.user.email, role: 'editor' } });
  assert.equal(invite.body.status, 'added');

  const res = await pull(bob.token);
  const ids = res.body.folders.map((f) => f.id);
  assert.ok(ids.includes(board.id));
  assert.ok(!ids.includes(personal.id));
  assert.equal(res.body.folders.find((f) => f.id === board.id).my_role, 'editor');
  assert.equal(typeof res.body.folders[0].color, 'number', 'bigint colors come back as numbers');
  assert.ok(res.body.items.every((i) => i.folder_id === board.id));
  const names = res.body.members.filter((m) => m.folder_id === board.id).map((m) => m.display_name);
  assert.deepEqual(names.sort(), ['Alice', 'Bob']);
});

test('personal folders cannot be shared', async () => {
  const res = await call('POST', `/folders/${personal.id}/invites`, {
    token: alice.token, body: { email: bob.user.email } });
  assert.equal(res.status, 400);
});

test('editors can pin; the owner sees who added it', async () => {
  const bobPin = item({ folder_id: board.id, title: 'DIY dekorasi', url: 'https://www.tiktok.com/@x/video/1', source: 'tiktok' });
  const res = await push(bob.token, [op('item', bobPin)]);
  assert.equal(res.body.applied.length, 1);
  const seen = (await pull(alice.token)).body.items.find((i) => i.id === bobPin.id);
  assert.equal(seen.added_by_name, 'Bob');
});

test('editors cannot rename a board they do not own', async () => {
  const res = await push(bob.token, [op('folder', { ...board, name: 'Hijacked', updated_at: now() })]);
  assert.equal(res.body.rejected.length, 1);
});

test('done: an editor can tick a friend\'s pin, and everyone sees who did it', async () => {
  const gift = item({ folder_id: board.id, title: 'Hampers buat tamu' });
  await push(alice.token, [op('item', gift)]);
  const doneAt = now();
  const res = await push(bob.token, [op('item', { ...gift, completed_at: doneAt, completion_updated_at: doneAt })]);
  assert.equal(res.body.applied.length, 1);
  const seen = (await pull(alice.token)).body.items.find((i) => i.id === gift.id);
  assert.ok(seen.completed_at);
  assert.equal(seen.completed_by_name, 'Bob');
});

test('done: a later content edit carrying a stale done state does not undo the tick', async () => {
  const pin = item({ folder_id: board.id, title: 'Rak minimalis' });
  await push(alice.token, [op('item', pin)]);
  const tick = new Date(Date.now() + 1000).toISOString();
  await push(bob.token, [op('item', { ...pin, completed_at: tick, completion_updated_at: tick })]);
  // Alice's phone was offline: it retitles the pin, still believing it isn't done.
  await push(alice.token, [op('item', { ...pin, title: 'Rak minimalis IKEA', updated_at: new Date(Date.now() + 2000).toISOString() })]);
  const { rows: [row] } = await pool.query('SELECT title, completed_at FROM items WHERE id = $1', [pin.id]);
  assert.equal(row.title, 'Rak minimalis IKEA', 'content edit applied');
  assert.ok(row.completed_at, 'tick kept');
});

test('done: editors cannot edit or delete a friend\'s pin, only tick it', async () => {
  const pin = item({ folder_id: board.id, title: 'Original' });
  await push(alice.token, [op('item', pin)]);
  const later = new Date(Date.now() + 1000).toISOString();
  await push(bob.token, [op('item', { ...pin, title: 'Renamed by Bob', updated_at: later })]);
  const del = await push(bob.token, [op('item', { ...pin, deleted_at: later, updated_at: later })]);
  assert.equal(del.body.rejected.length, 1);
  const { rows: [row] } = await pool.query('SELECT title, deleted_at FROM items WHERE id = $1', [pin.id]);
  assert.deepEqual(row, { title: 'Original', deleted_at: null });
});

test('viewers cannot add pins', async () => {
  const carol = await login('Carol');
  await call('POST', `/folders/${board.id}/invites`, { token: alice.token, body: { email: carol.user.email, role: 'viewer' } });
  const res = await push(carol.token, [op('item', item({ folder_id: board.id }))]);
  assert.equal(res.body.rejected.length, 1);
  assert.match(res.body.rejected[0].reason, /Viewers/);

  const pin = item({ folder_id: board.id, title: 'Viewer target' });
  await push(alice.token, [op('item', pin)]);
  const t = now();
  const tick = await push(carol.token, [op('item', { ...pin, completed_at: t, completion_updated_at: t })]);
  assert.equal(tick.body.rejected.length, 1, 'viewers cannot tick pins done');
});

test('invites for people without an account are accepted on first sign-in', async () => {
  const email = `dana.${run}@example.com`;
  const invite = await call('POST', `/folders/${board.id}/invites`, { token: alice.token, body: { email } });
  assert.equal(invite.body.status, 'pending');
  const dana = (await call('POST', '/auth/dev', { body: { email, display_name: 'Dana' } })).body;
  const res = await pull(dana.token);
  assert.ok(res.body.accessible_folder_ids.includes(board.id));
});

test('last write wins: a stale edit does not overwrite a newer one', async () => {
  const note = item({ folder_id: personal.id, title: 'v1' });
  await push(alice.token, [op('item', note)]);
  await push(alice.token, [op('item', { ...note, title: 'v2 newer', updated_at: new Date(Date.now() + 1000).toISOString() })]);
  await push(alice.token, [op('item', { ...note, title: 'v0 stale', updated_at: new Date(Date.now() - 60000).toISOString() })]);
  const { rows } = await pool.query('SELECT title FROM items WHERE id = $1', [note.id]);
  assert.equal(rows[0].title, 'v2 newer');
});

test('pull with a cursor only returns newer changes', async () => {
  // The cursor deliberately overlaps the last 5s (re-sent rows are harmless upserts),
  // so let earlier tests' writes age out of that window before taking the cursor.
  await new Promise((r) => setTimeout(r, 6000));
  const first = await pull(alice.token);
  const later = item({ folder_id: personal.id, title: 'after cursor' });
  await push(alice.token, [op('item', later)]);
  const second = await pull(alice.token, first.body.cursor);
  assert.deepEqual(second.body.items.map((i) => i.id), [later.id]);
});

test('removed members lose access to the board', async () => {
  await call('DELETE', `/folders/${board.id}/members/${bob.user.id}`, { token: alice.token });
  const res = await pull(bob.token);
  assert.ok(!res.body.accessible_folder_ids.includes(board.id));
});

test('bad data is rejected per-op without failing the batch', async () => {
  const good = item({ folder_id: personal.id, title: 'fine' });
  const res = await push(alice.token, [op('item', { ...item(), url: 'ftp://nope' }), op('item', good)]);
  assert.equal(res.body.rejected.length, 1);
  assert.deepEqual(res.body.applied.length, 1);
});
