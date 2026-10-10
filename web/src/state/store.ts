import { config } from '../config';
import { ApiClient, ApiUnreachable } from '../data/api';
import { LocalDb } from '../data/localDb';
import type { Folder, Item, Member, Role, Session } from '../data/models';
import { Repository } from '../data/repository';
import { SessionStore } from '../data/session';
import { SyncService } from '../data/sync';

export type SyncState = 'localOnly' | 'syncing' | 'synced' | 'offline' | 'error';

export interface Toast {
  id: number;
  message: string;
  action?: { label: string; run: () => void };
}

export interface Snapshot {
  ready: boolean;
  folders: Folder[];
  items: Item[];
  members: Member[];
  session: Session | null;
  syncState: SyncState;
  syncMessage: string | null;
  lastSyncedAt: number | null;
  pendingChanges: number;
  toast: Toast | null;
}

/**
 * The one object the UI subscribes to. Reads are in-memory snapshots of IndexedDB;
 * every action writes locally first, refreshes the snapshot, then schedules a sync.
 */
export class AppStore {
  private snap: Snapshot = {
    ready: false, folders: [], items: [], members: [], session: null,
    syncState: 'localOnly', syncMessage: null, lastSyncedAt: null, pendingChanges: 0, toast: null,
  };
  private listeners = new Set<() => void>();
  private debounce: ReturnType<typeof setTimeout> | undefined;
  private toastSeq = 0;

  private constructor(
    private readonly db: LocalDb,
    private readonly sessions: SessionStore,
    readonly repo: Repository,
    private readonly sync: SyncService,
    private readonly api: ApiClient,
  ) {}

  static async create(): Promise<AppStore> {
    const db = await LocalDb.open();
    const sessions = new SessionStore();
    const api = new ApiClient(config.apiBase, () => sessions.session?.token ?? null);
    return new AppStore(db, sessions, new Repository(db, sessions), new SyncService(db, api, sessions), api);
  }

  // ------------------------------------------------- useSyncExternalStore

  subscribe = (listener: () => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };
  getSnapshot = () => this.snap;

  private set(patch: Partial<Snapshot>) {
    this.snap = { ...this.snap, ...patch };
    this.listeners.forEach((l) => l());
  }

  // ------------------------------------------------------------ lifecycle

