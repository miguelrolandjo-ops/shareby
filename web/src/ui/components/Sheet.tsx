import { X } from 'lucide-react';
import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from 'react';

interface SheetApi {
  open: (node: ReactNode) => void;
  close: () => void;
}
const SheetContext = createContext<SheetApi | null>(null);

export function useSheets(): SheetApi {
  const api = useContext(SheetContext);
  if (!api) throw new Error('useSheets must be used inside <SheetHost>');
  return api;
}

/** Shows one sheet at a time, from anywhere (FAB, global paste, share target...). */
export function SheetHost({ children }: { children: ReactNode }) {
  const [node, setNode] = useState<ReactNode>(null);
  const [key, setKey] = useState(0);
  const open = useCallback((n: ReactNode) => { setNode(n); setKey((k) => k + 1); }, []);
  const close = useCallback(() => setNode(null), []);
  return (
    <SheetContext.Provider value={{ open, close }}>
      {children}
      {node && <Dialog key={key} onClose={close}>{node}</Dialog>}
    </SheetContext.Provider>
  );
}

/** Native <dialog>: focus trap, Esc, and an inert page behind it. */
function Dialog({ children, onClose }: { children: ReactNode; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const d = ref.current;
    if (d && !d.open) d.showModal();
    return () => d?.close();
  }, []);
  return (
    <dialog
      ref={ref}
      className="sheet"
      onClose={onClose}
      onCancel={(e) => { e.preventDefault(); onClose(); }}
      onClick={(e) => { if (e.target === ref.current) onClose(); }} // backdrop click
    >
      <div className="sheet-body">
        <div className="sheet-handle" aria-hidden />
        {children}
      </div>
    </dialog>
  );
}

export function SheetHead({ title, subtitle }: { title: string; subtitle?: ReactNode }) {
  const { close } = useSheets();
  return (
    <div className="sheet-head">
      <div className="grow">
        <h2>{title}</h2>
        {subtitle && <p className="muted small">{subtitle}</p>}
      </div>
      <button type="button" className="icon-btn" onClick={close} aria-label="Close"><X size={20} /></button>
    </div>
  );
}
