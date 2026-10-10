import { css, isDone, isNew, type Item } from '../../data/models';
import { NewPill, SourcePill, Thumb } from './bits';
import { Tick } from './bits';

interface Props {
  item: Item;
  color: number;
  shared?: boolean;
  /** Replaces the tag/author line, e.g. the folder name in search results. */
  label?: string;
  doneLabel?: string;
  onOpen: () => void;
  onMenu: () => void;
  /** Shows the done tick (absent for [New] links and for viewers). */
  onToggleDone?: () => void;
}

function metaText({ item, shared, label, doneLabel }: Props): string | null {
  if (label) return label;
  if (shared) return isDone(item) ? (doneLabel ?? 'Done') : `added by ${item.addedByName ?? 'someone'}`;
  return item.tag;
}

/** Right-click / long-press opens the actions menu, like a native app. */
const menuHandlers = (onMenu: () => void) => ({
  onContextMenu: (e: React.MouseEvent) => { e.preventDefault(); onMenu(); },
});

export function LinkRow(p: Props) {
  const { item, color, onOpen, onMenu, onToggleDone } = p;
  const meta = metaText(p);
  return (
    <div
      className={`link-row${isDone(item) ? ' is-done' : ''}`}
      style={{ borderLeftColor: css(color) }}
      {...menuHandlers(onMenu)}
    >
      <Thumb item={item} color={color} size={58} />
      <div className="grow">
        <button type="button" className="title stretched" onClick={onOpen}>{item.title}</button>
        <div className="meta"><SourcePill source={item.source} />{meta && <span>{meta}</span>}</div>
      </div>
      {isNew(item) ? <NewPill /> : onToggleDone && <Tick done={isDone(item)} onToggle={onToggleDone} />}
      <MenuButton onMenu={onMenu} title={item.title} />
    </div>
  );
}

export function LinkCard(p: Props) {
  const { item, color, onOpen, onMenu, onToggleDone } = p;
  const meta = metaText(p);
  return (
    <div
      className={`link-card${isDone(item) ? ' is-done' : ''}`}
      style={{ borderTopColor: css(color) }}
      {...menuHandlers(onMenu)}
    >
      <div style={{ position: 'relative' }}>
        <Thumb item={item} color={color} />
        <span className="on-thumb" style={{ left: 8 }}><SourcePill source={item.source} /></span>
        {isNew(item) && <span className="on-thumb" style={{ right: 8 }}><NewPill /></span>}
        {!isNew(item) && onToggleDone && <Tick overlay done={isDone(item)} onToggle={onToggleDone} />}
      </div>
      <div className="body">
        <button type="button" className="title stretched" onClick={onOpen}>{item.title}</button>
        <div className="row" style={{ marginTop: 4 }}>
          {meta ? <span className="grow faint small" style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{meta}</span> : <span className="grow" />}
          <MenuButton onMenu={onMenu} title={item.title} />
        </div>
      </div>
    </div>
  );
}

function MenuButton({ onMenu, title }: { onMenu: () => void; title: string }) {
  return (
    <button
      type="button"
      className="icon-btn"
      style={{ width: 32, height: 32, flex: 'none' }}
      aria-label={`More actions for ${title}`}
      onClick={(e) => { e.stopPropagation(); onMenu(); }}
    >
      <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden><circle cx="5" cy="12" r="2" fill="currentColor" /><circle cx="12" cy="12" r="2" fill="currentColor" /><circle cx="19" cy="12" r="2" fill="currentColor" /></svg>
    </button>
  );
}
