import { config } from '../config';
import { suggest, type Suggestion } from './categorizer';
import { nowIso, uuid } from './ids';
import type { LocalDb } from './localDb';
import { canAddLinks, UNCATEGORIZED, type Folder, type Item } from './models';
import type { SessionStore } from './session';
import { detectSource, fallbackTitle, youtubeThumbnail } from './urlUtils';

export const PALETTE = {
  amber: 0xffe8a23d,
  sky: 0xff4c9fe0,
  mint: 0xff2fa88f,
  coral: 0xffef6f5e,
  lilac: 0xff9a7fd1,
  grey: 0xff9aa39d,
};
export const FOLDER_COLORS = Object.values(PALETTE);

/** A user-facing problem ("You can view this board but not change it"). */
export class UserError extends Error {}

/**
 * Every change goes through here: written to IndexedDB first (works offline), and
 * when signed in also queued in the outbox in the same transaction.
 */
export class Repository {
  constructor(private readonly db: LocalDb, private readonly sessions: SessionStore) {}

  /** Only queue for sync once there is an account to sync to. */
  private get opId() {
    return this.sessions.signedIn ? uuid() : undefined;
  }
  private save = (f: Folder) => this.db.saveFolder(f, this.opId);
  private saveItem = (i: Item) => this.db.saveItem(i, this.opId);

  // -------------------------------------------------------------- folders

  async createFolder(input: { name: string; color: number; emoji: string; shared?: boolean }): Promise<Folder> {
    const shared = input.shared ?? false;
    if (shared && !this.sessions.signedIn) throw new UserError('Sign in with Google or Apple to create shared boards.');
    const now = nowIso();
    const folder: Folder = {
      id: uuid(),
      name: await this.uniqueName(input.name.trim(), shared),
      color: input.color,
      emoji: input.emoji,
      isShared: shared,
      ownerId: this.sessions.session?.userId ?? null,
      myRole: 'owner',
      createdAt: now,
      updatedAt: now,
      deleted: false,
    };
    await this.save(folder);
    return folder;
  }

  /** Duplicate names are allowed; the copy becomes "Name (2)", "Name (3)"... */
  private async uniqueName(name: string, shared: boolean): Promise<string> {
    const taken = new Set((await this.db.folders()).filter((f) => f.isShared === shared).map((f) => f.name.toLowerCase()));
    if (!taken.has(name.toLowerCase())) return name;
    let n = 2;
    while (taken.has(`${name.toLowerCase()} (${n})`)) n++;
    return `${name} (${n})`;
  }

  updateFolder(f: Folder, changes: Partial<Pick<Folder, 'name' | 'color' | 'emoji'>>) {
    return this.save({ ...f, ...changes, name: (changes.name ?? f.name).trim(), updatedAt: nowIso() });
  }

  /** A personal folder's links move to Uncategorized; a board's pins go with it. */
  async deleteFolder(f: Folder): Promise<void> {
    const now = nowIso();
    await this.save({ ...f, deleted: true, updatedAt: now });
    for (const item of (await this.db.items()).filter((i) => i.folderId === f.id)) {
      await this.saveItem(f.isShared
        ? { ...item, deleted: true, updatedAt: now }
        : { ...item, folderId: null, status: 'confirmed', updatedAt: now });
    }
  }

  // ---------------------------------------------------------------- items

  /**
   * folderId undefined -> "sort it for me": suggest a personal folder, mark [New].
   * folderId UNCATEGORIZED -> keep in Uncategorized. Otherwise straight into that folder.
   */
  async addLink(input: { url: string; title?: string; folderId?: string }): Promise<Item> {
    const now = nowIso();
    const user = this.sessions.session;
    const title = input.title?.trim() || fallbackTitle(input.url);
    let folderId: string | null = null;
    let status: Item['status'] = 'confirmed';
    let suggestion: Suggestion = { folderId: null, confidence: 0 };

    if (input.folderId === undefined) {
      suggestion = await this.suggestFor(`${title} ${input.url}`);
      folderId = suggestion.folderId;
      status = 'new';
    } else if (input.folderId !== UNCATEGORIZED) {
      const folder = await this.db.folderById(input.folderId);
      if (!folder || folder.deleted) throw new UserError('That collection no longer exists.');
      if (!canAddLinks(folder)) throw new UserError('You can view this board but not add to it.');
      folderId = folder.id;
    }

    const item: Item = {
      id: uuid(),
      folderId,
      url: input.url,
      title,
      source: detectSource(input.url),
      thumbnailUrl: youtubeThumbnail(input.url),
      tag: null,
      status,
      suggestedFolderId: suggestion.folderId,
      confidence: suggestion.confidence,
      viewCount: 0,
      addedBy: user?.userId ?? null,
      addedByName: user?.displayName ?? null,
      completedAt: null,
      completedBy: null,
      completedByName: null,
      completionUpdatedAt: null,
      createdAt: now,
      updatedAt: now,
      deleted: false,
    };
    await this.saveItem(item);
    return item;
  }

