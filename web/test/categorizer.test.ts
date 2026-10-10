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
