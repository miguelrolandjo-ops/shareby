import { useEffect } from 'react';
import { useApp, useStore } from '../../state/context';

/** One toast at a time; ones with Undo stay a little longer. */
export function Toaster() {
  const { toast } = useApp();
  const store = useStore();
  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => store.dismissToast(toast.id), toast.action ? 5000 : 3000);
    return () => clearTimeout(t);
  }, [toast, store]);
  if (!toast) return null;
  return (
    <div className="toast" role="status" aria-live="polite">
      <span>{toast.message}</span>
      {toast.action && (
        <button type="button" onClick={() => { toast.action!.run(); store.dismissToast(toast.id); }}>
          {toast.action.label}
        </button>
      )}
    </div>
  );
}
