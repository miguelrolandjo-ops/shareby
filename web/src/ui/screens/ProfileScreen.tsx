import { ArrowLeft, LogOut, RefreshCw, Trash2 } from 'lucide-react';
import { forgetGoogleAccount } from '../../data/googleIdentity';
import { friendlyError } from '../errors';
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
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);
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
              <button className="btn" style={{ color: 'var(--danger)' }} onClick={() => { forgetGoogleAccount(); void store.signOut(); setConfirmOut(false); }}>Sign out</button>
            </div>
          </div>
        ) : confirmDelete ? (
          <div className="card">
            <p style={{ marginBottom: 12 }}>
              Delete your Shareby account? Your backup, the boards you own and the pins you added to friends' boards
              are deleted from the server for good. Personal saves already in this browser stay here.
            </p>
            {deleteError && <p className="error" role="alert" style={{ marginBottom: 10 }}>{deleteError}</p>}
            <div className="row">
              <button className="btn" onClick={() => { setConfirmDelete(false); setDeleteError(null); }}>Cancel</button>
              <button className="btn" style={{ color: 'var(--danger)' }}
                onClick={() => {
                  setDeleteError(null);
                  store.deleteAccount()
                    .then(() => { forgetGoogleAccount(); setConfirmDelete(false); store.showToast('Your account was deleted.'); })
                    .catch((e) => setDeleteError(friendlyError(e)));
                }}>Delete account</button>
            </div>
          </div>
        ) : (
          <div style={{ display: 'grid', gap: 6, justifyItems: 'start' }}>
            <button className="btn danger" onClick={() => setConfirmOut(true)}><LogOut size={18} aria-hidden /> Sign out</button>
            <button className="btn danger small" onClick={() => setConfirmDelete(true)}><Trash2 size={16} aria-hidden /> Delete account</button>
          </div>
        )}
      </div>
    </div>
  );
}
