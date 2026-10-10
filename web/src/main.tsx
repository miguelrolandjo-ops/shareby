import '@fontsource/fredoka/latin-500.css';
import '@fontsource/fredoka/latin-600.css';
import '@fontsource/fredoka/latin-700.css';
import '@fontsource/plus-jakarta-sans/latin-400.css';
import '@fontsource/plus-jakarta-sans/latin-500.css';
import '@fontsource/plus-jakarta-sans/latin-600.css';
import '@fontsource/plus-jakarta-sans/latin-700.css';
import './styles/global.css';

import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { StoreProvider } from './state/context';
import { AppStore } from './state/store';
import { App } from './ui/App';

const root = createRoot(document.getElementById('root')!);

AppStore.create()
  .then(async (store) => {
    await store.init(); // local data first: no network needed to show the app
    root.render(
      <StrictMode>
        <StoreProvider store={store}>
          <App />
        </StoreProvider>
      </StrictMode>,
    );
  })
  .catch((err) => {
    console.error(err);
    root.render(
      <div className="empty" style={{ paddingTop: 80 }}>
        <h3>Shareby can't store data in this browser</h3>
        <p>Private browsing or blocked site storage stops it from saving your links. Open Shareby in a normal window.</p>
      </div>,
    );
  });
