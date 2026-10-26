'use strict';
const express = require('express');
const { pool } = require('./db');
const { ah, HttpError, isUuid } = require('./util');
const { tombstoneDays } = require('./maintenance');

/** A permanent problem with one op (bad data, no permission). The client drops it. */
class Rejection extends Error {}

// Platform keys come from rules.json and grow over time, so any well-formed key is accepted.
const SOURCE_KEY = /^[a-z0-9_-]{1,32}$/;
const STATUSES = new Set(['new', 'confirmed']);

function timestamp(value, field, { required = false } = {}) {
  if (value === null || value === undefined || value === '') {
    if (required) throw new Rejection(`${field} is required`);
    return null;
  }
  if (typeof value !== 'string' || Number.isNaN(new Date(value).getTime())) {
    throw new Rejection(`${field} must be an ISO-8601 timestamp`);
  }
  return value; // hand the original string to Postgres so microseconds survive
}

async function applyFolder(client, user, d) {
  if (!isUuid(d.id)) throw new Rejection('folder.id must be a UUID');
  const name = typeof d.name === 'string' ? d.name.trim() : '';
  if (!name || name.length > 80) throw new Rejection('folder.name is required (80 characters max)');
  if (!Number.isSafeInteger(d.color)) throw new Rejection('folder.color must be an integer');
  const emoji = typeof d.emoji === 'string' && d.emoji.length > 0 && d.emoji.length <= 16 ? d.emoji : '📁';
  const createdAt = timestamp(d.created_at, 'created_at', { required: true });
  const updatedAt = timestamp(d.updated_at, 'updated_at', { required: true });
  const deletedAt = timestamp(d.deleted_at, 'deleted_at');

  const { rows: [existing] } = await client.query(
    'SELECT owner_id FROM folders WHERE id = $1 FOR UPDATE', [d.id]);

  if (!existing) {
    await client.query(
      `INSERT INTO folders (id, owner_id, name, color, emoji, is_shared, created_at, updated_at, deleted_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [d.id, user.id, name, d.color, emoji, d.is_shared === true, createdAt, updatedAt, deletedAt]);
    await client.query(
      `INSERT INTO folder_members (folder_id, user_id, role) VALUES ($1, $2, 'owner')
       ON CONFLICT DO NOTHING`, [d.id, user.id]);
    return;
  }
  if (existing.owner_id !== user.id) throw new Rejection('Only the owner can change this folder');

  // Last write wins: an older edit arriving late is ignored (and still counts as applied).
  await client.query(
    `UPDATE folders
     SET name = $2, color = $3, emoji = $4, updated_at = $5, deleted_at = $6, server_updated_at = now()
     WHERE id = $1 AND updated_at < $5`,
    [d.id, name, d.color, emoji, updatedAt, deletedAt]);
}

async function applyItem(client, user, d) {
  if (!isUuid(d.id)) throw new Rejection('item.id must be a UUID');
  const folderId = d.folder_id ?? null;
  if (folderId !== null && !isUuid(folderId)) throw new Rejection('item.folder_id must be a UUID or null');
  const url = typeof d.url === 'string' ? d.url.trim() : '';
  if (!/^https?:\/\//i.test(url) || url.length > 2048) throw new Rejection('item.url must be an http(s) link');
  const title = typeof d.title === 'string' ? d.title.trim().slice(0, 300) : '';
  if (!title) throw new Rejection('item.title is required');
  const source = typeof d.source === 'string' && SOURCE_KEY.test(d.source) ? d.source : 'web';
  const author = typeof d.author === 'string' && d.author.trim() ? d.author.trim().slice(0, 120) : null;
  const status = STATUSES.has(d.status) ? d.status : 'confirmed';
  const tag = typeof d.tag === 'string' && d.tag.trim() ? d.tag.trim().slice(0, 40) : null;
  const thumbnail = typeof d.thumbnail_url === 'string' ? d.thumbnail_url.slice(0, 2048) : null;
  const suggested = isUuid(d.suggested_folder_id) ? d.suggested_folder_id : null;
  const confidence = typeof d.confidence === 'number' && Number.isFinite(d.confidence)
    ? Math.min(1, Math.max(0, d.confidence)) : 0;
  const createdAt = timestamp(d.created_at, 'created_at', { required: true });
  const updatedAt = timestamp(d.updated_at, 'updated_at', { required: true });
  const deletedAt = timestamp(d.deleted_at, 'deleted_at');
  const completedAt = timestamp(d.completed_at, 'completed_at');
  const completionAt = timestamp(d.completion_updated_at, 'completion_updated_at');

  const roleIn = async (fid) => {
    const { rows: [m] } = await client.query(
      'SELECT role FROM folder_members WHERE folder_id = $1 AND user_id = $2', [fid, user.id]);
    return m ? m.role : null;
  };
  const requireWriter = async (fid) => {
    const role = await roleIn(fid);
    if (!role) throw new Rejection('You are not a member of that folder');
    if (role === 'viewer') throw new Rejection('Viewers can look but not add or change pins');
  };

  const { rows: [existing] } = await client.query(
    `SELECT i.owner_id, i.folder_id, i.deleted_at, f.owner_id AS folder_owner
     FROM items i LEFT JOIN folders f ON f.id = i.folder_id
     WHERE i.id = $1 FOR UPDATE OF i`, [d.id]);

  const values = [d.id, folderId, url, title, source, thumbnail, tag, status, suggested, confidence, updatedAt, deletedAt, author];

  if (!existing) {
    if (folderId !== null) await requireWriter(folderId);
    await client.query(
      `INSERT INTO items (id, folder_id, url, title, source, thumbnail_url, tag, status,
                          suggested_folder_id, confidence, updated_at, deleted_at, author, owner_id, created_at,
                          completed_at, completed_by, completion_updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)`,
      [...values, user.id, createdAt, completedAt, completedAt ? user.id : null, completionAt]);
    return;
  }

  const isAuthor = existing.owner_id === user.id || existing.folder_owner === user.id;
  if (isAuthor) {
    if (folderId !== null) await requireWriter(folderId);
    // Last write wins on content.
    await client.query(
      `UPDATE items
       SET folder_id = $2, url = $3, title = $4, source = $5, thumbnail_url = $6, tag = $7, status = $8,
           suggested_folder_id = $9, confidence = $10, updated_at = $11, deleted_at = $12, author = $13,
           server_updated_at = now()
       WHERE id = $1 AND updated_at < $11`,
      values);
  } else {
    // Someone else's pin: editors on the same board may only tick it done / not done.
    if (!existing.folder_id) throw new Rejection('You can only change pins you added');
    await requireWriter(existing.folder_id);
    if (deletedAt && !existing.deleted_at) throw new Rejection('You can only remove pins you added');
    if (!completionAt) return; // nothing this user may change; ignore stale content
  }

  // Last write wins on "done", tracked separately from content.
  if (completionAt) {
    await client.query(
      `UPDATE items
       SET completed_at = $2::timestamptz,
           completed_by = CASE WHEN $2::timestamptz IS NULL THEN NULL ELSE $3::uuid END,
           completion_updated_at = $4, server_updated_at = now()
       WHERE id = $1 AND (completion_updated_at IS NULL OR completion_updated_at < $4)`,
      [d.id, completedAt, user.id, completionAt]);
  }
}

const syncRouter = express.Router();

/**
 * Body: { ops: [{ op_id, entity: 'folder' | 'item', data: {...} }] }
 * Each op runs in its own transaction. Replaying an op is harmless (upsert + LWW),
 * so the client can safely retry a whole batch after a network failure.
 */
syncRouter.post('/push', ah(async (req, res) => {
  const ops = Array.isArray(req.body.ops) ? req.body.ops.slice(0, 200) : [];
  const applied = [];
  const rejected = [];

  for (const op of ops) {
    const opId = typeof op?.op_id === 'string' ? op.op_id : null;
    if (!opId) continue;
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      if (op.entity === 'folder') await applyFolder(client, req.user, op.data || {});
      else if (op.entity === 'item') await applyItem(client, req.user, op.data || {});
      else throw new Rejection(`Unknown entity "${op.entity}"`);
      await client.query('COMMIT');
      applied.push(opId);
    } catch (err) {
      await client.query('ROLLBACK');
      if (!(err instanceof Rejection)) throw err; // transient: 500, client retries later
      rejected.push({ op_id: opId, reason: err.message });
    } finally {
      client.release();
    }
  }
  res.json({ applied, rejected });
}));

/**
 * Returns everything the caller can see that changed after `since`.
 * The cursor overlaps by a few seconds so writes committing mid-request are never skipped;
 * the client's upserts are idempotent, so duplicates are harmless.
 *
 * A device whose cursor is older than the tombstone horizon may have missed deletes that were
 * since purged, so it gets everything with `full: true`, and drops local (already synced)
 * records that are no longer in the answer.
 */
syncRouter.get('/pull', ah(async (req, res) => {
  let since = req.query.since ? new Date(String(req.query.since)) : new Date(0);
  if (Number.isNaN(since.getTime())) throw new HttpError(400, 'since must be an ISO-8601 timestamp');
  const horizon = Date.now() - tombstoneDays() * 86400_000;
  const full = Boolean(req.query.since) && since.getTime() < horizon;
  if (full) since = new Date(0);
  const me = req.user.id;

  // Independent reads run side by side: the database is a network hop away.
  const [cursorRes, folders, items, members, accessible] = await Promise.all([
    pool.query(`SELECT now() - interval '5 seconds' AS cursor`),
    pool.query(
      `SELECT f.id, f.owner_id, f.name, f.color, f.emoji, f.is_shared,
              f.created_at, f.updated_at, f.deleted_at, fm.role AS my_role
       FROM folders f
       JOIN folder_members fm ON fm.folder_id = f.id AND fm.user_id = $1
       WHERE f.server_updated_at > $2 OR fm.added_at > $2`,
      [me, since]),
    pool.query(
      `SELECT i.id, i.folder_id, i.url, i.title, i.source, i.thumbnail_url, i.tag, i.status, i.author,
              i.suggested_folder_id, i.confidence, i.created_at, i.updated_at, i.deleted_at,
              i.owner_id AS added_by, u.display_name AS added_by_name,
              i.completed_at, i.completed_by, cu.display_name AS completed_by_name, i.completion_updated_at
       FROM (
         SELECT i.* FROM items i
         JOIN folder_members fm ON fm.folder_id = i.folder_id AND fm.user_id = $1
         WHERE i.server_updated_at > $2 OR fm.added_at > $2
         UNION ALL
         SELECT i.* FROM items i
         WHERE i.folder_id IS NULL AND i.owner_id = $1 AND i.server_updated_at > $2
       ) i
       JOIN users u ON u.id = i.owner_id
       LEFT JOIN users cu ON cu.id = i.completed_by`,
      [me, since]),
    // Member lists are small, so send them in full for every shared board the caller is in.
    pool.query(
      `SELECT fm.folder_id, fm.user_id, fm.role, u.display_name
       FROM folder_members fm
       JOIN users u ON u.id = fm.user_id
       JOIN folders f ON f.id = fm.folder_id AND f.is_shared AND f.deleted_at IS NULL
       WHERE fm.folder_id IN (SELECT folder_id FROM folder_members WHERE user_id = $1)
       ORDER BY fm.added_at`,
      [me]),
    // Lets the client drop boards it was removed from.
    pool.query(
      `SELECT fm.folder_id FROM folder_members fm
       JOIN folders f ON f.id = fm.folder_id AND f.deleted_at IS NULL
       WHERE fm.user_id = $1`,
      [me]),
  ]);

  res.json({
    cursor: cursorRes.rows[0].cursor.toISOString(),
    full,
    folders: folders.rows,
    items: items.rows,
    members: members.rows,
    accessible_folder_ids: accessible.rows.map((r) => r.folder_id),
  });
}));

module.exports = { syncRouter };
