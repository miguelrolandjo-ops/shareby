import { Bell, House, Search, Users } from 'lucide-react';
import { useEffect, useState, type ReactNode } from 'react';
import { BrowserRouter, Link, Route, Routes, useLocation } from 'react-router';
import { css, isDone } from '../data/models';
import { extractUrl, titleFromShareText } from '../data/urlUtils';
import { useApp } from '../state/context';
import { folderById, itemsIn, newItems, personalFolders, sharedFolders } from '../state/selectors';
import { SyncLine } from './components/bits';
import { SheetHost, useSheets } from './components/Sheet';
import { Toaster } from './components/Toaster';
import { FolderScreen } from './screens/FolderScreen';
import { FriendsScreen } from './screens/FriendsScreen';
import { HomeScreen } from './screens/HomeScreen';
import { InboxScreen } from './screens/InboxScreen';
import { useOpenFolder } from './screens/nav';
import { ProfileScreen } from './screens/ProfileScreen';
import { SearchScreen } from './screens/SearchScreen';
import { ShareScreen } from './screens/ShareScreen';
import { AddLinkSheet } from './sheets/AddLinkSheet';

type Tab = 'home' | 'search' | 'new' | 'friends';
const TABS: { id: Tab; path: string; label: string; Icon: typeof House }[] = [
  { id: 'home', path: '/', label: 'Home', Icon: House },
  { id: 'search', path: '/search', label: 'Search', Icon: Search },
  { id: 'new', path: '/new', label: 'New', Icon: Bell },
  { id: 'friends', path: '/friends', label: 'Friends', Icon: Users },
];

export function App() {
  return (
    <BrowserRouter>
      <SheetHost>
        <Shell>
          <Routes>
            <Route path="/" element={<HomeScreen />} />
            <Route path="/search" element={<SearchScreen />} />
            <Route path="/new" element={<InboxScreen />} />
            <Route path="/friends" element={<FriendsScreen />} />
            <Route path="/profile" element={<ProfileScreen />} />
            <Route path="/folders/:id" element={<FolderScreen />} />
            <Route path="/share" element={<ShareScreen />} />
            <Route path="*" element={<HomeScreen />} />
          </Routes>
        </Shell>
        <Toaster />
      </SheetHost>
    </BrowserRouter>
  );
}

/** Which tab is "current" — inside a folder, the list you opened it from stays highlighted. */
function useActiveTab(): Tab | null {
  const location = useLocation();
  const snap = useApp();
  const p = location.pathname;
  const direct = TABS.find((t) => t.path === p);
  if (direct) return direct.id;
  if (p.startsWith('/folders/')) {
    const from = (location.state as { from?: string } | null)?.from;
    const fromTab = TABS.find((t) => t.path === from);
    if (fromTab) return fromTab.id;
    return folderById(snap, p.split('/')[2])?.isShared ? 'friends' : 'home';
  }
  return p === '/profile' ? 'home' : null;
}

function Shell({ children }: { children: ReactNode }) {
  const snap = useApp();
  const active = useActiveTab();
  const waiting = newItems(snap).length;
  const location = useLocation();
  useLinkDrops();

  useEffect(() => window.scrollTo(0, 0), [location.pathname]);

  const tabLink = (t: (typeof TABS)[number], className: string, withCount: boolean) => (
    <Link key={t.id} to={t.path} className={`${className}${active === t.id ? ' active' : ''}`}
      aria-current={active === t.id ? 'page' : undefined}>
      <span className="tab-icon"><t.Icon aria-hidden />{!withCount && t.id === 'new' && waiting > 0 && <span className="badge">{waiting}</span>}</span>
      <span>{t.label}</span>
      {withCount && t.id === 'new' && waiting > 0 && <span className="badge" aria-label={`${waiting} waiting`}>{waiting}</span>}
    </Link>
  );

  if (!snap.ready) return null;
  return (
    <div className="shell">
      <aside className="rail" aria-label="Shareby">
        <Link to="/" className="brand"><img src="/favicon.svg" alt="" /><span>Shareby</span></Link>
        <nav className="rail-nav" aria-label="Main">{TABS.map((t) => tabLink(t, 'rail-link', true))}</nav>
        <RailFolders title="Your folders" folders={personalFolders(snap)} />
        {snap.session && <RailFolders title="Shared boards" folders={sharedFolders(snap)} />}
        <div className="rail-foot"><Link to="/profile" className="rail-link" style={{ display: 'block' }}><SyncLine snap={snap} /></Link></div>
      </aside>
      <main className="main">{children}</main>
      <nav className="bottom-nav" aria-label="Main">{TABS.map((t) => tabLink(t, 'tab', false))}</nav>
    </div>
  );
}

