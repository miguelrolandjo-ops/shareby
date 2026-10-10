import { Eye, Pencil } from 'lucide-react';
import { useId, useState } from 'react';
import type { Folder } from '../../data/models';
import { useApp, useStore } from '../../state/context';
import { membersOf } from '../../state/selectors';
import { Avatar } from '../components/bits';
import { SheetHead, useSheets } from '../components/Sheet';
import { friendlyError } from '../errors';

export function InviteSheet({ board }: { board: Folder }) {
  const snap = useApp();
  const store = useStore();
  const { close } = useSheets();
  const [email, setEmail] = useState('');
  const [role, setRole] = useState<'editor' | 'viewer'>('editor');
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const emailId = useId();
  const members = membersOf(snap, board.id);

  async function send(e: React.FormEvent) {
    e.preventDefault();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim())) return setError('Enter an email address like name@gmail.com');
    setSending(true);
    setError(null);
    try {
      const status = await store.invite(board, email, role);
      close();
      store.showToast(status === 'added' ? `${email.trim()} can now see ${board.name}` : `Invite saved. ${email.trim()} gets access when they sign in`);
    } catch (err) {
      setSending(false);
      setError(friendlyError(err));
    }
  }

  const roleRow = (value: 'editor' | 'viewer', Icon: typeof Eye, title: string, sub: string) => (
    <button type="button" role="radio" aria-checked={role === value} className="choice" onClick={() => setRole(value)}>
      <Icon size={20} color="var(--brand)" aria-hidden />
      <span className="grow"><strong>{title}</strong><span className="hint" style={{ display: 'block' }}>{sub}</span></span>
    </button>
  );

  return (
    <form onSubmit={send} noValidate>
      <SheetHead title={`Invite to ${board.name}`} subtitle="They sign in with the Google or Apple account that uses this email." />
      <label className="field" htmlFor={emailId}>
        <span>Email</span>
        <input id={emailId} className="input" type="email" autoFocus placeholder="friend@gmail.com" value={email} onChange={(e) => setEmail(e.target.value)} />
      </label>
      <div role="radiogroup" aria-label="What they can do" style={{ marginBottom: 6 }}>
        {roleRow('editor', Pencil, 'Can add pins', 'Saves links here, ticks them done, removes their own')}
        {roleRow('viewer', Eye, 'Can view', 'Sees everything, changes nothing')}
      </div>
      {error && <p className="error" role="alert" style={{ marginBottom: 10 }}>{error}</p>}
      <button className="btn primary block" disabled={sending}>{sending ? 'Sending...' : 'Send invite'}</button>
      {members.length > 0 && (
        <div style={{ marginTop: 20 }}>
          <p className="small" style={{ fontWeight: 700, marginBottom: 8 }}>On this board</p>
          {members.map((m) => (
            <div key={m.userId} className="row" style={{ padding: '6px 0' }}>
              <Avatar name={m.displayName} seed={m.userId} size={34} />
              <span className="grow" style={{ fontWeight: 600 }}>{m.displayName}</span>
              <span className="hint">{m.role === 'owner' ? 'Owner' : m.role === 'viewer' ? 'Can view' : 'Can add'}</span>
            </div>
          ))}
        </div>
      )}
    </form>
  );
}
