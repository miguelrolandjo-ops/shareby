import type { Source } from './models';

const URL_PATTERN = /https?:\/\/[^\s<>"]+/i;
const TRAILING_JUNK = '.,;:!?)\'"';

/** First http(s) link in the text, or null — so "paste" only ever pastes a real link. */
export function extractUrl(text: string | null | undefined): string | null {
  if (!text) return null;
  const match = URL_PATTERN.exec(text);
  if (!match) return null;
  let url = match[0];
  while (url.length && TRAILING_JUNK.includes(url[url.length - 1])) url = url.slice(0, -1);
  try {
    return new URL(url).host ? url : null;
  } catch {
    return null;
  }
}

const host = (url: string) => {
  try {
    return new URL(url).hostname.toLowerCase();
  } catch {
    return '';
  }
};

export function detectSource(url: string): Source {
  const h = host(url);
  if (h.endsWith('instagram.com')) return 'instagram';
  if (h.endsWith('youtube.com') || h === 'youtu.be') return 'youtube';
  if (h.endsWith('tiktok.com')) return 'tiktok';
  return 'web';
}

/** YouTube thumbnails come from the link itself, no server needed. */
export function youtubeThumbnail(url: string): string | null {
  let u: URL;
  try {
    u = new URL(url);
  } catch {
    return null;
  }
  const h = u.hostname.toLowerCase();
  const parts = u.pathname.split('/').filter(Boolean);
  let id: string | null = null;
  if (h === 'youtu.be') id = parts[0] ?? null;
  else if (h.endsWith('youtube.com')) {
    id = u.searchParams.get('v');
    if (!id && parts.length >= 2 && (parts[0] === 'shorts' || parts[0] === 'embed')) id = parts[1];
  }
  return id && /^[A-Za-z0-9_-]{11}$/.test(id) ? `https://img.youtube.com/vi/${id}/hqdefault.jpg` : null;
}

export function fallbackTitle(url: string): string {
  const h = host(url).replace(/^www\./, '');
  return h ? `Saved from ${h}` : url;
}

export const isFallbackTitle = (title: string) => title.startsWith('Saved from ');

/** Share sheets send "caption https://link": keep the caption as the title. */
export function titleFromShareText(text: string | null | undefined, url: string): string {
  if (!text) return fallbackTitle(url);
  const cleaned = text.split(url).join('').replace(/\s+/g, ' ').trim();
  if (cleaned.length < 3) return fallbackTitle(url);
  return cleaned.length > 120 ? cleaned.slice(0, 117) + '...' : cleaned;
}
