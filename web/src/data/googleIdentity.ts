/**
 * Google Identity Services (the "Sign in with Google" button) for the web app.
 * The script is loaded only when someone opens the sign-in sheet, so the app itself never
 * talks to Google. The button hands back an ID token, which the API verifies.
 */
interface CredentialResponse {
  credential?: string;
}
interface GoogleId {
  initialize(options: {
    client_id: string;
    callback: (r: CredentialResponse) => void;
    ux_mode?: 'popup' | 'redirect';
    auto_select?: boolean;
    cancel_on_tap_outside?: boolean;
    use_fedcm_for_button?: boolean;
  }): void;
  renderButton(parent: HTMLElement, options: Record<string, unknown>): void;
  disableAutoSelect(): void;
}
declare global {
  interface Window {
    google?: { accounts: { id: GoogleId } };
  }
}

const SRC = 'https://accounts.google.com/gsi/client';
let loading: Promise<GoogleId> | null = null;

export function loadGoogleIdentity(): Promise<GoogleId> {
  if (window.google?.accounts?.id) return Promise.resolve(window.google.accounts.id);
  loading ??= new Promise<GoogleId>((resolve, reject) => {
    const s = document.createElement('script');
    s.src = SRC;
    s.async = true;
    s.onload = () => (window.google?.accounts?.id ? resolve(window.google.accounts.id) : reject(new Error('Google sign-in did not load')));
    s.onerror = () => {
      loading = null;
      s.remove();
      reject(new Error("Couldn't reach Google. Check your connection and try again."));
    };
    document.head.appendChild(s);
  });
  return loading;
}

/** Renders Google's button into `el`; `onToken` receives the ID token after the user picks an account. */
export async function renderGoogleButton(el: HTMLElement, clientId: string, onToken: (idToken: string) => void): Promise<void> {
  const gis = await loadGoogleIdentity();
  gis.initialize({
    client_id: clientId,
    callback: (r) => { if (r.credential) onToken(r.credential); },
    ux_mode: 'popup',
    auto_select: false,
    cancel_on_tap_outside: true,
    use_fedcm_for_button: true,
  });
  el.replaceChildren();
  gis.renderButton(el, {
    type: 'standard', theme: 'outline', size: 'large', shape: 'pill', text: 'continue_with',
    logo_alignment: 'left', width: Math.min(360, Math.max(220, el.clientWidth || 320)),
  });
}

/** After signing out, don't silently pick the same account next time. */
export function forgetGoogleAccount(): void {
  window.google?.accounts?.id?.disableAutoSelect();
}
