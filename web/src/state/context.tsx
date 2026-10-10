import { createContext, useContext, useSyncExternalStore, type ReactNode } from 'react';
import type { AppStore, Snapshot } from './store';

const StoreContext = createContext<AppStore | null>(null);

export function StoreProvider({ store, children }: { store: AppStore; children: ReactNode }) {
  return <StoreContext.Provider value={store}>{children}</StoreContext.Provider>;
}

/** Actions. */
export function useStore(): AppStore {
  const store = useContext(StoreContext);
  if (!store) throw new Error('useStore must be used inside <StoreProvider>');
  return store;
}

/** Current data; re-renders when it changes. */
export function useApp(): Snapshot {
  const store = useStore();
  return useSyncExternalStore(store.subscribe, store.getSnapshot);
}
