import { useId, useState } from 'react';
import type { Folder } from '../../data/models';
import { FOLDER_COLORS, PALETTE } from '../../data/repository';
import { useApp, useStore } from '../../state/context';
import { personalFolders, sharedFolders } from '../../state/selectors';
import { soft } from '../components/bits';
import { SheetHead, useSheets } from '../components/Sheet';
import { friendlyError } from '../errors';
import { css } from '../../data/models';

const EMOJIS = ['📁', '🍳', '🏙️', '🌴', '☕', '🏀', '✨', '🏡', '🎬', '🛍️', '📚', '🎁'];
const COLOR_NAMES = ['Amber', 'Sky', 'Mint', 'Coral', 'Lilac', 'Grey'];

/** Create or edit a personal folder or a shared board. */
export function AddFolderSheet({ editing, shared = false, onCreated }: {
  editing?: Folder; shared?: boolean; onCreated?: (f: Folder) => void;
}) {
  const snap = useApp();
  const store = useStore();
  const { close } = useSheets();
  const isBoard = editing?.isShared ?? shared;
  const [name, setName] = useState(editing?.name ?? '');
  const [color, setColor] = useState(editing?.color ?? (isBoard ? PALETTE.lilac : PALETTE.amber));
  const [emoji, setEmoji] = useState(editing?.emoji ?? (isBoard ? '✨' : '📁'));
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const nameId = useId();

  const pool = isBoard ? sharedFolders(snap) : personalFolders(snap);
  const typed = name.trim().toLowerCase();
  const duplicate = !!typed && pool.some((f) => f.id !== editing?.id && f.name.toLowerCase() === typed);
  const noun = isBoard ? 'board' : 'folder';

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;
    try {
      if (editing) {
        await store.updateFolder(editing, { name, color, emoji });
        close();
      } else {
        const f = await store.createFolder({ name, color, emoji, shared: isBoard });
        close();
        onCreated?.(f);
      }
    } catch (err) {
      setError(friendlyError(err));
    }
  }

  async function remove() {
    if (!editing) return;
    await store.deleteFolder(editing);
    close();
    store.showToast(`Deleted ${editing.name}`);
  }

  return (
    <form onSubmit={save}>
      <SheetHead
        title={editing ? `Edit ${noun}` : isBoard ? 'New shared board' : 'New folder'}
        subtitle={isBoard ? 'Friends you invite can see and add pins. Shared boards have no tags or auto-sorting.' : 'New saves can be sorted into it automatically.'}
      />
      <label className="field" htmlFor={nameId}>
        <span>Name</span>
        <input id={nameId} className="input" value={name} maxLength={80} autoFocus={!editing}
          placeholder={isBoard ? 'e.g. Weekend Inspo' : 'e.g. Cooking'} onChange={(e) => setName(e.target.value)} />
        {duplicate && <span className="hint">You already have one with this name. This one will be saved as "{name.trim()} (2)".</span>}
      </label>

      <div className="field">
        <span id="emoji-label">Icon</span>
        <div className="emojis" role="radiogroup" aria-labelledby="emoji-label">
          {EMOJIS.map((e) => (
            <button key={e} type="button" role="radio" aria-checked={e === emoji} className="emoji-opt" onClick={() => setEmoji(e)}
              style={e === emoji ? { background: soft(color), borderColor: css(color) } : undefined}>{e}</button>
          ))}
        </div>
      </div>
      <div className="field">
        <span id="color-label">Color</span>
        <div className="swatches" role="radiogroup" aria-labelledby="color-label">
          {FOLDER_COLORS.map((c, i) => (
            <button key={c} type="button" role="radio" aria-checked={c === color} aria-label={COLOR_NAMES[i]}
              className="swatch" style={{ background: css(c) }} onClick={() => setColor(c)} />
          ))}
        </div>
      </div>

      {error && <p className="error" role="alert" style={{ marginBottom: 10 }}>{error}</p>}
      <button className="btn primary block" disabled={!name.trim()}>
        {editing ? 'Save changes' : isBoard ? 'Create board' : 'Create folder'}
      </button>

      {editing?.myRole === 'owner' && (
        confirmDelete ? (
          <div className="card" style={{ background: 'var(--bg)', marginTop: 12 }}>
            <p className="small" style={{ marginBottom: 10 }}>
              {editing.isShared ? 'The board and its pins are removed for everyone in it.' : 'Its links move to Uncategorized. Nothing you saved is lost.'}
            </p>
            <div className="row">
              <button type="button" className="btn small" onClick={() => setConfirmDelete(false)}>Cancel</button>
              <button type="button" className="btn small" style={{ color: 'var(--danger)' }} onClick={remove}>Delete {noun}</button>
            </div>
          </div>
        ) : (
          <button type="button" className="btn danger block" style={{ marginTop: 8 }} onClick={() => setConfirmDelete(true)}>Delete {noun}</button>
        )
      )}
    </form>
  );
}
