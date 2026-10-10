import { ClipboardPaste, Plus, Search, Settings, User } from 'lucide-react';
import { Link, useNavigate } from 'react-router';
import { isDone, isNew, uncategorizedFolder, type Item } from '../../data/models';
import { useApp, useStore } from '../../state/context';
import { folderOf, hasUncategorized, itemsIn, newItems, personalFolders } from '../../state/selectors';
import { deep, FolderCard, NewPill, SourcePill, Thumb } from '../components/bits';
import { useSheets } from '../components/Sheet';
import { useActions } from '../actions';
import { AddFolderSheet } from '../sheets/AddFolderSheet';
import { ConfirmItemSheet } from '../sheets/ConfirmItemSheet';
import { useOpenFolder } from './nav';

export function HomeScreen() {
  const snap = useApp();
  const sheets = useSheets();
  const navigate = useNavigate();
  const openFolder = useOpenFolder();
  const { pasteLink } = useActions();
  const waiting = newItems(snap);
  const folders = [...personalFolders(snap), ...(hasUncategorized(snap) ? [uncategorizedFolder()] : [])];
  const name = snap.session?.displayName;

  return (
    <>
      <header className="row">
        <Link to="/profile" className="avatar" aria-label="Your profile"
          style={{ width: 46, height: 46, border: 0, background: 'linear-gradient(135deg, var(--brand), #2FA88F)', color: '#fff', fontFamily: 'var(--head)', fontSize: 20 }}>
          {name ? name[0].toUpperCase() : <User size={22} />}
        </Link>
        <div className="grow">
          <h1 style={{ fontSize: 24 }}>{name ? `Hi, ${name.split(' ')[0]}` : 'Hi there'}</h1>
          <p className="muted small">
            {waiting.length === 0 ? 'All caught up' : waiting.length === 1 ? '1 save needs a quick look' : `${waiting.length} saves need a quick look`}
          </p>
        </div>
        <Link to="/profile" className="icon-btn" aria-label="Settings"><Settings size={21} /></Link>
      </header>

      <button type="button" className="search-entry" style={{ marginTop: 16 }} onClick={() => navigate('/search')}>
        <Search size={19} aria-hidden /> Search your saves
      </button>
      <p className="desktop-only hint" style={{ marginTop: 10 }}>
        Save from anywhere: press <kbd>{navigator.platform.startsWith('Mac') ? '⌘' : 'Ctrl'}</kbd> + <kbd>V</kbd> with a link copied, or drag a link onto this page.
      </p>

      {waiting.length > 0 && (
        <section className="section" aria-labelledby="quick">
          <div className="section-head">
            <h2 id="quick">Needs a quick look</h2>
            <Link to="/new" className="btn ghost">See all ({waiting.length})</Link>
          </div>
          <div className="quick-row">{waiting.map((i) => <QuickCard key={i.id} item={i} />)}</div>
        </section>
      )}

      <section className="section" aria-labelledby="collections">
        <div className="section-head"><h2 id="collections">Your collections</h2></div>
        <div className="folder-grid">
          {folders.map((f) => {
            const inside = itemsIn(snap, f.id);
            return (
              <FolderCard key={f.id} folder={f} count={inside.length} onOpen={() => openFolder(f.id)}
                newCount={inside.filter(isNew).length} doneCount={inside.filter(isDone).length} />
            );
          })}
          <button type="button" className="folder-card add" onClick={() => sheets.open(<AddFolderSheet />)}>
            <Plus size={26} aria-hidden /> New folder
          </button>
        </div>
      </section>

      <button type="button" className="fab" onClick={() => void pasteLink()}>
        <ClipboardPaste size={19} aria-hidden /> Paste link
      </button>
    </>
  );
}

function QuickCard({ item }: { item: Item }) {
  const snap = useApp();
  const store = useStore();
  const sheets = useSheets();
  const folder = folderOf(snap, item);
  return (
    <article className="quick-card">
      <div style={{ position: 'relative' }}>
        <Thumb item={item} color={folder.color} />
        <span className="on-thumb" style={{ left: 8 }}><NewPill /></span>
        <span className="on-thumb" style={{ right: 8 }}><SourcePill source={item.source} /></span>
      </div>
      <div className="body">
        <p className="title">{item.title}</p>
        <p className="small" style={{ color: deep(folder.color), fontWeight: 700 }}>{folder.emoji} {folder.name}</p>
        <div className="actions">
          <button className="btn primary small" onClick={async () => {
            await store.confirmItem(item);
            store.showToast(`Filed in ${folder.name}`);
          }}>Confirm</button>
          <button className="btn small" onClick={() => sheets.open(<ConfirmItemSheet item={item} />)}>Change</button>
        </div>
      </div>
    </article>
  );
}
