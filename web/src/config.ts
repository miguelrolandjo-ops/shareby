/** Build-time settings (set with VITE_* env vars). */
export const config = {
  /** Same-origin path that Nginx (or the Vite dev server) proxies to the API. */
  apiBase: import.meta.env.VITE_API_BASE ?? '/api',
  seedDemoData: (import.meta.env.VITE_SEED_DEMO ?? 'true') !== 'false',
  syncIntervalMs: 45_000,
  /** A [New] link shown this many times without confirmation is filed on the next showing. */
  autoConfirmAfterViews: 2,
  suggestionThreshold: 0.3,
};
