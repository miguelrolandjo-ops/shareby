import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shareby/l10n/l10n.dart';
import 'package:shareby/l10n/strings_id.dart';

/// Every text wrapped in tr()/trn() in lib/ must have a Bahasa Indonesia entry, with the
/// same {placeholders}. Run with `flutter test test/l10n_test.dart`.
void main() {
  const lit = r'''(?:'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")''';
  const group = '($lit(?:\\s*$lit)*)';
  final trCall = RegExp('\\btr\\(\\s*$group');
  final trnCall = RegExp('\\btrn\\(\\s*[^,]+?,\\s*$group\\s*,\\s*$group', dotAll: true);
  final piece = RegExp(r'''^'((?:[^'\\]|\\.)*)'|^"((?:[^"\\]|\\.)*)"''');

  String value(String g) {
    final out = StringBuffer();
    var rest = g.trim();
    while (rest.isNotEmpty) {
      final m = piece.firstMatch(rest)!;
      out.write(m.group(1) ?? m.group(2));
      rest = rest.substring(m.end).trimLeft();
    }
    return out.toString().replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);
  }

  Set<String> keysInCode() {
    final keys = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('l10n')) continue;
      final src = f.readAsStringSync();
      for (final m in trCall.allMatches(src)) {
        keys.add(value(m.group(1)!));
      }
      for (final m in trnCall.allMatches(src)) {
        keys..add(value(m.group(1)!))..add(value(m.group(2)!));
      }
    }
    return keys;
  }

  Set<String> placeholders(String s) => RegExp(r'\{\w+\}').allMatches(s).map((m) => m.group(0)!).toSet();

  test('every tr() text has an Indonesian translation', () {
    final missing = keysInCode().where((k) => !idStrings.containsKey(k)).toList()..sort();
    expect(missing, isEmpty, reason: 'Add these to lib/l10n/strings_id.dart');
  });

  test('translations keep the same placeholders and are not empty', () {
    idStrings.forEach((en, id) {
      expect(id.trim(), isNotEmpty, reason: en);
      expect(placeholders(id), placeholders(en), reason: en);
    });
  });

  test('tr fills placeholders and falls back to English', () {
    L10n.current = AppLanguage.id;
    expect(tr('Keep in {folder}', {'folder': 'Resep'}), 'Simpan di Resep');
    expect(tr('Not in the table yet'), 'Not in the table yet');
    expect(trn(1, '1 link', '{n} links'), '1 link');
    expect(trn(3, '1 link', '{n} links'), '3 link');
    L10n.current = AppLanguage.en;
    expect(trn(3, '1 link', '{n} links'), '3 links');
  });
}