function RailFolders({ title, folders }: { title: string; folders: ReturnType<typeof personalFolders> }) {
  const snap = useApp();
  const openFolder = useOpenFolder();
  const location = useLocation();
  if (!folders.length) return null;
  return (
    <div className="rail-group">
      <h4>{title}</h4>
      {folders.map((f) => {
        const inside = itemsIn(snap, f.id);
        const left = inside.length - inside.filter(isDone).length;
        const here = location.pathname === `/folders/${f.id}`;
        return (
          <a key={f.id} href={`/folders/${f.id}`} className={`rail-link${here ? ' active' : ''}`} aria-current={here ? 'page' : undefined}
            onClick={(e) => { e.preventDefault(); openFolder(f.id); }}>
            <span className="dot" style={{ background: css(f.color) }} aria-hidden />
            <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{f.name}</span>
            <span className="count" aria-label={`${left} to do`}>{left}</span>
          </a>
        );
      })}
    </div>
  );
}

/** Desktop shortcuts: Ctrl/Cmd+V anywhere, or drag a link onto the page, opens the save sheet. */
function useLinkDrops() {
  const sheets = useSheets();
  const [dragging, setDragging] = useState(false);

  useEffect(() => {
    const open = (text: string) => {
      const url = extractUrl(text);
      if (url) sheets.open(<AddLinkSheet initialUrl={url} initialTitle={titleFromShareText(text, url)} />);
      return !!url;
    };
    const busy = (t: EventTarget | null) =>
      !!document.querySelector('dialog[open]') ||
      (t instanceof HTMLElement && (t.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT'].includes(t.tagName)));

    const onPaste = (e: ClipboardEvent) => {
      if (busy(e.target)) return;
      if (open(e.clipboardData?.getData('text/plain') ?? '')) e.preventDefault();
    };
    const hasLink = (e: DragEvent) => !!e.dataTransfer && [...e.dataTransfer.types].some((t) => t === 'text/uri-list' || t === 'text/plain');
    const onOver = (e: DragEvent) => {
      if (!hasLink(e) || busy(null)) return;
      e.preventDefault();
      setDragging(true);
    };
    const onLeave = (e: DragEvent) => { if (!e.relatedTarget) setDragging(false); };
    const onDrop = (e: DragEvent) => {
      setDragging(false);
      if (!hasLink(e) || busy(null)) return;
      e.preventDefault();
      open(e.dataTransfer!.getData('text/uri-list') || e.dataTransfer!.getData('text/plain'));
    };
    document.addEventListener('paste', onPaste);
    window.addEventListener('dragover', onOver);
    window.addEventListener('dragleave', onLeave);
    window.addEventListener('drop', onDrop);
    return () => {
      document.removeEventListener('paste', onPaste);
      window.removeEventListener('dragover', onOver);
      window.removeEventListener('dragleave', onLeave);
      window.removeEventListener('drop', onDrop);
    };
  }, [sheets]);

  useEffect(() => {
    const el = document.getElementById('drop-overlay');
    if (dragging && !el) {
      const div = document.createElement('div');
      div.id = 'drop-overlay';
      div.className = 'drop-overlay';
      div.textContent = 'Drop the link to save it';
      document.body.appendChild(div);
    } else if (!dragging && el) el.remove();
  }, [dragging]);
}
