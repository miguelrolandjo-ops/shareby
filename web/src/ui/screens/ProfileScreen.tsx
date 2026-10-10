import { ArrowLeft, LogOut, RefreshCw } from 'lucide-react';
import { useState } from 'react';
import { useNavigate } from 'react-router';
import { useApp, useStore } from '../../state/context';
import { personalFolders, plural, sharedFolders } from '../../state/selectors';
import { Avatar, SyncLine } from '../components/bits';
import { SignInButtons } from './FriendsScreen';

const ago = (t: number) => {
  const s = Math.round((Date.now() - t) / 1000);
  return s < 60 ? 'just now' : s < 3600 ? `${Math.round(s / 60)} min ago` : `${Math.round(s / 3600)} h ago`;
};

export function ProfileScreen() {
  const snap = useApp();
  const store = useStore();
  const navigate = useNavigate();
  const [confirmOut, setConfirmOut] = useState(false);
  const user = snap.session;
  const boards = sharedFolders(snap).length;

  return (
    <div style={{ maxWidth: 560 }}>
      <div className="row" style={{ marginBottom: 18 }}>
        <button className="icon-btn" aria-label="Back" onClick={() => navigate('/')}><ArrowLeft size={20} /></button>
        <h1 style={{ fontSize: 22 }}>Profile</h1>
      </div>
      <div className="row" style={{ marginBottom: 20 }}>
        <Avatar name={user?.displayName ?? '?'} seed={user?.userId} size={64} />
        <div>
          <h2>{user?.displayName ?? 'Not signed in'}</h2>
          <p className="muted">{user ? `${user.email}, ${user.provider === 'apple' ? 'Apple' : 'Google'} account` : 'Everything is saved in this browser'}</p>
        </div>
      </div>

      <div className="card" style={{ display: 'grid', gap: 10 }}>
        <h3>Storage</h3>
        <p className="muted">
          {plural(snap.items.length, 'link')} in {plural(personalFolders(snap).length, 'folder')}
          {boards ? ` and ${plural(boards, 'shared board')}` : ''}
        </p>
        <SyncLine snap={snap} />
        {snap.lastSyncedAt && <p className="faint small">Last synced {ago(snap.lastSyncedAt)}</p>}
        {user && (
          <button className="btn" disabled={snap.syncState === 'syncing'} onClick={() => void store.syncNow()}>
            <RefreshCw size={18} aria-hidden /> Sync now
          </button>
        )}
      </div>

      <div style={{ marginTop: 18 }}>
        {!user ? (
          <>
            <p className="muted" style={{ marginBottom: 12 }}>
              Sign in to back up your saves and share boards with friends. You can keep using Shareby without an account.
            </p>
            <SignInButtons />
          </>
        ) : confirmOut ? (
          <div className="card">
            <p style={{ marginBottom: 12 }}>
              {snap.pendingChanges > 0 && `${plural(snap.pendingChanges, 'change')} haven't synced yet and will stay in this browser only. `}
              Your personal saves stay in this browser. Shared boards are removed from it until you sign in again.
            </p>
            <div className="row">
              <button className="btn" onClick={() => setConfirmOut(false)}>Cancel</button>
              <button className="btn" style={{ color: 'var(--danger)' }} onClick={() => { void store.signOut(); setConfirmOut(false); }}>Sign out</button>
            </div>
          </div>
        ) : (
          <button className="btn danger" onClick={() => setConfirmOut(true)}><LogOut size={18} aria-hidden /> Sign out</button>
        )}
      </div>
    </div>
  );
}
