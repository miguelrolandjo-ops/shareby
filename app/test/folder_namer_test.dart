import 'package:flutter_test/flutter_test.dart';
import 'package:shareby/data/folder_namer.dart';

void main() {
  const namer = FolderNamer();

  test('a NewJeans post gets a broad K-Pop folder, not an artist folder', () {
    final p = namer.propose('NewJeans Hype Boy performance https://youtu.be/abc', {});
    expect(p.name, 'K-Pop');
    expect(p.existingId, isNull);
  });

  test('reuses an existing broader folder instead of creating a new one', () {
    final p = namer.propose('NewJeans fancam', {'f1': 'Music', 'f2': 'Cooking'});
    expect(p.existingId, 'f1');
    expect(p.name, 'Music');
  });

  test('short keywords only match whole words', () {
    expect(namer.propose('rain on the window', {}).name, 'Inspo');
  });

  test('unknown topics fall back to a general folder', () {
    expect(namer.propose('Saved from instagram.com', {}).name, 'Inspo');
  });

  group('English', () {
    test('common English saves get a fitting folder', () {
      expect(namer.propose('Creamy chicken pasta for dinner', {}).name, 'Recipes');
      expect(namer.propose('Things to do on a weekend road trip', {}).name, 'Travel');
      expect(namer.propose('My favorite novels this year #booktok', {}).name, 'Books');
      expect(namer.propose('Birthday gift ideas for him', {}).name, 'Gift Ideas');
    });

    test('plural words still hit short keywords', () {
      expect(namer.propose('Best gyms in Jakarta', {}).name, 'Fitness');
    });

    test('"how to" does not pull a recipe into Learning', () {
      expect(namer.propose('How to make fried rice at home: easy recipe', {}).name, 'Recipes');
    });
  });
}
