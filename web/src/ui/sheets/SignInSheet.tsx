import { useEffect, useId, useRef, useState } from 'react';
import { renderGoogleButton } from '../../data/googleIdentity';
import type { AuthConfig } from '../../state/store';
import { useStore } from '../../state/context';
import { SheetHead, useSheets } from '../components/Sheet';
import { friendlyError } from '../errors';

/**
 * Sign-in. Production: Google's own button (Google Identity Services) gives an ID token that the
 * API verifies. When the server runs with ALLOW_DEV_AUTH=true, a "development" email form is
 * offered as well, so two browsers can play two friends without Google accounts.
 */
export function SignInSheet() {
  const store = useStore();
  const { close } = useSheets();
  const [cfg, setCfg] = useState<AuthConfig | null | 'loading'>('loading');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const googleEl = useRef<HTMLDivElement>(null);

  async function done(run: () => Promise<void>) {
    setBusy(true);
    setError(null);
    try {
      await run();
      close();
      store.showToast('Signed in. Your saves are backing up and sharing is on.');
    } catch (err) {
      setBusy(false);
      setError(friendlyError(err));
    }
  }

  useEffect(() => {
    let live = true;
    void store.authConfig().then((c) => live && setCfg(c));
    return () => { live = false; };
  }, [store]);

  const clientId = cfg && cfg !== 'loading' ? cfg.googleClientId : null;
  useEffect(() => {
    if (!clientId || !googleEl.current) return;
    renderGoogleButton(googleEl.current, clientId, (token) => void done(() => store.signInWithGoogle(token)))
      .catch((e) => setError(friendlyError(e)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clientId]);

  return (
    <div>
      <SheetHead title="Sign in to Shareby" subtitle="Back up your saves and share boards with friends." />
      {cfg === 'loading' && <p className="muted">Checking sign-in options...</p>}
      {cfg === null && (
        <p className="error" role="alert">Can't reach Shareby right now. Check your connection and try again.</p>
      )}
      {cfg && cfg !== 'loading' && (
        <>
          {cfg.googleClientId && (
            <div style={{ display: 'grid', justifyItems: 'center', gap: 8, marginBottom: 14, opacity: busy ? 0.5 : 1 }}>
              <div ref={googleEl} style={{ minHeight: 44, width: '100%', display: 'flex', justifyContent: 'center' }} />
              {busy && <p className="muted small">Signing in...</p>}
            </div>
          )}
          {!cfg.googleClientId && !cfg.dev && (
            <p className="muted">Sign-in isn't set up on this server yet.</p>
          )}
          {cfg.dev && <DevSignIn busy={busy} onSubmit={(email, name) => done(() => store.signInDev('google', email, name))} />}
        </>
      )}
      {error && <p className="error" role="alert" style={{ marginTop: 10 }}>{error}</p>}
      <p className="faint small" style={{ marginTop: 14 }}>
        Personal folders stay private. Only boards you create under Friends are shared.
      </p>
    </div>
  );
}

function DevSignIn({ busy, onSubmit }: { busy: boolean; onSubmit: (email: string, name: string) => void }) {
  const [email, setEmail] = useState('');
  const [name, setName] = useState('');
  const ids = { email: useId(), name: useId() };
  const valid = /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim());
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        if (valid) onSubmit(email.trim(), name.trim() || email.trim().split('@')[0]);
      }}
      style={{ borderTop: '1px solid var(--line, #e3e8e5)', paddingTop: 14 }}
    >
      <p className="muted small" style={{ marginBottom: 10 }}>Development server: enter any email to act as that account.</p>
      <label className="field" htmlFor={ids.email}>
        <span>Email</span>
        <input id={ids.email} className="input" type="email" autoComplete="email" placeholder="you@gmail.com"
          value={email} onChange={(e) => setEmail(e.target.value)} />
      </label>
      <label className="field" htmlFor={ids.name}>
        <span>Your name</span>
        <input id={ids.name} className="input" autoComplete="name" placeholder="Shown to friends on shared boards"
          value={name} onChange={(e) => setName(e.target.value)} />
      </label>
      <button className="btn block" disabled={!valid || busy}>{busy ? 'Signing in...' : 'Continue'}</button>
    </form>
  );
}
