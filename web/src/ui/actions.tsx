import { isDone, type Item } from '../data/models';
import { extractUrl, titleFromShareText } from '../data/urlUtils';
import { useStore } from '../state/context';
import { useSheets } from './components/Sheet';
import { friendlyError } from './errors';
import { AddLinkSheet } from './sheets/AddLinkSheet';

/** Actions shared by several screens. */
export function useActions() {
  const store = useStore();
  const sheets = useSheets();

  const openLink = (url: string) => window.open(url, '_blank', 'noopener,noreferrer');

  const toggleDone = async (item: Item) => {
    const nowDone = !isDone(item);
    try {
      await store.setDone(item, nowDone);
      store.showToast(nowDone ? 'Marked as done' : 'Moved back to to-do', {
        label: 'Undo',
        run: () => void store.restoreCompletion(item),
      });
    } catch (e) {
      store.showToast(friendlyError(e));
    }
  };

  /** Paste: only opens the save sheet when the clipboard actually holds a link. */
  const pasteLink = async (folderId?: string) => {
    let text = '';
    try {
      text = await navigator.clipboard.readText();
    } catch {
      // Clipboard permission denied or unsupported: let the person paste into the field.
    }
    const url = extractUrl(text);
    sheets.open(<AddLinkSheet initialUrl={url ?? ''} initialTitle={url ? titleFromShareText(text, url) : ''} folderId={folderId} />);
  };

  return { openLink, toggleDone, pasteLink };
}
