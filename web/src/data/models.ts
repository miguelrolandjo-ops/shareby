/** Shapes shared by IndexedDB, the sync layer and the UI. Same fields as the mobile app. */

export const UNCATEGORIZED = '__uncategorized__';

export type Role = 'owner' | 'editor' | 'viewer';
export type Source = 'instagram' | 'youtube' | 'tiktok' | 'web';

export interface Folder {
  id: string;
  name: string;
  color: number; // ARGB int, same as the phone app
  emoji: string;
  isShared: boolean;
  ownerId: string | null;
  myRole: Role;
  createdAt: string; // ISO-8601 UTC
  updatedAt: string;
  deleted: boolean;
}

export interface Item {
  id: string;
  /** null = Uncategorized. For [New] items: the suggested folder. */
  folderId: string | null;
  url: string;
  title: string;
  source: Source;
  /** null = not looked up yet, '' = looked up, nothing found. */
  thumbnailUrl: string | null;
  tag: string | null; // personal folders only
  status: 'new' | 'confirmed';
  suggestedFolderId: string | null;
  confidence: number;
  /** Device-local, never synced. */
  viewCount: number;
  addedBy: string | null;
  addedByName: string | null;
  completedAt: string | null;
  completedBy: string | null;
  completedByName: string | null;
  completionUpdatedAt: string | null;
  createdAt: string;
  updatedAt: string;
  deleted: boolean;
}

export interface Member {
  folderId: string;
  userId: string;
  displayName: string;
  role: Role;
}

export interface Session {
  userId: string;
  email: string;
  displayName: string;
  provider: 'google' | 'apple';
  token: string;
}

export const isDone = (i: Item) => i.completedAt !== null;
export const isNew = (i: Item) => i.status === 'new';
export const canAddLinks = (f: Folder) => f.id !== UNCATEGORIZED && (f.myRole === 'owner' || f.myRole === 'editor');

export const uncategorizedFolder = (): Folder => ({
  id: UNCATEGORIZED,
  name: 'Uncategorized',
  color: 0xff9aa39d,
  emoji: '🗂️',
  isShared: false,
  ownerId: null,
  myRole: 'owner',
  createdAt: '2020-01-01T00:00:00.000Z',
  updatedAt: '2020-01-01T00:00:00.000Z',
  deleted: false,
});

/** ARGB int -> CSS hex. */
export const css = (argb: number) => '#' + (argb & 0xffffff).toString(16).padStart(6, '0');

// ---------------------------------------------------------------- API mapping

type Json = Record<string, unknown>;
const str = (v: unknown) => (typeof v === 'string' ? v : null);

export function folderToApi(f: Folder): Json {
  return {
    id: f.id, name: f.name, color: f.color, emoji: f.emoji, is_shared: f.isShared,
    created_at: f.createdAt, updated_at: f.updatedAt, deleted_at: f.deleted ? f.updatedAt : null,
  };
}

export function folderFromApi(j: Json): Folder {
  return {
    id: j.id as string,
    name: j.name as string,
    color: Number(j.color),
    emoji: str(j.emoji) ?? '📁',
    isShared: j.is_shared === true,
    ownerId: str(j.owner_id),
    myRole: (str(j.my_role) as Role | null) ?? 'owner',
    createdAt: j.created_at as string,
    updatedAt: j.updated_at as string,
    deleted: j.deleted_at != null,
  };
}

/** view_count and display names are not sent: the server derives authorship from the session. */
export function itemToApi(i: Item): Json {
  return {
    id: i.id, folder_id: i.folderId, url: i.url, title: i.title, source: i.source,
    thumbnail_url: i.thumbnailUrl, tag: i.tag, status: i.status,
    suggested_folder_id: i.suggestedFolderId, confidence: i.confidence,
    completed_at: i.completedAt, completion_updated_at: i.completionUpdatedAt,
    created_at: i.createdAt, updated_at: i.updatedAt, deleted_at: i.deleted ? i.updatedAt : null,
  };
}

export function itemFromApi(j: Json): Item {
  return {
    id: j.id as string,
    folderId: str(j.folder_id),
    url: j.url as string,
    title: j.title as string,
    source: (str(j.source) as Source | null) ?? 'web',
    thumbnailUrl: str(j.thumbnail_url),
    tag: str(j.tag),
    status: j.status === 'new' ? 'new' : 'confirmed',
    suggestedFolderId: str(j.suggested_folder_id),
    confidence: typeof j.confidence === 'number' ? j.confidence : 0,
    viewCount: 0,
    addedBy: str(j.added_by),
    addedByName: str(j.added_by_name),
    completedAt: str(j.completed_at),
    completedBy: str(j.completed_by),
    completedByName: str(j.completed_by_name),
    completionUpdatedAt: str(j.completion_updated_at),
    createdAt: j.created_at as string,
    updatedAt: j.updated_at as string,
    deleted: j.deleted_at != null,
  };
}

export function memberFromApi(j: Json): Member {
  return {
    folderId: j.folder_id as string,
    userId: j.user_id as string,
    displayName: str(j.display_name) ?? 'Friend',
    role: (str(j.role) as Role | null) ?? 'editor',
  };
}
