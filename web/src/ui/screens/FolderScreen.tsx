import { ArrowLeft, LayoutGrid, List, Pencil, Plus, UserPlus } from 'lucide-react';
import { useState } from 'react';
import { useLocation, useNavigate, useParams } from 'react-router';
import { canAddLinks, css, isDone, type Folder, type Item } from '../../data/models';
import { useApp } from '../../state/context';
import { canMarkDone, doneByLabel, folderById, itemsIn, membersOf } from '../../state/selectors';
import { AvatarStack } from '../components/bits';
import { LinkCard, LinkRow } from '../components/LinkViews';
import { useSheets } from '../components/Sheet';
import { useActions } from '../actions';
import { AddFolderSheet } from '../sheets/AddFolderSheet';
import { AddLinkSheet } from '../sheets/AddLinkSheet';
import { ConfirmItemSheet } from '../sheets/ConfirmItemSheet';
import { InviteSheet } from '../sheets/InviteSheet';
import { ItemActionsSheet } from '../sheets/ItemActionsSheet';

/** One folder or shared board. Back returns to the list you opened it from. */
export function FolderScreen() {
  const { id = '' } = useParams();
  const snap = useApp();
  const navigate = useNavigate();
  const location = useLocation();
  const sheets = useSheets();
  const { openLink, toggleDone } = useActions();
  const [grid, setGrid] = useState(false);
  const [filter, setFilter] = useState<string | null>(null);
  const [doneHidden, setDoneHidden] = useState(false);
  const folder = folderById(snap, id);
  const from = (location.state as { from?: string } | null)?.from;

  if (!folder) {
    return (
      <div className="empty">
        <h3>This folder isn't here</h3>
        <p>It was deleted, or it's no longer shared with you.</p>
        <button className="btn" style={{ marginTop: 16 }} onClick={() => navigate('/')}>Go to Home</button>
      </div>
    );
  }

  const back = () => navigate(from && !from.startsWith('/folders') ? from : folder.isShared ? '/friends' : '/');
  const all = itemsIn(snap, folder.id);
  const members = folder.isShared ? membersOf(snap, folder.id) : [];
  const filters = folder.isShared ? members.map((m) => m.displayName) : [...new Set(all.map((i) => i.tag).filter((t): t is string => !!t))].sort();
  const active = filter && filters.includes(filter) ? filter : null;
  const visible = active ? all.filter((i) => (folder.isShared ? i.addedByName === active : i.tag === active)) : all;
  const todo = visible.filter((i) => !isDone(i));
  const done = visible.filter(isDone).sort((a, b) => (b.completedAt ?? '').localeCompare(a.completedAt ?? ''));
  const doneCount = all.filter(isDone).length;

  const open = (item: Item) => (item.status === 'new' ? sheets.open(<ConfirmItemSheet item={item} />) : openLink(item.url));
  const render = (items: Item[]) => {
    const View = grid ? LinkCard : LinkRow;
    const els = items.map((item) => (
      <View key={item.id} item={item} color={folder.color} shared={folder.isShared}
        doneLabel={doneByLabel(item, snap.session?.userId)}
        onOpen={() => open(item)}
        onMenu={() => sheets.open(<ItemActionsSheet item={item} />)}
        onToggleDone={canMarkDone(snap, item) ? () => void toggleDone(item) : undefined} />
    ));
    return grid ? <div className="link-grid">{els}</div> : <div>{els}</div>;
  };

  return (
    <>
      <Hero folder={folder} count={all.length} doneCount={doneCount} members={members} me={snap.session?.userId} onBack={back}
        onInvite={() => sheets.open(<InviteSheet board={folder} />)}
        onEdit={() => sheets.open(<AddFolderSheet editing={folder} />)} />

      <div className="toolbar">
        <div className="chips" role="group" aria-label={folder.isShared ? 'Filter by who added' : 'Filter by tag'}>
          <button type="button" className="chip" aria-pressed={!active} onClick={() => setFilter(null)}>All</button>
          {filters.map((f) => (
            <button key={f} type="button" className="chip" aria-pressed={active === f} onClick={() => setFilter(f)}>{f}</button>
          ))}
        </div>
        <div className="seg" role="group" aria-label="Layout">
          <button type="button" aria-pressed={!grid} aria-label="List" onClick={() => setGrid(false)}><List size={18} /></button>
          <button type="button" aria-pressed={grid} aria-label="Grid" onClick={() => setGrid(true)}><LayoutGrid size={18} /></button>
        </div>
      </div>

      {visible.length === 0 ? (
        <div className="empty">
          <h3>Nothing here yet</h3>
          <p>{canAddLinks(folder) ? `Share a link from Instagram, YouTube or TikTok, or use ${folder.isShared ? 'Add pin' : 'Add link'}.` : 'Links your friends pin will show up here.'}</p>
        </div>
      ) : (
        <>
          {render(todo)}
          {done.length > 0 && (
            <>
              <div className="done-head">
                <h3>Done</h3><span className="faint" style={{ fontWeight: 700 }}>{done.length}</span>
                <span className="grow" />
                <button type="button" className="btn ghost" aria-expanded={!doneHidden} onClick={() => setDoneHidden(!doneHidden)}>
                  {doneHidden ? 'Show' : 'Hide'}
                </button>
              </div>
              {!doneHidden && render(done)}
            </>
          )}
        </>
      )}

      {canAddLinks(folder) && (
        <button type="button" className="fab" onClick={() => sheets.open(<AddLinkSheet folderId={folder.id} />)}>
          <Plus size={19} aria-hidden /> {folder.isShared ? 'Add pin' : 'Add link'}
        </button>
      )}
    </>
  );
}

