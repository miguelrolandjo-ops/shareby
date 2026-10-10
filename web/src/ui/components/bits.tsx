import { Camera, Check, CircleAlert, CloudCheck, CloudOff, Info, Link2, Music, Play, RefreshCw, Smartphone } from 'lucide-react';
import { useState, type ReactNode } from 'react';
import { css, type Folder, type Item, type Member, type Source } from '../../data/models';
import type { Snapshot } from '../../state/store';
import { syncLabel } from '../../state/selectors';

/** Folder color helpers: soft tint for backgrounds, deep shade for text on it. */
export const soft = (argb: number) => `color-mix(in srgb, ${css(argb)} 20%, white)`;
export const deep = (argb: number) => `color-mix(in srgb, ${css(argb)} 55%, #16302B)`;

const SOURCE_ICON: Record<Source, typeof Play> = { youtube: Play, instagram: Camera, tiktok: Music, web: Link2 };
const SOURCE_PILL: Record<Source, [string, string]> = {
  youtube: ['YT', '#D93025'],
  instagram: ['IG', '#D62976'],
  tiktok: ['TT', '#111111'],
  web: ['WEB', '#5B7168'],
};

/**
 * Card image. The real thumbnail when there is one and it loads; otherwise a
 * placeholder drawn from the folder color and the source icon (offline, blocked, none).
 */
export function Thumb({ item, color, size, className = '' }: { item: Item; color: number; size?: number; className?: string }) {
  const [failed, setFailed] = useState(false);
  const Icon = SOURCE_ICON[item.source];
  const showImage = !!item.thumbnailUrl && !failed;
  return (
    <div
      className={`thumb ${className}`}
      style={{
        width: size, height: size,
        background: `linear-gradient(135deg, ${css(color)}, color-mix(in srgb, ${css(color)} 40%, white))`,
      }}
    >
      {showImage ? (
        <img src={item.thumbnailUrl!} alt="" loading="lazy" referrerPolicy="no-referrer" onError={() => setFailed(true)} />
      ) : (
        <div className="ph" aria-hidden><Icon size={22} /></div>
      )}
    </div>
  );
}

export function SourcePill({ source }: { source: Source }) {
  const [label, bg] = SOURCE_PILL[source];
  return <span className="pill" style={{ background: bg }} aria-label={source}>{label}</span>;
}

export const NewPill = () => <span className="pill new">New</span>;

const AVATAR_COLORS = [0xffe8a23d, 0xff4c9fe0, 0xff2fa88f, 0xffef6f5e, 0xff9a7fd1];
export function avatarColor(seed: string): number {
  let h = 7;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) & 0x7fffffff;
  return AVATAR_COLORS[h % AVATAR_COLORS.length];
}

export function Avatar({ name, seed, size = 32 }: { name: string; seed?: string | null; size?: number }) {
  const c = avatarColor(seed ?? name);
  return (
    <span className="avatar" title={name}
      style={{ width: size, height: size, fontSize: size * 0.4, background: soft(c), color: deep(c) }}>
      {(name.trim()[0] ?? '?').toUpperCase()}
    </span>
  );
}

export function AvatarStack({ members, size = 28, max = 4 }: { members: Member[]; size?: number; max?: number }) {
  return (
    <span className="avatar-stack">
      {members.slice(0, max).map((m) => <Avatar key={m.userId} name={m.displayName} seed={m.userId} size={size} />)}
    </span>
  );
}

/** The done tick. aria-pressed so screen readers announce it as a toggle. */
export function Tick({ done, onToggle, overlay = false }: { done: boolean; onToggle: () => void; overlay?: boolean }) {
  return (
    <button
      type="button"
      className={`tick${done ? ' on' : ''}${overlay ? ' over' : ''}`}
      aria-pressed={done}
      aria-label={done ? 'Done. Mark as not done' : 'Mark as done'}
      onClick={(e) => {
        e.stopPropagation();
        onToggle();
      }}
    >
      <span><Check size={16} strokeWidth={3} /></span>
    </button>
  );
}

export function FolderCard({ folder, count, newCount, doneCount, onOpen }: {
  folder: Folder; count: number; newCount: number; doneCount: number; onOpen: () => void;
}) {
  return (
    <a
      className="folder-card"
      href={`/folders/${folder.id}`}
      onClick={(e) => { e.preventDefault(); onOpen(); }}
      style={{ background: soft(folder.color), color: deep(folder.color) }}
    >
      <div className="row">
        <div className="emoji" aria-hidden>{folder.emoji}</div>
        <span className="grow" />
        {newCount > 0 && <NewPill />}
      </div>
      <div>
        <h3>{folder.name}</h3>
        <p>{count === 1 ? '1 link' : `${count} links`}{doneCount > 0 ? `, ${doneCount} done` : ''}</p>
      </div>
    </a>
  );
}

export function SyncLine({ snap }: { snap: Snapshot }) {
  const [Icon, color] = {
    localOnly: [Smartphone, 'var(--ink-soft)'],
    syncing: [RefreshCw, 'var(--brand)'],
    synced: [CloudCheck, 'var(--brand)'],
    offline: [CloudOff, 'var(--amber-ink)'],
    error: [CircleAlert, 'var(--danger)'],
  }[snap.syncState] as [typeof Info, string];
  return (
    <p className="sync-line" style={{ color }} role="status">
      <Icon size={16} aria-hidden /> {syncLabel(snap)}
    </p>
  );
}

export function Note({ children, icon }: { children: ReactNode; icon?: ReactNode }) {
  return <div className="note">{icon ?? <Info size={17} aria-hidden />}<div>{children}</div></div>;
}
