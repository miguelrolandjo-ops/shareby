import { ClipboardPaste, FolderOpen, Sparkles } from 'lucide-react';
import { useId, useState } from 'react';
import { canAddLinks, css, uncategorizedFolder, type Folder } from '../../data/models';
import { extractUrl, titleFromShareText } from '../../data/urlUtils';
import { useApp, useStore } from '../../state/context';
import { folderById, personalFolders, sharedFolders } from '../../state/selectors';
import { soft } from '../components/bits';
import { SheetHead, useSheets } from '../components/Sheet';
import { friendlyError } from '../errors';

/** Save a link: "sort it for me" (auto-suggest) or pick a collection now. */
export function AddLinkSheet({ initialUrl = '', initialTitle = '', folderId, fromShare = false }: {
  initialUrl?: string; initialTitle?: string; folderId?: string; fromShare?: boolean;
}) {
  const snap = useApp();
  const store = useStore();
  const { close } = useSheets();
  const [url, setUrl] = useState(initialUrl);
  const [title, setTitle] = useState(initialTitle);
  const [sortLater, setSortLater] = useState(folderId === undefined && !fromShare);
  const [selected, setSelected] = useState<string | undefined>(folderId);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const ids = { url: useId(), title: useId() };

  const personal = personalFolders(snap);
  const boards = sharedFolders(snap).filter(canAddLinks);

  async function paste() {
    try {
      const text = await navigator.clipboard.readText();
      const found = extractUrl(text);
      if (!found) return setError('Your clipboard has no link');
      setUrl(found);
      setError(null);
      if (!title.trim()) setTitle(titleFromShareText(text, found));
    } catch {
      setError('Paste with Ctrl+V (or long-press) into the link field');
    }
  }

  async function save(e: React.FormEvent) {
    e.preventDefault();
    const clean = extractUrl(url);
    if (!clean) return setError('Enter a link that starts with http:// or https://');
    if (!sortLater && !selected) return setError('Pick a collection, or choose "Sort it for me"');
    setSaving(true);
    try {
      const item = await store.addLink({ url: clean, title, folderId: sortLater ? undefined : selected });
      const where = item.folderId ? folderById(store.getSnapshot(), item.folderId)?.name ?? 'your collection' : 'Uncategorized';
      close();
      store.showToast(sortLater ? `Saved. Suggested: ${where}. Confirm it on Home` : `Saved to ${where}`);
    } catch (err) {
      setSaving(false);
      setError(friendlyError(err));
    }
  }

  const choice = (f: Folder, sub?: string) => (
    <button key={f.id} type="button" role="radio" aria-checked={selected === f.id} className="choice"
      onClick={() => { setSelected(f.id); setError(null); }}>
      <span className="emoji-badge" style={{ background: soft(f.color) }} aria-hidden>{f.emoji}</span>
      <span className="grow"><strong>{f.name}</strong>{sub && <span className="hint" style={{ display: 'block' }}>{sub}</span>}</span>
      <span className="dot" style={{ background: css(f.color) }} aria-hidden />
    </button>
  );

  return (
    <form onSubmit={save} noValidate>
      <SheetHead title={fromShare ? 'Save to Shareby' : 'Save a link'} subtitle={fromShare ? 'Shared from another app' : undefined} />
      <label className="field" htmlFor={ids.url}>
        <span>Link</span>
        <div className="input-wrap">
          <input id={ids.url} className="input" type="url" inputMode="url" placeholder="https://..." value={url}
            autoFocus={!initialUrl} onChange={(e) => { setUrl(e.target.value); setError(null); }} />
          <button type="button" className="icon-btn" onClick={paste} aria-label="Paste from clipboard"><ClipboardPaste size={19} /></button>
        </div>
      </label>
      <label className="field" htmlFor={ids.title}>
        <span>Title</span>
        <input id={ids.title} className="input" placeholder="What is this? (optional)" value={title} onChange={(e) => setTitle(e.target.value)} />
      </label>

      <div className="seg wide" role="group" aria-label="Where it goes" style={{ marginBottom: 12 }}>
        <button type="button" aria-pressed={sortLater} onClick={() => setSortLater(true)}><Sparkles size={17} /> Sort it for me</button>
        <button type="button" aria-pressed={!sortLater} onClick={() => setSortLater(false)}><FolderOpen size={17} /> Choose now</button>
      </div>

      {sortLater ? (
        <p className="hint" style={{ marginBottom: 14, lineHeight: 1.45 }}>
          We'll suggest one of your personal folders and mark it New on Home. Confirm or change it there. If you
          don't, it's filed automatically after it's been shown twice.
        </p>
      ) : (
        <div role="radiogroup" aria-label="Collection" style={{ marginBottom: 6 }}>
          {personal.map((f) => choice(f))}
          {choice(uncategorizedFolder())}
          {boards.length > 0 && <p className="hint" style={{ margin: '10px 0 8px', fontWeight: 700 }}>Shared boards</p>}
          {boards.map((f) => choice(f, 'Shared with friends, no tags'))}
        </div>
      )}
      {error && <p className="error" role="alert" style={{ marginBottom: 10 }}>{error}</p>}
      <button className="btn primary block" disabled={saving}>{saving ? 'Saving...' : 'Save link'}</button>
    </form>
  );
}
