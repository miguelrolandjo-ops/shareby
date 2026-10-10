import { Search, X } from 'lucide-react';
import { useId, useState } from 'react';
import { useApp } from '../../state/context';
import { canMarkDone, doneByLabel, folderOf } from '../../state/selectors';
import { LinkRow } from '../components/LinkViews';
import { useSheets } from '../components/Sheet';
import { useActions } from '../actions';
import { ConfirmItemSheet } from '../sheets/ConfirmItemSheet';
import { ItemActionsSheet } from '../sheets/ItemActionsSheet';

/** Searches titles, links, tags, folders and names in this browser, so it works offline. */
export function SearchScreen() {
  const snap = useApp();
  const sheets = useSheets();
  const { openLink, toggleDone } = useActions();
  const [q, setQ] = useState('');
  const inputId = useId();
  const words = q.toLowerCase().split(/\s+/).filter(Boolean);
  const results = words.length === 0 ? [] : snap.items.filter((item) => {
    const f = folderOf(snap, item);
    const hay = [item.title, item.url, item.tag, f.name, item.addedByName].filter(Boolean).join(' ').toLowerCase();
    return words.every((w) => hay.includes(w));
  });

  return (
    <>
      <h1>Search</h1>
      <div className="input-wrap" style={{ margin: '14px 0 18px' }}>
        <label htmlFor={inputId} className="sr-only">Search your saves</label>
        <Search size={19} aria-hidden style={{ position: 'absolute', left: 14, top: 14, color: 'var(--ink-faint)' }} />
        <input id={inputId} className="input" type="search" autoFocus value={q} onChange={(e) => setQ(e.target.value)}
          placeholder={'Try "sambal", "bali" or a friend\'s name'} style={{ paddingLeft: 42, background: 'var(--surface)' }} />
        {q && <button type="button" className="icon-btn" aria-label="Clear search" onClick={() => setQ('')}><X size={18} /></button>}
      </div>
      <p className="sr-only" role="status">{words.length ? `${results.length} results` : ''}</p>
      {words.length > 0 && results.length === 0 && (
        <p className="empty">Nothing matches "{q.trim()}". Try a shorter word.</p>
      )}
      {results.map((item) => {
        const f = folderOf(snap, item);
        return (
          <LinkRow key={item.id} item={item} color={f.color} shared={f.isShared} label={`${f.emoji} ${f.name}`}
            doneLabel={doneByLabel(item, snap.session?.userId)}
            onOpen={() => (item.status === 'new' ? sheets.open(<ConfirmItemSheet item={item} />) : openLink(item.url))}
            onMenu={() => sheets.open(<ItemActionsSheet item={item} />)}
            onToggleDone={canMarkDone(snap, item) ? () => void toggleDone(item) : undefined} />
        );
      })}
    </>
  );
}
