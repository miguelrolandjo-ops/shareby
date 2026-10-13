import 'package:flutter_test/flutter_test.dart';
import 'package:shareby/data/categorizer.dart';

void main() {
  const categorizer = KeywordCategorizer(threshold: 0.3);

  // The categorizer knows no words of its own: it matches folder names and learns from the
  // titles filed in each folder.
  const folders = [
    CategoryCandidate(id: 'cooking', name: 'Cooking', examples: [
      'Resep nasi goreng cuma butuh 3 bahan',
      'Resep ayam geprek pedas',
      'Cara bikin sambel matah',
    ]),
    CategoryCandidate(id: 'jakarta', name: 'Jakarta Trip', examples: ['Rooftop bar Senopati']),
    CategoryCandidate(id: 'bali', name: 'Bali Trip', examples: ['Sunrise trek Gunung Batur']),
    CategoryCandidate(id: 'cafe', name: 'Cafe Picks', examples: ['Kopi susu terenak di Kemang']),
  ];

  test('a word from the folder name matches it', () {
    final s = categorizer.suggest('Villa murah di Bali buat liburan', folders);
    expect(s.folderId, 'bali');
    expect(s.confidence, greaterThan(0.3));
  });

  test('words learned from the folder\'s saves match it', () {
    // "resep" recurs in Cooking's titles and appears nowhere else.
    expect(categorizer.suggest('Resep sambel ayam kecap', folders).folderId, 'cooking');
  });

  test('no built-in vocabulary: an unfamiliar word is not guessed', () {
    expect(categorizer.suggest('Kopi aren paling enak se-Jaksel', folders).folderId, isNull);
    expect(categorizer.suggest('hello world', folders).folderId, isNull);
  });

  test('a tie between two folders is left Uncategorized', () {
    const tie = [
      CategoryCandidate(id: 'a', name: 'Dessert Ideas'),
      CategoryCandidate(id: 'b', name: 'Dessert Spots'),
    ];
    expect(categorizer.suggest('Dessert box viral', tie).folderId, isNull);
  });

  test('no folders means no suggestion', () {
    expect(categorizer.suggest('Resep ayam', const []).folderId, isNull);
  });

  group('any language', () {
    test('Korean, Japanese and Chinese folder names match', () {
      const cjk = [
        CategoryCandidate(id: 'ko', name: '여행'),
        CategoryCandidate(id: 'ja', name: 'レシピ'),
        CategoryCandidate(id: 'zh', name: '美食'),
      ];
      expect(categorizer.suggest('제주도 여행 추천 코스', cjk).folderId, 'ko');
      expect(categorizer.suggest('簡単レシピ 5分で完成', cjk).folderId, 'ja');
      expect(categorizer.suggest('上海美食 探店', cjk).folderId, 'zh');
    });

    test('accented words are kept, not stripped', () {
      const es = [CategoryCandidate(id: 'cocina', name: 'Cocina')];
      expect(categorizer.suggest('Receta de cocina fácil', es).folderId, 'cocina');
      const fr = [CategoryCandidate(id: 'cafe', name: 'Café')];
      expect(categorizer.suggest('Le meilleur café de Paris', fr).folderId, 'cafe');
    });
  });

  group('real-world Instagram saves', () {
    // Sew already holds several Instagram links: "... on Instagram" is in all their titles.
    final mine = [
      CategoryCandidate(id: 'sew', name: 'Sew', examples: [
        for (final t in [
          'Hand sewing a hem',
          'Easy tote bag pattern',
          'Crochet basics',
          'Fabric haul',
          'Sewing machine tips',
          'Alter jeans at home',
          'Thrifted fabric ideas',
          'Button repair',
        ])
          '$t on Instagram: "caption text here"',
      ]),
      const CategoryCandidate(id: 'mtg', name: 'magic the gathering', examples: ['Deck tech on Instagram']),
      const CategoryCandidate(id: 'kpop', name: 'Kpop', examples: ['NewJeans on Instagram']),
      const CategoryCandidate(id: 'jobs', name: 'Job Posting', examples: ['Hiring designer on Instagram']),
    ];
    const url = 'https://www.instagram.com/reel/DAbC12xyz/';
    const mtgPost =
        'TapForMe_MTG on Instagram: "Roxxane, starfall savant is one of my favorite commanders and it’s ..." $url';

    test('random posts do not land in Sew just because both are on Instagram', () {
      for (final text in [
        'FEDRS | NICOTINE POUCHES on Instagram: "Pouches that are looking for tributors" $url',
        'Some random chef on Instagram: "Weekend vibes with the family" $url',
        'on Instagram: "just posted a photo" $url',
      ]) {
        expect(categorizer.suggest(text, mine).folderId, isNull, reason: text);
      }
    });

    test('an MTG post is not forced into the wrong folder before anything is learned', () {
      expect(categorizer.suggest(mtgPost, mine).folderId, isNull);
    });

    test('a single word shared with one old title is not enough', () {
      expect(categorizer.suggest('Tote on Instagram $url', mine).folderId, isNull);
    });

    test('a folder is still found by what its saved titles share', () {
      expect(categorizer.suggest('Sewing a tote bag with fabric scraps on Instagram $url', mine).folderId, 'sew');
    });

    test('once MTG saves are filed, new MTG posts follow them', () {
      final learned = [
        mine.first,
        const CategoryCandidate(id: 'mtg', name: 'magic the gathering', examples: [
          'Commander deck tech from TapForMe_MTG',
          'Sealed MTG pack opening',
          'Budget MTG upgrades',
        ]),
        ...mine.skip(2),
      ];
      expect(categorizer.suggest(mtgPost, learned).folderId, 'mtg');
    });
  });

  group('learning from what is filed', () {
    CategoryCandidate cards(List<String> titles) => CategoryCandidate(id: 'cards', name: 'Cards', examples: titles);
    const other =
        CategoryCandidate(id: 'sew', name: 'Sew', examples: ['Hand sewing a hem', 'Fabric haul', 'Crochet basics']);
    const post = 'TapForMe_MTG: Roxxane, starfall savant is a favorite https://www.instagram.com/reel/abc/';

    test('a folder with an unrelated name starts matching once it has a few related saves', () {
      expect(categorizer.suggest(post, [cards(const []), other]).folderId, isNull);
      expect(
          categorizer.suggest(post, [
            cards(const ['MTG deck tech']),
            other
          ]).folderId,
          isNull); // one save: not yet
      final learned = cards(const ['MTG deck tech', 'Sealed MTG pack opening', 'Budget MTG upgrades']);
      expect(categorizer.suggest(post, [learned, other]).folderId, 'cards');
    });

    test('a word shared by two folders is not treated as a learned keyword', () {
      const a = CategoryCandidate(id: 'a', name: 'Alpha', examples: ['MTG deck tech', 'MTG pack opening']);
      const b = CategoryCandidate(id: 'b', name: 'Beta', examples: ['MTG budget upgrades', 'MTG rules']);
      expect(categorizer.suggest(post, [a, b]).folderId, isNull);
    });
  });
}