function Hero({ folder, count, doneCount, members, me, onBack, onInvite, onEdit }: {
  folder: Folder; count: number; doneCount: number; members: ReturnType<typeof membersOf>; me?: string;
  onBack: () => void; onInvite: () => void; onEdit: () => void;
}) {
  const c = css(folder.color);
  const counts = `${count === 1 ? `1 ${folder.isShared ? 'pin' : 'link'}` : `${count} ${folder.isShared ? 'pins' : 'links'}`}${doneCount ? `, ${doneCount} done` : ''}`;
  const others = members.filter((m) => m.userId !== me).map((m) => m.displayName);
  const withWhom = !folder.isShared ? '' : others.length === 0 ? ', only you so far'
    : `, shared with ${others.length <= 2 ? others.join(' & ') : `${others.slice(0, -1).join(', ')} & ${others[others.length - 1]}`}`;
  return (
    <div className="hero" style={{ background: `linear-gradient(135deg, ${c}, color-mix(in srgb, ${c} 55%, #16302B))` }}>
      <div className="row">
        <button type="button" className="icon-btn" onClick={onBack} aria-label="Back to list"><ArrowLeft size={20} /></button>
        <span className="grow" />
        {folder.isShared && folder.myRole === 'owner' && (
          <button type="button" className="icon-btn" onClick={onInvite} aria-label="Invite friends"><UserPlus size={19} /></button>
        )}
        {folder.myRole === 'owner' && folder.id !== '__uncategorized__' && (
          <button type="button" className="icon-btn" onClick={onEdit} aria-label="Edit"><Pencil size={18} /></button>
        )}
      </div>
      <h1><span aria-hidden>{folder.emoji}</span>{folder.name}</h1>
      <div className="sub">
        {folder.isShared && members.length > 0 && <AvatarStack members={members} size={26} />}
        <span>{counts}{withWhom}</span>
      </div>
      {folder.isShared && !canAddLinks(folder) && <p className="small" style={{ marginTop: 8, opacity: 0.85 }}>You can view this board</p>}
    </div>
  );
}
