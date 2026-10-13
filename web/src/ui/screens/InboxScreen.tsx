import { CircleCheck } from 'lucide-react';
import { config } from '../../config';
import { useApp } from '../../state/context';
import { folderOf, newItems } from '../../state/selectors';
import { Note } from '../components/bits';
import { LinkRow } from '../components/LinkViews';
import { useSheets } from '../components/Sheet';
import { ConfirmItemSheet } from '../sheets/ConfirmItemSheet';
import { ItemActionsSheet } from '../sheets/ItemActionsSheet';

/** Every auto-sorted link still waiting for a yes or a different folder. */
export function InboxScreen() {
  const snap = useApp();
  const sheets = useSheets();
  const items = newItems(snap);
  return (
    <>
      <h1>Needs a quick look</h1>
      <p className="muted" style={{ margin: '8px 0 20px', maxWidth: '60ch' }}>
        We guessed where these belong. Open one to keep the suggestion or pick another folder. Ones you skip are
        filed automatically after they've been shown {config.autoConfirmAfterViews} times.
      </p>
      {items.length === 0 ? (
        <div className="empty">
          <CircleCheck size={44} color="var(--brand)" aria-hidden style={{ margin: '0 auto' }} />
          <h3>You're all caught up</h3>
          <p>Links you save with "Sort it for me" show up here.</p>
        </div>
      ) : (
        items.map((item) => {
          const f = folderOf(snap, item);
          return (
            <LinkRow key={item.id} item={item} color={f.color} label={`Suggested: ${f.name}`}
              onOpen={() => sheets.open(<ConfirmItemSheet item={item} />)}
              onMenu={() => sheets.open(<ItemActionsSheet item={item} />)} />
          );
        })
      )}
    </>
  );
}
