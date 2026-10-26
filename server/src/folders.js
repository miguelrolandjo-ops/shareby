'use strict';
const express = require('express');
const { pool } = require('./db');
const { ah, HttpError, isUuid, isEmail } = require('./util');

const foldersRouter = express.Router();

/**
 * Invite someone to a shared board.
 * - If they already have an account they become a member right away ("added").
 * - Otherwise the invite waits and is accepted automatically on their first sign-in ("pending").
 */
foldersRouter.post('/:id/invites', ah(async (req, res) => {
  const folderId = req.params.id;
  if (!isUuid(folderId)) throw new HttpError(400, 'Board id must be a UUID');
  const email = String(req.body.email || '').trim().toLowerCase();
  if (!isEmail(email)) throw new HttpError(400, 'Enter a valid email address');
  const role = req.body.role === 'viewer' ? 'viewer' : 'editor';

  const { rows: [folder] } = await pool.query(
    'SELECT owner_id, is_shared FROM folders WHERE id = $1 AND deleted_at IS NULL', [folderId]);
  if (!folder) throw new HttpError(404, 'Board not found — it may not have synced yet');
  if (folder.owner_id !== req.user.id) throw new HttpError(403, 'Only the board owner can invite people');
  if (!folder.is_shared) throw new HttpError(400, 'Personal folders stay private. Create a shared board to invite friends.');
  if (email === req.user.email) throw new HttpError(400, 'You already own this board');

  const { rows: [invitee] } = await pool.query(
    'SELECT id, display_name FROM users WHERE email = $1', [email]);

  if (invitee) {
    await pool.query(
      `INSERT INTO folder_members (folder_id, user_id, role) VALUES ($1, $2, $3)
       ON CONFLICT (folder_id, user_id) DO UPDATE SET role = EXCLUDED.role
       WHERE folder_members.role <> 'owner'`,
      [folderId, invitee.id, role]);
    return res.json({ status: 'added', display_name: invitee.display_name });
  }

  await pool.query(
    `INSERT INTO invitations (folder_id, email, role) VALUES ($1, $2, $3)
     ON CONFLICT (folder_id, email) DO UPDATE SET role = EXCLUDED.role, created_at = now()`,
    [folderId, email, role]);
  res.json({ status: 'pending' });
}));

/** Leave a board (members) or remove someone (owner). */
foldersRouter.delete('/:id/members/:userId', ah(async (req, res) => {
  const { id: folderId, userId } = req.params;
  if (!isUuid(folderId) || !isUuid(userId)) throw new HttpError(400, 'Ids must be UUIDs');
  const { rows: [folder] } = await pool.query('SELECT owner_id FROM folders WHERE id = $1', [folderId]);
  if (!folder) throw new HttpError(404, 'Board not found');
  const isSelf = userId === req.user.id;
  if (!isSelf && folder.owner_id !== req.user.id) throw new HttpError(403, 'Only the owner can remove people');
  if (userId === folder.owner_id) throw new HttpError(400, 'The owner cannot leave — delete the board instead');
  await pool.query('DELETE FROM folder_members WHERE folder_id = $1 AND user_id = $2', [folderId, userId]);
  res.json({ status: 'removed' });
}));

module.exports = { foldersRouter };
