import { openDB, type DBSchema, type IDBPDatabase } from 'idb';
import { folderToApi, itemToApi, type Folder, type Item, type Member } from './models';

/**
 * The browser's copy of your data: the source of truth, online or not.
 *
 * Every edit writes the record and (when signed in) an outbox op in ONE transaction.
 * The outbox keeps at most one op per record holding its latest full state, so ten
 * offline edits become one push. `dirty` marks records with unpushed edits; pulls
 * never overwrite those. Same design as the phone app's SQLite database.
 */

type Stored<T> = T & { dirty: 0 | 1 };

export interface OutboxOp {
  seq?: number;
  opId: string;
  entity: 'folder' | 'item';
  entityId: string;
  payload: Record<string, unknown>;
}

interface Schema extends DBSchema {
  folders: { key: string; value: Stored<Folder> };
  items: { key: string; value: Stored<Item>; indexes: { byFolder: string } };
  members: { key: [string, string]; value: Member };
  outbox: { key: number; value: OutboxOp; indexes: { byEntity: [string, string] } };
}

type DB = IDBPDatabase<Schema>;

export class LocalDb {
  private constructor(private readonly db: DB) {}

  static async open(name = 'shareby'): Promise<LocalDb> {
    const db = await openDB<Schema>(name, 1, {
      upgrade(db) {
        db.createObjectStore('folders', { keyPath: 'id' });
        const items = db.createObjectStore('items', { keyPath: 'id' });
        items.createIndex('byFolder', 'folderId');
        db.createObjectStore('members', { keyPath: ['folderId', 'userId'] });
        const outbox = db.createObjectStore('outbox', { keyPath: 'seq', autoIncrement: true });
        outbox.createIndex('byEntity', ['entity', 'entityId']);
      },
    });
    return new LocalDb(db);
  }

  // ---------------------------------------------------------------- reads

  async folders(): Promise<Folder[]> {
    const all = await this.db.getAll('folders');
    return all.filter((f) => !f.deleted).map(strip).sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  }

  async items(): Promise<Item[]> {
    const all = await this.db.getAll('items');
    return all.filter((i) => !i.deleted).map(strip).sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }

  async folderById(id: string): Promise<Folder | undefined> {
    const f = await this.db.get('folders', id);
    return f ? strip(f) : undefined;
  }

  async members(): Promise<Member[]> {
    return (await this.db.getAll('members')).sort((a, b) => a.displayName.localeCompare(b.displayName));
  }

  async isEmpty(): Promise<boolean> {
    return (await this.db.count('folders')) === 0;
  }

  // --------------------------------------------------------------- writes

  /** Pass `opId` (only when signed in) to queue the change for sync. */
  async saveFolder(f: Folder, opId?: string): Promise<void> {
    const tx = this.db.transaction(['folders', 'outbox'], 'readwrite');
    await tx.objectStore('folders').put({ ...f, dirty: opId ? 1 : 0 });
    if (opId) await enqueue(tx.objectStore('outbox'), { opId, entity: 'folder', entityId: f.id, payload: folderToApi(f) });
    await tx.done;
  }

  async saveItem(i: Item, opId?: string): Promise<void> {
    const tx = this.db.transaction(['items', 'outbox'], 'readwrite');
    await tx.objectStore('items').put({ ...i, dirty: opId ? 1 : 0 });
    if (opId) await enqueue(tx.objectStore('outbox'), { opId, entity: 'item', entityId: i.id, payload: itemToApi(i) });
    await tx.done;
  }

  /** Device-local counter for the auto-confirm rule; never synced. */
  async setViewCount(itemId: string, viewCount: number): Promise<void> {
    const tx = this.db.transaction('items', 'readwrite');
    const row = await tx.store.get(itemId);
    if (row) await tx.store.put({ ...row, viewCount });
    await tx.done;
  }

  // --------------------------------------------------------------- outbox