  /** Auto-sorting only ever considers personal folders. */
  async suggestFor(text: string): Promise<Suggestion> {
    const folders = (await this.db.folders()).filter((f) => !f.isShared);
    const items = await this.db.items();
    return suggest(
      text,
      folders.map((f) => ({
        id: f.id,
        name: f.name,
        examples: items.filter((i) => i.folderId === f.id && i.status === 'confirmed').slice(0, 25).map((i) => i.title),
      })),
      config.suggestionThreshold,
    );
  }

  confirmItem(item: Item, moveTo?: string) {
    const target = moveTo ?? item.folderId ?? UNCATEGORIZED;
    return this.saveItem({
      ...item,
      folderId: target === UNCATEGORIZED ? null : target,
      status: 'confirmed',
      updatedAt: nowIso(),
    });
  }

  /** Tags are a personal-folder feature. */
  async setTag(item: Item, tag: string | null): Promise<void> {
    if (item.folderId && (await this.db.folderById(item.folderId))?.isShared) {
      throw new UserError('Tags are only available in your personal folders.');
    }
    const clean = tag?.trim() || null;
    await this.saveItem({ ...item, tag: clean, updatedAt: nowIso() });
  }

  deleteItem(item: Item) {
    return this.saveItem({ ...item, deleted: true, updatedAt: nowIso() });
  }

  /** Undo for deleteItem (deletes are soft until synced, and stay soft after). */
  restoreItem(item: Item) {
    return this.saveItem({ ...item, deleted: false, updatedAt: nowIso() });
  }

  /**
   * Done checkmark. Only completion fields change (with their own timestamp), so a
   * friend's tick never conflicts with someone else's edit to the title or folder.
   */
  async setDone(item: Item, done: boolean): Promise<void> {
    if (item.status === 'new') throw new UserError('Confirm which folder this goes in first, then mark it done.');
    await this.requireCanChange(item);
    const now = nowIso();
    const user = this.sessions.session;
    await this.saveItem(done
      ? { ...item, completedAt: now, completedBy: user?.userId ?? null, completedByName: user?.displayName ?? 'You', completionUpdatedAt: now }
      : { ...item, completedAt: null, completedBy: null, completedByName: null, completionUpdatedAt: now });
  }

  /** Undo for setDone: restores exactly who ticked it and when. */
  async restoreCompletion(current: Item, previous: Item): Promise<void> {
    await this.requireCanChange(current);
    await this.saveItem({
      ...current,
      completedAt: previous.completedAt,
      completedBy: previous.completedBy,
      completedByName: previous.completedByName,
      completionUpdatedAt: nowIso(),
    });
  }

  private async requireCanChange(item: Item) {
    if (!item.folderId) return;
    const folder = await this.db.folderById(item.folderId);
    if (folder?.isShared && !canAddLinks(folder)) throw new UserError('You can view this board but not change it.');
  }

  /**
   * Call when [New] links are shown. One already shown `autoConfirmAfterViews` times
   * is confirmed now. Returns how many were auto-confirmed.
   */
  async registerImpressions(): Promise<number> {
    let confirmed = 0;
    for (const item of (await this.db.items()).filter((i) => i.status === 'new')) {
      if (item.viewCount >= config.autoConfirmAfterViews) {
        await this.confirmItem(item);
        confirmed++;
      } else {
        await this.db.setViewCount(item.id, item.viewCount + 1);
      }
    }
    return confirmed;
  }

