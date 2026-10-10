import { Apple, Lock, Plus, Users } from 'lucide-react';
import { isDone, type Folder } from '../../data/models';
import { useApp } from '../../state/context';
import { itemsIn, membersOf, sharedFolders } from '../../state/selectors';
import { AvatarStack, Note, soft, SyncLine } from '../components/bits';
import { useSheets } from '../components/Sheet';
import { AddFolderSheet } from '../sheets/AddFolderSheet';
import { InviteSheet } from '../sheets/InviteSheet';
import { SignInSheet } from '../sheets/SignInSheet';
import { useOpenFolder } from './nav';

export function SignInButtons() {
  const sheets = useSheets();
  return (
    <div style={{ display: 'grid', gap: 10 }}>
      <button className="btn block" onClick={() => sheets.open(<SignInSheet provider="google" />)}>
        <span aria-hidden style={{ color: '#4285F4', fontWeight: 800, fontSize: 18 }}>G</span> Continue with Google
      </button>
      <button className="btn dark block" onClick={() => sheets.open(<SignInSheet provider="apple" />)}>
        <Apple size={19} aria-hidden /> Continue with Apple
      </button>
    </div>
  );
}

export function FriendsScreen() {
  const snap = useApp();
  return snap.session ? <Boards /> : <Locked />;
}

function Locked() {
  return (
    <div style={{ maxWidth: 440, paddingTop: 24 }}>
      <div style={{ width: 76, height: 76, borderRadius: 24, background: '#EAE1F8', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <Users size={38} color="#9A7FD1" aria-hidden />
      </div>
      <h1 style={{ marginTop: 20 }}>Build boards with friends</h1>
      <p className="muted" style={{ margin: '10px 0 26px', fontSize: 16 }}>
        Sign in to plan trips, gift lists and weekend ideas together. Signing in also backs up everything saved in this browser.
      </p>
      <SignInButtons />
      <div style={{ marginTop: 20 }}>
        <Note icon={<Lock size={17} aria-hidden />}>Your personal folders stay private. Only boards you create here are shared.</Note>
      </div>
    </div>
  );
}

function Boards() {
  const snap = useApp();
  const sheets = useSheets();
  const boards = sharedFolders(snap);
  const newBoard = () => sheets.open(<AddFolderSheet shared onCreated={(b) => sheets.open(<InviteSheet board={b} />)} />);
  return (
    <>
      <h1>Friends</h1>
      <div style={{ margin: '8px 0 24px' }}><SyncLine snap={snap} /></div>
      <div className="section-head">
        <h2>Shared boards</h2>
        <button className="btn ghost" onClick={newBoard}><Plus size={18} /> New board</button>
      </div>
      {boards.length === 0 ? (
        <div className="card empty">
          <h3>No shared boards yet</h3>
          <p style={{ marginBottom: 16 }}>Create one and invite friends by email.</p>
          <button className="btn primary" onClick={newBoard}>Create a board</button>
        </div>
      ) : (
        <div className="folder-grid" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))' }}>
          {boards.map((b) => <BoardCard key={b.id} board={b} />)}
        </div>
      )}
      <div style={{ marginTop: 18 }}>
        <Note>Tags and auto-sorting are for your personal folders. Everything on a shared board is placed by whoever pins it.</Note>
      </div>
    </>
  );
}

function BoardCard({ board }: { board: Folder }) {
  const snap = useApp();
  const openFolder = useOpenFolder();
  const inside = itemsIn(snap, board.id);
  const done = inside.filter(isDone).length;
  const role = board.myRole === 'owner' ? 'Owner' : board.myRole === 'viewer' ? 'Can view' : 'Can add';
  return (
    <a href={`/folders/${board.id}`} className="card row" style={{ cursor: 'pointer' }}
      onClick={(e) => { e.preventDefault(); openFolder(board.id); }}>
      <span aria-hidden style={{ width: 52, height: 52, borderRadius: 14, background: soft(board.color), display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 24, flex: 'none' }}>{board.emoji}</span>
      <span className="grow">
        <h3>{board.name}</h3>
        <span className="muted small">{inside.length === 1 ? '1 pin' : `${inside.length} pins`}{done ? `, ${done} done` : ''}. {role}</span>
      </span>
      <AvatarStack members={membersOf(snap, board.id)} />
    </a>
  );
}
