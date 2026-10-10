import {
  canAddLinks, isNew, UNCATEGORIZED, uncategorizedFolder,
  type Folder, type Item, type Member,
} from '../data/models';
import type { Snapshot } from './store';

export const personalFolders = (s: Snapshot) => s.folders.filter((f) => !f.isShared);
export const sharedFolders = (s: Snapshot) => s.folders.filter((f) => f.isShared);
export const newItems = (s: Snapshot) => s.items.filter(isNew);
export const hasUncategorized = (s: Snapshot) => s.items.some((i) => i.folderId === null);

export function folderById(s: Snapshot, id: string | null | undefined): Folder | undefined {
  if (!id) return undefined;
  if (id === UNCATEGORIZED) return uncategorizedFolder();
  return s.folders.find((f) => f.id === id);
}

/** The folder an item lives in (or is suggested into); Uncategorized when none. */
export const folderOf = (s: Snapshot, item: Item): Folder =>
  folderById(s, item.folderId) ?? uncategorizedFolder();

/** Includes [New] items suggested into the folder. */
export const itemsIn = (s: Snapshot, folderId: string): Item[] =>
  folderId === UNCATEGORIZED ? s.items.filter((i) => i.folderId === null) : s.items.filter((i) => i.folderId === folderId);

export const membersOf = (s: Snapshot, folderId: string): Member[] => s.members.filter((m) => m.folderId === folderId);

/** Confirmed links in personal folders, or on boards you can add to. */
export function canMarkDone(s: Snapshot, item: Item): boolean {
  if (isNew(item)) return false;
  const f = folderById(s, item.folderId);
  return !f || !f.isShared || canAddLinks(f);
}

export function doneByLabel(item: Item, myUserId: string | undefined): string {
  if (item.completedBy && item.completedBy === myUserId) return 'Done by you';
  const name = item.completedByName;
  return !name || name === 'You' ? 'Done by you' : `Done by ${name}`;
}

export function syncLabel(s: Snapshot): string {
  switch (s.syncState) {
    case 'localOnly':
      return 'Saved in this browser only';
    case 'syncing':
      return 'Syncing...';
    case 'synced':
      return s.pendingChanges > 0 ? `${s.pendingChanges} change(s) waiting to sync` : 'Synced to your Shareby account';
    case 'offline':
      return s.pendingChanges > 0
        ? `Offline. ${s.pendingChanges} change(s) will sync when you're back online`
        : 'Offline. Your saves are safe in this browser';
    case 'error':
      return s.syncMessage ?? "Couldn't sync. Will retry shortly";
  }
}

export const plural = (n: number, one: string, many = one + 's') => `${n} ${n === 1 ? one : many}`;
