'use strict';

/**
 * Daily housekeeping that keeps the database small on the Supabase free tier:
 *   * deleted links and folders ("tombstones") are kept TOMBSTONE_DAYS so every device
 *     learns about the delete, then removed for good;
 *   * invitations nobody accepted within INVITE_DAYS expire.
 * It also touches the database once a day, which keeps a free project from being paused for
 * inactivity while nobody is using the app.
 */
const tombstoneDays = () => Math.max(7, Number(process.env.TOMBSTONE_DAYS || 60));
const inviteDays = () => Math.max(1, Number(process.env.INVITE_DAYS || 60));

async function runMaintenance(pool) {
  const t = tombstoneDays();
  const items = await pool.query(
    `DELETE FROM items WHERE deleted_at IS NOT NULL AND deleted_at < now() - make_interval(days => $1)`, [t]);
  // Anything still inside a folder being purged goes with it (e.g. friends' pins on a deleted
  // board); otherwise the foreign key would quietly turn them into loose links.
  await pool.query(
    `DELETE FROM items WHERE folder_id IN (
       SELECT id FROM folders WHERE deleted_at IS NOT NULL AND deleted_at < now() - make_interval(days => $1))`, [t]);
  const folders = await pool.query(
    `DELETE FROM folders WHERE deleted_at IS NOT NULL AND deleted_at < now() - make_interval(days => $1)`, [t]);
  const invites = await pool.query(
    `DELETE FROM invitations WHERE created_at < now() - make_interval(days => $1)`, [inviteDays()]);
  return { items: items.rowCount, folders: folders.rowCount, invitations: invites.rowCount };
}

function scheduleMaintenance(pool, everyMs = 24 * 3600_000) {
  const run = () => runMaintenance(pool)
    .then((r) => console.log(`Maintenance: purged ${r.items} links, ${r.folders} folders, ${r.invitations} invitations`))
    .catch((err) => console.error('Maintenance failed:', err.message));
  setTimeout(run, 60_000).unref();       // shortly after start
  setInterval(run, everyMs).unref();
}

module.exports = { runMaintenance, scheduleMaintenance, tombstoneDays };
