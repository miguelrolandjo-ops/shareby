import 'package:flutter_test/flutter_test.dart';
import 'package:shareby/data/categorizer.dart';

void main() {
  const categorizer = KeywordCategorizer(threshold: 0.3);
  const folders = [
    CategoryCandidate(id: 'cooking', name: 'Cooking', examples: ['Resep nasi goreng cuma butuh 3 bahan']),
    CategoryCandidate(id: 'jakarta', name: 'Jakarta Trip', examples: ['Rooftop bar Senopati']),
    CategoryCandidate(id: 'bali', name: 'Bali Trip', examples: ['Sunrise trek Gunung Batur']),
    CategoryCandidate(id: 'cafe', name: 'Cafe Picks', examples: ['Kopi susu terenak di Kemang']),
  ];

  test('Indonesian recipe words go to Cooking', () {
    final s = categorizer.suggest('Ayam geprek sambel korek pedas nampol', folders);
    expect(s.folderId, 'cooking');
    expect(s.confidence, greaterThan(0.5));
  });

  test('a place named in the folder wins over generic trip words', () {
    final s = categorizer.suggest('Villa murah di Bali buat liburan', folders);
    expect(s.folderId, 'bali');
  });

  test('coffee goes to Cafe Picks', () {
    expect(categorizer.suggest('Kopi aren paling enak se-Jaksel', folders).folderId, 'cafe');
  });

  test('ambiguous or unrelated text is left Uncategorized', () {
    expect(categorizer.suggest('hello world', folders).folderId, isNull);
    expect(categorizer.suggest('Dessert box viral', folders).folderId, isNull); // cooking vs cafe tie
  });

  test('no folders means no suggestion', () {
    expect(categorizer.suggest('Resep ayam', const []).folderId, isNull);
  });
}
