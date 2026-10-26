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

/**
 * Words that point to a folder whose NAME starts with the key, in Indonesian and English
 * (so a folder called "Recipes", "Resep" or "Cooking" catches "easy pasta recipe" alike).
 * Keys and words are singular; see `singular`.
 */
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
  inspo: ['moodboard', 'aesthetic', 'outfit', 'decor', 'dekorasi', 'idea', 'ide', 'diy'],
  // English-named folders
  recipe: ['cook', 'cooking', 'bake', 'baking', 'dinner', 'lunch', 'breakfast', 'pasta', 'chicken', 'soup',
    'salad', 'cake', 'cookie', 'dessert', 'ingredient', 'meal', 'oven', 'airfryer', 'resep', 'masak'],
  meal: ['recipe', 'cook', 'dinner', 'lunch', 'breakfast', 'prep', 'healthy'],
  bak: ['bread', 'cake', 'cookie', 'oven', 'dough', 'pastry', 'recipe'],
  restaurant: ['food', 'dinner', 'brunch', 'eat', 'menu', 'resto', 'kuliner'],
  eat: ['food', 'restaurant', 'brunch', 'dinner', 'street', 'kuliner'],
  coffee: ['cafe', 'latte', 'espresso', 'brew', 'barista', 'kopi'],
  vacation: ['trip', 'travel', 'hotel', 'beach', 'flight', 'itinerary', 'resort'],
  holiday: ['trip', 'travel', 'hotel', 'beach', 'flight', 'itinerary', 'liburan'],
  fit: ['workout', 'gym', 'exercise', 'training', 'running', 'yoga', 'pilates', 'cardio', 'muscle'],
  workout: ['gym', 'exercise', 'training', 'abs', 'cardio', 'fitness', 'routine'],
  gym: ['workout', 'exercise', 'training', 'muscle', 'lift'],
  fashion: ['outfit', 'style', 'dress', 'shirt', 'jacket', 'sneaker', 'ootd', 'wear', 'baju'],
  style: ['outfit', 'fashion', 'dress', 'ootd', 'wear'],
  outfit: ['ootd', 'style', 'dress', 'fashion', 'wear'],
  beauty: ['skincare', 'makeup', 'serum', 'lipstick', 'hair', 'nail', 'glow'],
  skincare: ['serum', 'sunscreen', 'moisturizer', 'cleanser', 'acne', 'routine'],
  home: ['decor', 'interior', 'room', 'kitchen', 'bedroom', 'furniture', 'organize', 'diy', 'rumah'],
  decor: ['interior', 'room', 'furniture', 'aesthetic', 'home'],
  music: ['song', 'playlist', 'album', 'concert', 'cover', 'lyric', 'guitar', 'piano', 'lagu'],
  movie: ['film', 'trailer', 'netflix', 'series', 'watchlist', 'review', 'cinema'],
  film: ['movie', 'trailer', 'netflix', 'series', 'cinema'],
  book: ['read', 'reading', 'novel', 'author', 'booktok', 'library', 'buku'],
  read: ['book', 'novel', 'booktok', 'article'],
  tech: ['gadget', 'phone', 'laptop', 'app', 'review', 'setup', 'coding', 'software'],
  money: ['invest', 'investing', 'saving', 'budget', 'finance', 'stock', 'crypto', 'tabungan'],
  financ: ['invest', 'investing', 'saving', 'budget', 'money', 'stock'],
  learn: ['tutorial', 'course', 'tip', 'lesson', 'study', 'guide', 'belajar'],
  study: ['tutorial', 'course', 'note', 'exam', 'lesson', 'belajar'],
  shop: ['buy', 'wishlist', 'deal', 'sale', 'discount', 'shopee', 'tokopedia', 'belanja'],
  wishlist: ['buy', 'want', 'gift', 'deal', 'sale'],
  gift: ['present', 'birthday', 'hadiah', 'kado', 'idea'],
  pet: ['cat', 'dog', 'puppy', 'kitten', 'kucing', 'anjing'],
  gam: ['game', 'gaming', 'gameplay', 'playstation', 'nintendo', 'steam', 'xbox'],
  craft: ['diy', 'sewing', 'knit', 'crochet', 'pattern', 'handmade'],
  art: ['drawing', 'painting', 'design', 'illustration', 'sketch'],
};

const STOP = new Set([
  // Indonesian filler
  'yang', 'dan', 'buat', 'untuk', 'cara', 'ini', 'itu', 'dari', 'aja', 'banget', 'dengan', 'atau', 'juga',
  'ada', 'bisa', 'kita', 'kamu', 'aku', 'saya', 'nya', 'gak', 'nggak', 'udah', 'lagi', 'jadi', 'pada',
  // English filler (same list as the phone app)
  'the', 'and', 'for', 'with', 'you', 'your', 'how', 'one', 'are', 'was', 'but', 'not', 'this', 'that',
  'have', 'has', 'from', 'they', 'their', 'what', 'when', 'will', 'about', 'more', 'some', 'all', 'out',
  'its', 'our', 'can', 'get', 'just', 'like', 'love', 'best', 'new', 'top', 'most', 'very', 'than', 'then',
  'who', 'why', 'here', 'there', 'been', 'into', 'over', 'make', 'made', 'only', 'also', 'any', 'too',
  // platforms and media types
  'www', 'com', 'http', 'https', 'instagram', 'tiktok', 'youtube', 'facebook', 'twitter', 'threads',
  'reel', 'video', 'watch', 'short', 'post', 'photo', 'story', 'link', 'saved', 'viral', 'fyp', 'foryou', 'explore',
]);

/**
 * English plurals to their singular ("recipes" -> "recipe", "berries" -> "berry"), so folder
 * names and titles match either way. Never touches words ending in -ss, -us or -is
 * ("glass", "bagus", "manis"). Same rule as the phone app.
 */
export function singular(t: string): string {
  if (t.length < 4 || !/^[a-z]+$/.test(t)) return t;
  if (t.endsWith('ies') && t.length > 4) return `${t.slice(0, -3)}y`;
  if (/(?:ches|shes|xes|sses|zes)$/.test(t)) return t.slice(0, -2);
  if (t.endsWith('s') && !t.endsWith('ss') && !t.endsWith('us') && !t.endsWith('is')) return t.slice(0, -1);
  return t;
}

export const tokenize = (s: string) =>
  new Set(s.toLowerCase().split(/[^a-z0-9]+/).filter((t) => t.length > 2).map(singular).filter((t) => !STOP.has(t)));

function score(tokens: Set<string>, c: Candidate): number {
  const name = tokenize(c.name);
  const hints = new Set<string>();
  for (const [key, words] of Object.entries(HINTS)) {
    if ([...name].some((t) => t.startsWith(key) || key.startsWith(t))) words.forEach((w) => hints.add(singular(w)));
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
