import type { Session } from './models';

/**
 * Small key-value state in localStorage: the signed-in session, the sync cursor,
 * and first-run flags. (Links themselves live in IndexedDB.)
 * Production hardening: move the token to an httpOnly cookie set by the API.
 */
const KEYS = { session: 'shareby.session.v1', cursor: 'shareby.pullCursor.v1', seeded: 'shareby.seeded.v1' };

export class SessionStore {
  private current: Session | null = null;

  constructor(private readonly storage: Storage = localStorage) {
    const raw = storage.getItem(KEYS.session);
    if (raw) {
      try {
        this.current = JSON.parse(raw) as Session;
      } catch {
        storage.removeItem(KEYS.session);
      }
    }
  }

  get session(): Session | null {
    return this.current;
  }
  get signedIn(): boolean {
    return this.current !== null;
  }

  save(s: Session): void {
    this.current = s;
    this.storage.setItem(KEYS.session, JSON.stringify(s));
  }

  clear(): void {
    this.current = null;
    this.storage.removeItem(KEYS.session);
    this.storage.removeItem(KEYS.cursor);
  }

  get pullCursor(): string | null {
    return this.storage.getItem(KEYS.cursor);
  }
  setPullCursor(cursor: string | null): void {
    if (cursor === null) this.storage.removeItem(KEYS.cursor);
    else this.storage.setItem(KEYS.cursor, cursor);
  }

  get seeded(): boolean {
    return this.storage.getItem(KEYS.seeded) === '1';
  }
  markSeeded(): void {
    this.storage.setItem(KEYS.seeded, '1');
  }
}
