/// The app's languages: English (the source text) and Bahasa Indonesia.
///
/// Strings are written in English right where they are used and wrapped in [tr]:
///
///     Text(tr('Keep in {folder}', {'folder': name}))
///
/// English needs no table; the Indonesian table ([idStrings]) is keyed by the English
/// text. A string with no translation yet shows in English rather than breaking, and
/// `test/l10n_test.dart` fails until every [tr] text in the app has one.
library;

import 'dart:ui' show Locale;

import 'strings_id.dart';

enum AppLanguage {
  en('English'),
  id('Bahasa Indonesia');

  const AppLanguage(this.nativeName);

  /// The language's name in itself, for the picker.
  final String nativeName;

  Locale get locale => Locale(name);

  static AppLanguage fromCode(String? code) =>
      AppLanguage.values.firstWhere((l) => l.name == code, orElse: () => AppLanguage.en);
}

class L10n {
  L10n._();

  /// The language in use. Set at start-up from the saved settings and when the user changes
  /// it; the whole app rebuilds afterwards (see SharebyApp).
  static AppLanguage current = AppLanguage.en;
}

/// [en] in the current language, with `{name}` placeholders filled from [args].
String tr(String en, [Map<String, Object?> args = const {}]) {
  var s = L10n.current == AppLanguage.id ? (idStrings[en] ?? en) : en;
  if (args.isNotEmpty) {
    args.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  }
  return s;
}

/// Counted text: [one] when [n] is 1, else [other]. Both may use `{n}`. Indonesian has
/// no plural forms, so its table usually gives both the same translation.
String trn(int n, String one, String other, [Map<String, Object?> args = const {}]) =>
    tr(n == 1 ? one : other, {'n': n, ...args});
