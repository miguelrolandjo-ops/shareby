import { ApiClient, ApiError, ApiUnreachable } from './api';
import { nowIso, uuid } from './ids';
import type { LocalDb } from './localDb';
import { folderFromApi, itemFromApi, memberFromApi } from './models';
import type { SessionStore } from './session';
import { isFallbackTitle } from './urlUtils';

export type SyncOutcome =
  | { kind: 'ok'; rejected: number }
  | { kind: 'offline' }
  | { kind: 'sessionExpired'; message: string }
  | { kind: 'error'; message: string }
  | { kind: 'notSignedIn' };

type Json = Record<string, unknown>;
const list = (v: unknown): Json[] => (Array.isArray(v) ? v.filter((x): x is Json => !!x && typeof x === 'object') : []);

/** Push the outbox, then pull. Same protocol as the phone app. Overlapping calls share one run. */
export class SyncService {
  private inFlight: Promise<SyncOutcome> | null = null;

  constructor(private readonly db: LocalDb, readonly api: ApiClient, private readonly sessions: SessionStore) {}

  run(): Promise<SyncOutcome> {
    if (!this.sessions.signedIn) return Promise.resolve({ kind: 'notSignedIn' });
    this.inFlight ??= this.runOnce().finally(() => (this.inFlight = null));
    return this.inFlight;
  }

  private async runOnce(): Promise<SyncOutcome> {
    try {
      const rejected = await this.push();
      // A refused change was already applied locally: pull everything once so this
      // browser shows the server's version again.
      if (rejected > 0) this.sessions.setPullCursor(null);
      await this.pull();
      await this.resolvePreviews();
      await this.push();
      return { kind: 'ok', rejected };
    } catch (e) {
      if (e instanceof ApiUnreachable) return { kind: 'offline' };
      if (e instanceof ApiError && e.status === 401) return { kind: 'sessionExpired', message: e.message };
      if (e instanceof ApiError) return { kind: 'error', message: e.message };
      throw e;
    }
  }

  private async push(): Promise<number> {
    let rejected = 0;
    for (let round = 0; round < 40; round++) {
      const ops = await this.db.pendingOps(50);
      if (!ops.length) break;
      const res = await this.api.push(ops.map((o) => ({ op_id: o.opId, entity: o.entity, data: o.payload })));
      const done = new Set<string>(Array.isArray(res.applied) ? res.applied.filter((x): x is string => typeof x === 'string') : []);
      for (const r of list(res.rejected)) {
        if (typeof r.op_id === 'string') {
          done.add(r.op_id);
          rejected++;
        }
      }
      if (!done.size) break; // no progress; try again next sync
      await this.db.completeOps(ops.filter((o) => done.has(o.opId)));
    }
    return rejected;
  }

  private async pull(): Promise<void> {
    const res = await this.api.pull(this.sessions.pullCursor);
    await this.db.applyServerChanges({
      folders: list(res.folders).map(folderFromApi),
      items: list(res.items).map(itemFromApi),
      members: list(res.members).map(memberFromApi),
      accessibleFolderIds: new Set(Array.isArray(res.accessible_folder_ids) ? res.accessible_folder_ids.filter((x): x is string => typeof x === 'string') : []),
      full: res.full === true,
    });
    if (typeof res.cursor === 'string') this.sessions.setPullCursor(res.cursor);
  }

  /** Card images from Open Graph tags, a few per sync. '' = looked up, nothing found. */
  private async resolvePreviews(): Promise<void> {
    const me = this.sessions.session?.userId;
    const pending = (await this.db.items())
      .filter((i) => i.thumbnailUrl === null && i.source !== 'youtube' && (!i.addedBy || i.addedBy === me))
      .slice(0, 5);
    for (const item of pending) {
      let image = '';
      let title = item.title;
      try {
        const res = await this.api.preview(item.url);
        if (typeof res.image === 'string' && res.image.startsWith('http')) image = res.image;
        if (typeof res.title === 'string' && res.title.trim() && isFallbackTitle(item.title)) title = res.title.trim();
      } catch (e) {
        if (!(e instanceof ApiError)) throw e; // offline: stop, retry next sync
      }
      await this.db.saveItem({ ...item, thumbnailUrl: image, title, updatedAt: nowIso() }, uuid());
    }
  }
}