  async init(): Promise<void> {
    await this.repo.seedIfNeeded();
    await this.countImpressions();
    await this.reload();
    this.set({ ready: true, session: this.sessions.session });

    setInterval(() => void this.syncNow(), config.syncIntervalMs);
    window.addEventListener('online', () => void this.syncNow()); // back online: sync right away
    window.addEventListener('offline', () => this.signedIn && this.set({ syncState: 'offline' }));
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') void this.onVisible();
    });
    void this.syncNow();
  }

  private async onVisible() {
    await this.countImpressions();
    await this.reload();
    void this.syncNow();
  }

  /**
   * Each visit counts as one showing of [New] links. Unlike a phone app, a browser
   * reloads often, so the last count is persisted and visits under 10 min apart
   * (refreshes, tab switches) count once.
   */
  private async countImpressions() {
    const key = 'shareby.lastImpressions.v1';
    const last = Number(localStorage.getItem(key) ?? 0);
    if (Date.now() - last < 10 * 60_000) return;
    localStorage.setItem(key, String(Date.now()));
    const auto = await this.repo.registerImpressions();
    if (auto > 0) {
      this.showToast(auto === 1 ? '1 save was filed automatically' : `${auto} saves were filed automatically`);
      this.scheduleSync();
    }
  }

  async reload(): Promise<void> {
    const [folders, items, members, pendingChanges] = await Promise.all([
      this.db.folders(), this.db.items(), this.db.members(), this.db.pendingCount(),
    ]);
    this.set({ folders, items, members, pendingChanges, session: this.sessions.session });
  }

  get signedIn() {
    return this.sessions.signedIn;
  }

  // ----------------------------------------------------------------- sync

  private scheduleSync() {
    clearTimeout(this.debounce);
    this.debounce = setTimeout(() => void this.syncNow(), 2000);
  }

  syncNow = async (): Promise<void> => {
    if (!this.signedIn) {
      this.set({ syncState: 'localOnly' });
      return;
    }
    this.set({ syncState: 'syncing' });
    const r = await this.sync.run();
    switch (r.kind) {
      case 'ok':
        this.set({
          syncState: 'synced', lastSyncedAt: Date.now(),
          syncMessage: r.rejected ? `${r.rejected} change(s) weren't allowed and were undone` : null,
        });
        break;
      case 'offline':
        this.set({ syncState: 'offline', syncMessage: null });
        break;
      case 'sessionExpired':
        await this.signOutLocally();
        this.showToast('Your session expired. Sign in again to keep syncing.');
        break;
      case 'error':
        this.set({ syncState: 'error', syncMessage: r.message });
        break;
      case 'notSignedIn':
        this.set({ syncState: 'localOnly' });
    }
    await this.reload();
  };

  private async mutate<T>(action: () => Promise<T>): Promise<T> {
    const result = await action();
    await this.reload();
    this.scheduleSync();
    return result;
  }

  // -------------------------------------------------------------- actions

  createFolder = (input: { name: string; color: number; emoji: string; shared?: boolean }) =>
    this.mutate(() => this.repo.createFolder(input));
  updateFolder = (f: Folder, changes: Partial<Pick<Folder, 'name' | 'color' | 'emoji'>>) =>
    this.mutate(() => this.repo.updateFolder(f, changes));
  deleteFolder = (f: Folder) => this.mutate(() => this.repo.deleteFolder(f));
  addLink = (input: { url: string; title?: string; folderId?: string }) => this.mutate(() => this.repo.addLink(input));
  confirmItem = (item: Item, moveTo?: string) => this.mutate(() => this.repo.confirmItem(item, moveTo));
  setTag = (item: Item, tag: string | null) => this.mutate(() => this.repo.setTag(item, tag));
  deleteItem = (item: Item) => this.mutate(() => this.repo.deleteItem(item));
  restoreItem = (item: Item) => this.mutate(() => this.repo.restoreItem(item));
  setDone = (item: Item, done: boolean) => this.mutate(() => this.repo.setDone(item, done));

  restoreCompletion = async (previous: Item) => {
    const current = this.snap.items.find((i) => i.id === previous.id);
    if (current) await this.mutate(() => this.repo.restoreCompletion(current, previous));
  };

  /** Invites need the board on the server, so sync first; needs a connection. */
  invite = async (board: Folder, email: string, role: Exclude<Role, 'owner'>): Promise<'added' | 'pending'> => {
    const pre = await this.sync.run();
    if (pre.kind === 'offline') throw new ApiUnreachable();
    const res = await this.api.invite(board.id, email.trim(), role);
    void this.syncNow();
    return res.status === 'added' ? 'added' : 'pending';
  };

  /**
   * Development sign-in (any email). For production, get a Google ID token from
   * Google Identity Services and call api.googleLogin(token) here instead.
   */
  signIn = async (provider: 'google' | 'apple', email: string, displayName: string): Promise<void> => {
    const body = await this.api.devLogin(email, displayName, provider);
    const user = body.user as Record<string, string>;
    this.sessions.save({ userId: user.id, email: user.email, displayName: user.display_name, provider, token: body.token as string });
    await this.repo.enqueueFullUpload(); // this browser's saves move to the cloud
    await this.reload();
    await this.syncNow();
  };

  signOut = async () => {
    await this.signOutLocally();
    await this.reload();
  };

  private async signOutLocally() {
    await this.db.resetForSignOut();
    this.sessions.clear();
    this.set({ syncState: 'localOnly', syncMessage: null, lastSyncedAt: null, session: null });
  }

  // --------------------------------------------------------------- toasts

  showToast = (message: string, action?: Toast['action']) => {
    this.set({ toast: { id: ++this.toastSeq, message, action } });
  };
  dismissToast = (id: number) => {
    if (this.snap.toast?.id === id) this.set({ toast: null });
  };
}
