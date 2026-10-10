import { CircleCheck, Circle, ExternalLink, FolderInput, ListChecks, Tag, Trash2 } from 'lucide-react';
import { useState } from 'react';
import { isDone, isNew, type Item } from '../../data/models';
import { useApp, useStore } from '../../state/context';
import { canMarkDone, folderOf } from '../../state/selectors';
import { SourcePill, Thumb } from '../components/bits';
import { SheetHead, useSheets } from '../components/Sheet';
import { useActions } from '../actions';
import { friendlyError } from '../errors';
import { ConfirmItemSheet } from './ConfirmItemSheet';

/** Per-link menu (the ⋯ button, right-click). Tag and move are personal-folder features. */
export function ItemActionsSheet({ item }: { item: Item }) {
  const snap = useApp();
  const store = useStore();
  const sheets = useSheets();
  const { openLink, toggleDone } = useActions();
  const [editingTag, setEditingTag] = useState(false);
  const [tag, setTag] = useState(item.tag ?? '');
  const folder = folderOf(snap, item);
  const me = snap.session?.userId;
  const canDelete = !folder.isShared || folder.myRole === 'owner' || item.addedBy === me;

  const run = (fn: () => void) => () => { sheets.close(); fn(); };

  async function saveTag(e: React.FormEvent) {
    e.preventDefault();
    try {
      await store.setTag(item, tag);
      sheets.close();
    } catch (err) {
      store.showToast(friendlyError(err));
    }
  }

  async function remove() {
    sheets.close();
    await store.deleteItem(item);
    store.showToast(folder.isShared ? 'Pin removed' : 'Link deleted', { label: 'Undo', run: () => void store.restoreItem(item) });
  }

  return (
    <div>
      <SheetHead title="Link" />
      <div className="row" style={{ marginBottom: 10 }}>
        <Thumb item={item} color={folder.color} size={48} />
        <div className="grow"><p style={{ fontWeight: 700 }}>{item.title}</p><SourcePill source={item.source} /></div>
      </div>

      {editingTag ? (
        <form onSubmit={saveTag} className="row" style={{ margin: '12px 0' }}>
          <input className="input grow" autoFocus maxLength={40} placeholder="e.g. Must try" value={tag}
            aria-label="Tag" onChange={(e) => setTag(e.target.value)} />
          <button className="btn primary">Save tag</button>
        </form>
      ) : (
        <div role="menu">
          <button role="menuitem" className="menu-item" onClick={run(() => openLink(item.url))}><ExternalLink size={20} /> Open link</button>
          {canMarkDone(snap, item) && (
            <button role="menuitem" className="menu-item" onClick={run(() => void toggleDone(item))}>
              {isDone(item) ? <><Circle size={20} /> Mark as not done</> : <><CircleCheck size={20} /> Mark as done</>}
            </button>
          )}
          {!folder.isShared && isNew(item) && (
            <button role="menuitem" className="menu-item" onClick={() => sheets.open(<ConfirmItemSheet item={item} />)}><ListChecks size={20} /> Review suggestion</button>
          )}
          {!folder.isShared && (
            <>
              <button role="menuitem" className="menu-item" onClick={() => setEditingTag(true)}>
                <Tag size={20} /> {item.tag ? `Edit tag "${item.tag}"` : 'Add a tag'}
              </button>
              <button role="menuitem" className="menu-item" onClick={() => sheets.open(<ConfirmItemSheet item={{ ...item, status: 'confirmed' }} />)}>
                <FolderInput size={20} /> Move to another folder
              </button>
            </>
          )}
          {canDelete && (
            <button role="menuitem" className="menu-item danger" onClick={remove}>
              <Trash2 size={20} /> {folder.isShared ? 'Remove pin' : 'Delete link'}
            </button>
          )}
        </div>
      )}
    </div>
  );
}
