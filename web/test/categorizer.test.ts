import { describe, expect, it } from 'vitest';
import { suggest } from '../src/data/categorizer';

const folders = [
  { id: 'cooking', name: 'Cooking', examples: ['Resep nasi goreng cuma butuh 3 bahan'] },
  { id: 'jakarta', name: 'Jakarta Trip', examples: ['Rooftop bar Senopati'] },
  { id: 'bali', name: 'Bali Trip', examples: ['Sunrise trek Gunung Batur'] },
  { id: 'cafe', name: 'Cafe Picks', examples: ['Kopi susu terenak di Kemang'] },
];

describe('categorizer (same results as the phone app)', () => {
  it('sends Indonesian recipe words to Cooking', () => {
    const s = suggest('Ayam geprek sambel korek pedas nampol', folders);
    expect(s.folderId).toBe('cooking');
    expect(s.confidence).toBeGreaterThan(0.5);
  });
  it('prefers the place named in the folder', () => {
    expect(suggest('Villa murah di Bali buat liburan', folders).folderId).toBe('bali');
  });
  it('sends coffee to Cafe Picks', () => {
    expect(suggest('Kopi aren paling enak se-Jaksel', folders).folderId).toBe('cafe');
  });
  it('leaves ambiguous or unrelated text uncategorized', () => {
    expect(suggest('hello world', folders).folderId).toBeNull();
    expect(suggest('Dessert box viral', folders).folderId).toBeNull();
  });
});

describe('categorizer in English', () => {
  const english = [
    { id: 'recipes', name: 'Recipes', examples: [] },
    { id: 'cafes', name: 'Cafes', examples: [] },
    { id: 'gifts', name: 'Gift Ideas', examples: [] },
    { id: 'gym', name: 'Workouts', examples: [] },
    { id: 'books', name: 'Books to read', examples: [] },
  ];
  it('matches plural folder names to singular words and back', () => {
    expect(suggest('Easy one-pan pasta recipe', english).folderId).toBe('recipes');
    expect(suggest('Tiny cafe hidden in Kemang', english).folderId).toBe('cafes');
    expect(suggest('Birthday gift for my sister', english).folderId).toBe('gifts');
  });
  it('knows common English words for English-named folders', () => {
    expect(suggest('Chicken soup for dinner, ready in 20 minutes', english).folderId).toBe('recipes');
    expect(suggest('10 minute abs and cardio routine', english).folderId).toBe('gym');
    expect(suggest('Novels everyone on BookTok is reading', english).folderId).toBe('books');
  });
  it('still leaves unrelated English text uncategorized', () => {
    expect(suggest('Funny moment at the airport', english).folderId).toBeNull();
  });
  it('mixes with Indonesian folders', () => {
    const mixed = [...english, { id: 'resep', name: 'Resep', examples: [] }];
    expect(suggest('Resep ayam goreng', mixed).folderId).toBe('resep');
  });
});
