import 'package:flutter_test/flutter_test.dart';
import 'package:shareby/data/categorizer.dart';
import 'package:shareby/data/folder_namer.dart';
import 'package:shareby/data/regions.dart';
import 'package:shareby/data/sources.dart';
import 'package:shareby/l10n/l10n.dart';

import 'test_rules.dart';

void main() {
  setUpAll(loadBundledRules);

  const kompas = CustomSource(id: 'k1', name: 'Kompas', host: 'kompas.com', exampleUrl: 'https://www.kompas.com/x');

  group('custom sources', () {
    test('a custom source is recognised from the link, built-ins win', () {
      final catalog = SourceCatalog(custom: [kompas]);
      expect(catalog.keyFor('https://megapolitan.kompas.com/read/2026/banjir', 'web'), 'custom-k1');
      expect(catalog.keyFor('https://www.instagram.com/reel/abc', 'instagram'), 'instagram');
      expect(catalog.keyFor('https://example.org/a', 'web'), 'web');
      expect(catalog.info('custom-k1')!.name, 'Kompas');
    });

    test('the host comes from the example link, without www', () {
      expect(CustomSource.hostOf('https://www.kompas.com/read/1'), 'kompas.com');
      expect(CustomSource.hostOf('detik.com/news'), 'detik.com');
      expect(CustomSource.hostOf('not a link'), isNull);
    });

    test('validation needs a name and a real link, and refuses duplicates and built-ins', () {
      final catalog = SourceCatalog(custom: [kompas]);
      expect(catalog.validate('', 'https://detik.com'), isNotNull);
      expect(catalog.validate('Detik', 'nope'), isNotNull);
      expect(catalog.validate('Detik', 'https://www.detik.com/news/1'), isNull);
      expect(catalog.validate('Kompas again', 'https://kompas.com/b'), isNotNull);
      SourceInfo? builtIn;
      expect(catalog.validate('IG', 'https://instagram.com/p/1', builtInMatch: (b) => builtIn = b), isNotNull);
      expect(builtIn?.key, 'instagram');
    });

    test('the filter lists switched-on built-ins and custom sources only', () {
      final catalog = SourceCatalog(enabled: {'instagram', 'shopee'}, custom: [kompas]);
      expect(catalog.filterOptions.map((s) => s.key), ['instagram', 'shopee', 'custom-k1']);
    });

    test('a custom source name is not treated as a topic word', () {
      SourceCatalog.current = SourceCatalog(custom: [kompas]);
      const folders = [CategoryCandidate(id: 'news', name: 'Kompas picks')];
      expect(KeywordCategorizer().suggest('Kompas: banjir di Jakarta', folders).folderId, isNull);
      SourceCatalog.current = SourceCatalog();
    });
  });

  group('the source counts in sorting', () {
    final music = CategoryCandidate(
      id: 'music',
      name: 'Chill',
      examples: const ['Hype Boy', 'Ditto', 'Super Shy', 'OMG'],
      exampleSources: const ['spotify', 'spotify', 'spotify', 'youtube'],
    );
    final food = CategoryCandidate(
      id: 'food',
      name: 'Food',
      examples: const ['Ramen spot', 'Best sushi', 'Nasi goreng'],
      exampleSources: const ['instagram', 'tiktok', 'instagram'],
    );

    test('a link from the source a folder is mostly made of goes there', () {
      final s = KeywordCategorizer().suggest('Bubble Gum', [music, food], source: 'spotify');
      expect(s.folderId, 'music');
    });

    test('without that source nothing is guessed', () {
      expect(KeywordCategorizer().suggest('Bubble Gum', [music, food], source: 'web').folderId, isNull);
    });

    test('a source spread across folders is no signal', () {
      final f2 = CategoryCandidate(
        id: 'more', name: 'More', examples: const ['a b', 'c d', 'e f'], exampleSources: const ['spotify', 'spotify', 'spotify'],
      );
      expect(KeywordCategorizer().suggest('Bubble Gum', [music, f2], source: 'spotify').folderId, isNull);
    });
  });

  group('regions', () {
    test('every region default is a real built-in source', () {
      final known = SourceCatalog().builtIns.map((s) => s.key).toSet();
      for (final r in regions) {
        expect(known.containsAll(r.sources), isTrue, reason: r.code);
      }
    });

    test('Indonesia defaults to Indonesian and local shops', () {
      final id = regionByCode('id');
      expect(id.language, AppLanguage.id);
      expect(id.sources, containsAll(['shopee', 'tokopedia', 'gofood']));
      expect(regionByCode('us').language, AppLanguage.en);
      expect(regionByCode('nowhere').code, 'global');
    });

    test('suggested folder names follow the language', () {
      L10n.current = AppLanguage.id;
      expect(const FolderNamer().propose('Creamy chicken pasta for dinner', {}).name, 'Resep');
      L10n.current = AppLanguage.en;
      expect(const FolderNamer().propose('Creamy chicken pasta for dinner', {}).name, 'Recipes');
    });
  });
}