  /** First sign-in: queue everything in this browser so it moves to the cloud. */
  async enqueueFullUpload(): Promise<void> {
    for (const f of await this.db.folders()) await this.db.saveFolder(f, uuid());
    for (const i of await this.db.items()) await this.db.saveItem(i, uuid());
  }

  // ------------------------------------------------------------ demo seed

  async seedIfNeeded(): Promise<void> {
    if (!config.seedDemoData || this.sessions.seeded || !(await this.db.isEmpty())) {
      this.sessions.markSeeded();
      return;
    }
    let tick = 0;
    const base = Date.now() - 3 * 24 * 3600_000;
    const at = () => new Date(base + tick++ * 60_000).toISOString();

    const folder = async (name: string, color: number, emoji: string) => {
      const t = at();
      const f: Folder = { id: uuid(), name, color, emoji, isShared: false, ownerId: null, myRole: 'owner', createdAt: t, updatedAt: t, deleted: false };
      await this.db.saveFolder(f);
      return f;
    };
    const link = async (f: Folder, title: string, url: string, o: { tag?: string; isNew?: boolean; views?: number; done?: boolean } = {}) => {
      const t = at();
      await this.db.saveItem({
        id: uuid(), folderId: f.id, url, title, source: detectSource(url), thumbnailUrl: null,
        tag: o.tag ?? null, status: o.isNew ? 'new' : 'confirmed', suggestedFolderId: o.isNew ? f.id : null,
        confidence: o.isNew ? 0.72 : 0, viewCount: o.views ?? 0, addedBy: null, addedByName: null,
        completedAt: o.done ? t : null, completedBy: null, completedByName: o.done ? 'You' : null,
        completionUpdatedAt: o.done ? t : null, createdAt: t, updatedAt: t, deleted: false,
      });
    };

    const cooking = await folder('Cooking', PALETTE.amber, '🍳');
    const jakarta = await folder('Jakarta Trip', PALETTE.sky, '🏙️');
    const bali = await folder('Bali Trip', PALETTE.mint, '🌴');
    const cafe = await folder('Cafe Picks', PALETTE.coral, '☕');
    const sports = await folder('Sports Vibe', PALETTE.lilac, '🏀');

    await link(cooking, 'Resep nasi goreng cuma butuh 3 bahan', 'https://www.instagram.com/reel/shareby-demo-1', { tag: 'Jumat gas' });
    await link(cooking, 'Cheesecake no-bake yang lumer di mulut', 'https://www.tiktok.com/@shareby/video/1001', { tag: 'Dessert' });
    await link(cooking, 'Cara bikin bumbu rendang tahan lama', 'https://www.instagram.com/reel/shareby-demo-2');
    await link(jakarta, 'Rooftop bar Senopati buat nongkrong malam', 'https://www.instagram.com/p/shareby-demo-3', { done: true });
    await link(jakarta, 'Itinerary sehari muter Kota Tua', 'https://www.youtube.com/watch?v=shareby0001', { tag: 'Day trip' });
    await link(bali, 'Sunrise trek Gunung Batur worth it banget', 'https://www.youtube.com/watch?v=shareby0002', { tag: 'Must do' });
    await link(bali, 'Warung lokal murah enak di Canggu', 'https://www.instagram.com/reel/shareby-demo-4');
    await link(cafe, 'Kopi susu terenak murah di Kemang', 'https://www.instagram.com/reel/shareby-demo-5', { tag: 'Under 25rb' });
    await link(sports, 'Home workout 15 menit tanpa alat', 'https://www.instagram.com/reel/shareby-demo-6');
    await link(cooking, 'Ayam geprek sambel korek pedas nampol', 'https://www.youtube.com/watch?v=shareby0003', { isNew: true });
    await link(cafe, 'Dessert box viral yang wajib dicoba', 'https://www.tiktok.com/@shareby/video/1002', { isNew: true });
    await link(jakarta, 'Spot foto golden hour di GBK', 'https://www.tiktok.com/@shareby/video/1003', { isNew: true, views: 1 });
    this.sessions.markSeeded();
  }
}
