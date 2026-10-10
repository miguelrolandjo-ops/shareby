import { useId, useState } from 'react';
import { useStore } from '../../state/context';
import { SheetHead, useSheets } from '../components/Sheet';
import { friendlyError } from '../errors';

/**
 * Development stand-in for the Google / Apple account picker: any email works.
 * Production: Google Identity Services gives an ID token -> store.api.googleLogin().
 */
export function SignInSheet({ provider }: { provider: 'google' | 'apple' }) {
  const store = useStore();
  const { close } = useSheets();
  const [email, setEmail] = useState('');
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const ids = { email: useId(), name: useId() };
  const label = provider === 'apple' ? 'Apple' : 'Google';
  const valid = /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim());

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!valid) return;
    setBusy(true);
    setError(null);
    try {
      await store.signIn(provider, email.trim(), name.trim() || email.trim().split('@')[0]);
      close();
      store.showToast('Signed in. Your saves are backing up and sharing is on.');
    } catch (err) {
      setBusy(false);
      setError(friendlyError(err));
    }
  }

  return (
    <form onSubmit={submit}>
      <SheetHead title={`Continue with ${label}`} subtitle={`Development build: enter any email to act as that ${label} account.`} />
      <label className="field" htmlFor={ids.email}>
        <span>Email</span>
        <input id={ids.email} className="input" type="email" autoFocus autoComplete="email" placeholder="you@gmail.com"
          value={email} onChange={(e) => setEmail(e.target.value)} />
      </label>
      <label className="field" htmlFor={ids.name}>
        <span>Your name</span>
        <input id={ids.name} className="input" autoComplete="name" placeholder="Shown to friends on shared boards"
          value={name} onChange={(e) => setName(e.target.value)} />
      </label>
      {error && <p className="error" role="alert" style={{ marginBottom: 10 }}>{error}</p>}
      <button className="btn primary block" disabled={!valid || busy}>{busy ? 'Signing in...' : 'Continue'}</button>
    </form>
  );
}
