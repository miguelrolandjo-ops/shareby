import 'fake-indexeddb/auto';
import { describe, expect, it } from 'vitest';
import { LocalDb } from '../src/data/localDb';
import type { Folder, Item } from '../src/data/models';

let n = 0;
const open = () => LocalDb.open(`test-${n++}`);
const t = '2026-10-01T10:00:00.000Z';
const folder = (o: Partial<Folder> = {}): Folder => ({
  id: 'f1', name: 'Cooking', color: 1, emoji: '🍳', isShared: false, ownerId: null, myRole: 'owner',
  createdAt: t, updatedAt: t, deleted: false, ...o,
});
const item = (o: Partial<Item> = {}): Item => ({
  id: 'i1', folderId: 'f1', url: 'https://a.com', title: 'A', source: 'web', thumbnailUrl: null, tag: null,
  status: 'confirmed', suggestedFolderId: null, confidence: 0, viewCount: 0, addedBy: null, addedByName: null,
  completedAt: null, completedBy: null, completedByName: null, completionUpdatedAt: null,
  createdAt: t, updatedAt: t, deleted: false, ...o,
});

describe('LocalDb outbox', () => {
  it('keeps one op per record (ten edits = one push) and pushes folders first', async () => {
    const db = await open();
    await db.saveItem(item({ title: 'v1' }), 'op1');
    await db.saveFolder(folder(), 'op2');
    await db.saveItem(item({ title: 'v2' }), 'op3');
    const ops = await db.pendingOps();
    expect(ops.map((o) => o.opId)).toEqual(['op2', 'op3']);
    expect(ops[1].payload.title).toBe('v2');
  });

  it('a record edited while its push was in flight stays queued', async () => {
    const db = await open();
    await db.saveItem(item({ title: 'v1' }), 'op1');
    const inFlight = await db.pendingOps();
    await db.saveItem(item({ title: 'v2' }), 'op2'); // edit during the push
    await db.completeOps(inFlight);
    expect((await db.pendingOps()).map((o) => o.opId)).toEqual(['op2']);
  });

  it('pulls never overwrite unpushed local edits', async () => {
    const db = await open();
    await db.saveItem(item({ title: 'mine, not pushed yet' }), 'op1');
    await db.applyServerChanges({ folders: [], items: [item({ title: 'server' })], members: [], accessibleFolderIds: new Set() });
    expect((await db.items())[0].title).toBe('mine, not pushed yet');
  });

  it('keeps the device-local view count when the server copy arrives', async () => {
    const db = await open();
    await db.saveItem(item({ viewCount: 2 }));
    await db.applyServerChanges({ folders: [], items: [item({ title: 'B' })], members: [], accessibleFolderIds: new Set() });
    expect((await db.items())[0]).toMatchObject({ title: 'B', viewCount: 2 });
  });

  it('drops shared boards you lost access to, and clears them on sign-out', async () => {
    const db = await open();
    await db.saveFolder(folder({ id: 'b1', isShared: true, myRole: 'editor' }));
    await db.saveItem(item({ id: 'p1', folderId: 'b1' }));
    await db.saveFolder(folder());
    await db.applyServerChanges({ folders: [], items: [], members: [], accessibleFolderIds: new Set(['f1']) });
    expect((await db.folders()).map((f) => f.id)).toEqual(['f1']);
    expect(await db.items()).toEqual([]);

    await db.saveFolder(folder({ id: 'b2', isShared: true }), 'op');
    await db.resetForSignOut();
    expect((await db.folders()).map((f) => f.id)).toEqual(['f1']);
    expect(await db.pendingCount()).toBe(0);
  });
});