  /** Folders first, so a new folder exists on the server before items that use it. */
  async pendingOps(limit = 50): Promise<OutboxOp[]> {
    const all = await this.db.getAll('outbox'); // ordered by seq
    const rank = (o: OutboxOp) => (o.entity === 'folder' ? 0 : 1);
    return all.sort((a, b) => rank(a) - rank(b) || (a.seq ?? 0) - (b.seq ?? 0)).slice(0, limit);
  }

  async pendingCount(): Promise<number> {
    return this.db.count('outbox');
  }

  /** Drops pushed ops and clears `dirty`, unless the record was edited again mid-push. */
  async completeOps(ops: OutboxOp[]): Promise<void> {
    if (!ops.length) return;
    const tx = this.db.transaction(['outbox', 'folders', 'items'], 'readwrite');
    const outbox = tx.objectStore('outbox');
    for (const op of ops) {
      if (op.seq !== undefined) await outbox.delete(op.seq);
    }
    for (const op of ops) {
      if ((await outbox.index('byEntity').count([op.entity, op.entityId])) > 0) continue;
      if (op.entity === 'folder') {
        const store = tx.objectStore('folders');
        const row = await store.get(op.entityId);
        if (row?.dirty) await store.put({ ...row, dirty: 0 });
      } else {
        const store = tx.objectStore('items');
        const row = await store.get(op.entityId);
        if (row?.dirty) await store.put({ ...row, dirty: 0 });
      }
    }
    await tx.done;
  }

  // ------------------------------------------------------- server changes

  async applyServerChanges(changes: {
    folders: Folder[];
    items: Item[];
    members: Member[];
    accessibleFolderIds: Set<string>;
  }): Promise<void> {
    const tx = this.db.transaction(['folders', 'items', 'members'], 'readwrite');
    const folders = tx.objectStore('folders');
    const items = tx.objectStore('items');
    const members = tx.objectStore('members');

    for (const f of changes.folders) {
      const local = await folders.get(f.id);
      if (local?.dirty) continue; // our unpushed edit wins; it syncs next
      await folders.put({ ...f, dirty: 0 });
    }
    for (const i of changes.items) {
      const local = await items.get(i.id);
      if (local?.dirty) continue;
      await items.put({ ...i, viewCount: local?.viewCount ?? 0, dirty: 0 });
    }

    // Boards we were removed from (or that were deleted) disappear from this browser.
    for (const f of await folders.getAll()) {
      if (f.isShared && !f.dirty && !changes.accessibleFolderIds.has(f.id)) {
        for (const key of await items.index('byFolder').getAllKeys(f.id)) await items.delete(key);
        await folders.delete(f.id);
      }
    }

    await members.clear();
    for (const m of changes.members) await members.put(m);
    await tx.done;
  }

  /** Signing out: shared boards leave this browser; personal saves stay (offline-first). */
  async resetForSignOut(): Promise<void> {
    const tx = this.db.transaction(['folders', 'items', 'members', 'outbox'], 'readwrite');
    const folders = tx.objectStore('folders');
    const items = tx.objectStore('items');
    for (const f of await folders.getAll()) {
      if (f.isShared) {
        for (const key of await items.index('byFolder').getAllKeys(f.id)) await items.delete(key);
        await folders.delete(f.id);
      } else if (f.dirty) {
        await folders.put({ ...f, dirty: 0 });
      }
    }
    for (const i of await items.getAll()) {
      if (i.dirty) await items.put({ ...i, dirty: 0 });
    }
    await tx.objectStore('members').clear();
    await tx.objectStore('outbox').clear();
    await tx.done;
  }
}

function strip<T extends { dirty: 0 | 1 }>(row: T): Omit<T, 'dirty'> {
  const { dirty: _dirty, ...rest } = row;
  return rest;
}

async function enqueue(
  outbox: { index(name: 'byEntity'): { getAllKeys(q: [string, string]): Promise<number[]> }; delete(k: number): Promise<void>; add(v: OutboxOp): Promise<number> },
  op: OutboxOp,
): Promise<void> {
  for (const key of await outbox.index('byEntity').getAllKeys([op.entity, op.entityId])) await outbox.delete(key);
  await outbox.add(op);
}
