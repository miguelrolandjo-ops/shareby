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
}
