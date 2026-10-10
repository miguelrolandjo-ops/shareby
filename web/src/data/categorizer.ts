/**
 * Suggests which personal folder a new save belongs to. Offline keyword/overlap scorer,
 * identical to the mobile app's, so a link sorts the same way on phone and web.
 * Swap for an embedding model behind the same interface later.
 */
export interface Suggestion {
  folderId: string | null; // null = not confident; goes to Uncategorized
  confidence: number;
}

export interface Candidate {
  id: string;
  name: string;
  examples: string[]; // titles already confirmed in that folder
}

const HINTS: Record<string, string[]> = {
  cook: ['resep', 'masak', 'goreng', 'ayam', 'sambel', 'sambal', 'geprek', 'pedas', 'rendang',
    'bumbu', 'cheesecake', 'kue', 'recipe', 'bake', 'nasi', 'mie', 'dessert', 'makanan'],
  resep: ['masak', 'goreng', 'ayam', 'sambel', 'bumbu', 'recipe', 'kue'],
  food: ['makan', 'kuliner', 'restaurant', 'resto', 'warung', 'street', 'enak'],
  trip: ['trip', 'itinerary', 'wisata', 'pantai', 'beach', 'hotel', 'villa', 'spot', 'travel',
    'sunrise', 'sunset', 'gunung', 'trek', 'jalan', 'liburan', 'staycation'],
  travel: ['trip', 'itinerary', 'wisata', 'hotel', 'flight', 'liburan'],
  cafe: ['cafe', 'kafe', 'kopi', 'coffee', 'latte', 'nongkrong', 'wfc', 'brunch', 'dessert'],
  sport: ['workout', 'lari', 'running', 'gym', 'sepatu', 'olahraga', 'fitness', 'yoga', 'futsal', 'basket'],
  inspo: ['moodboard', 'aesthetic', 'outfit', 'decor', 'dekorasi', 'ideas', 'ide', 'diy'],
};

const STOP = new Set(['yang', 'dan', 'buat', 'untuk', 'cara', 'ini', 'itu', 'dari', 'aja', 'banget', 'the',
  'and', 'for', 'with', 'you', 'your', 'how', 'www', 'com', 'http', 'https', 'reel', 'video', 'watch']);

export const tokenize = (s: string) =>
  new Set(s.toLowerCase().split(/[^a-z0-9]+/).filter((t) => t.length > 2 && !STOP.has(t)));

function score(tokens: Set<string>, c: Candidate): number {
  const name = tokenize(c.name);
  const hints = new Set<string>();
  for (const [key, words] of Object.entries(HINTS)) {
    if ([...name].some((t) => t.startsWith(key) || key.startsWith(t))) words.forEach((w) => hints.add(w));
  }
  const examples = new Set(c.examples.flatMap((e) => [...tokenize(e)]));
  let s = 0;
  for (const t of tokens) {
    if (name.has(t)) s += 1.0;
    else if (hints.has(t)) s += 0.8;
    else if (examples.has(t)) s += 0.4;
  }
  return s;
}

export function suggest(text: string, candidates: Candidate[], threshold = 0.3): Suggestion {
  const tokens = tokenize(text);
  if (!tokens.size || !candidates.length) return { folderId: null, confidence: 0 };
  let bestId: string | null = null;
  let best = 0;
  let second = 0;
  for (const c of candidates) {
    const s = score(tokens, c);
    if (s > best) {
      second = best;
      best = s;
      bestId = c.id;
    } else if (s > second) second = s;
  }
  if (!bestId || best === 0) return { folderId: null, confidence: 0 };
  const strength = best / (best + 1.2);
  const margin = (best - second) / best;
  const confidence = Math.min(1, Math.max(0, strength * (0.5 + 0.5 * margin)));
  return confidence >= threshold ? { folderId: bestId, confidence } : { folderId: null, confidence };
}
