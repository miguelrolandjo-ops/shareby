import { css, isNew, uncategorizedFolder, UNCATEGORIZED, type Item } from '../../data/models';
import { config } from '../../config';
import { useApp, useStore } from '../../state/context';
import { folderOf, personalFolders } from '../../state/selectors';
import { deep, soft, SourcePill, Thumb } from '../components/bits';
import { SheetHead, useSheets } from '../components/Sheet';
import { useState } from 'react';

/** Review an auto-sorted [New] link, or move a confirmed one. */
export function ConfirmItemSheet({ item }: { item: Item }) {
  const snap = useApp();
  const store = useStore();
  const { close } = useSheets();
  const reviewing = isNew(item);
  const [picking, setPicking] = useState(!reviewing);
  const suggested = folderOf(snap, item);
  const views = Math.min(item.viewCount, config.autoConfirmAfterViews);

  async function file(moveTo?: string) {
    await store.confirmItem(item, moveTo);
    const name = moveTo ? (moveTo === UNCATEGORIZED ? 'Uncategorized' : snap.folders.find((f) => f.id === moveTo)?.name) : suggested.name;
    close();
    store.showToast(`Filed in ${name ?? 'your folder'}`);
  }

  return (
    <div>
      <SheetHead title={reviewing ? 'Where does this go?' : 'Move link'} />
      <div className="row" style={{ marginBottom: 16 }}>
        <Thumb item={item} color={suggested.color} size={64} />
        <div className="grow">
          <h3 style={{ marginBottom: 6 }}>{item.title}</h3>
          <SourcePill source={item.source} />
        </div>
      </div>

      {reviewing && (
        <>
          <div className="card" style={{ background: soft(suggested.color), color: deep(suggested.color), marginBottom: 14 }}>
            <div className="row" style={{ marginBottom: 8, fontWeight: 700 }}>
              <span aria-hidden>{suggested.emoji}</span>
              <span className="grow">{item.folderId ? `Suggested: ${suggested.name}` : 'No confident match'}</span>
              <span>{Math.round(item.confidence * 100)}%</span>
            </div>
            <div className="meter" role="meter" aria-label="Confidence" aria-valuenow={Math.round(item.confidence * 100)} aria-valuemin={0} aria-valuemax={100}>
              <div style={{ width: `${Math.max(5, item.confidence * 100)}%`, background: css(suggested.color) }} />
            </div>
          </div>
          <div className="steps" aria-hidden>
            {Array.from({ length: config.autoConfirmAfterViews }, (_, i) => <div key={i} className={i < views ? 'on' : ''} />)}
          </div>
          <p className="hint" style={{ margin: '6px 0 16px' }}>
            Shown {views} of {config.autoConfirmAfterViews} times. If you don't choose, it's filed here the next time you open Shareby.
          </p>
        </>
      )}

      {!picking ? (
        <div style={{ display: 'grid', gap: 10 }}>
          <button className="btn primary block" onClick={() => file()} autoFocus>Keep in {suggested.name}</button>
          <button className="btn block" onClick={() => setPicking(true)}>Choose a different folder</button>
        </div>
      ) : (
        <div role="radiogroup" aria-label={reviewing ? 'File it in' : 'Move to'}>
          {[...personalFolders(snap), uncategorizedFolder()].map((f) => (
            <button key={f.id} type="button" role="radio" className="choice"
              aria-checked={f.id === (item.folderId ?? UNCATEGORIZED)} onClick={() => file(f.id)}>
              <span className="emoji-badge" style={{ background: soft(f.color) }} aria-hidden>{f.emoji}</span>
              <strong className="grow">{f.name}</strong>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
