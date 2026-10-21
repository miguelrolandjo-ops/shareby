/// Which app a link comes from, and how that app words its titles.
///
/// The table lives in `assets/rules.json` (the same file the server serves at `/rules`).
/// The bundled copy always works offline; on pull-to-refresh the app fetches the server's
/// copy, so a platform changing its title format, or a new platform, needs no app release.
/// Rules are plain data (regexes with named groups `title` and `author`), never code, and a
/// rule that does not compile is skipped rather than trusted.
library;

import 'dart:convert';
import 'dart:ui' show Color;

/// What a platform's page title turns into once its boilerplate is removed.
class CleanedTitle {
  const CleanedTitle(this.title, {this.author});

  final String title;
  final String? author;
}

class SourcePlatform {
  SourcePlatform({
    required this.key,
    required this.name,
    required this.label,
    required this.color,
    required this.hosts,
    required List<String> titleRules,
  }) : _rules = _compileAll(titleRules);

  final String key;
  final String name;

  /// Short badge text, e.g. "IG".
  final String label;
  final Color color;

  /// "instagram.com" matches that host and its subdomains; "google.com/maps" also needs the path.
  final List<String> hosts;
  final List<RegExp> _rules;

  /// Patterns that do not compile are dropped.
  static List<RegExp> _compileAll(List<String> patterns) {
    final out = <RegExp>[];
    for (final p in patterns) {
      try {
        out.add(RegExp(p, caseSensitive: false, dotAll: true));
      } on FormatException {
        continue;
      }
    }
    return out;
  }

  bool matches(Uri uri) {
    final host = uri.host.toLowerCase();
    for (final h in hosts) {
      final slash = h.indexOf('/');
      final domain = slash < 0 ? h : h.substring(0, slash);
      if (host != domain && !host.endsWith('.$domain')) continue;
      if (slash < 0 || uri.path.toLowerCase().startsWith(h.substring(slash))) return true;
    }
    return false;
  }

  /// Removes this platform's wording from [raw] ("Mia on Instagram: nasi goreng" ->
  /// title "nasi goreng", author "Mia"). Text no rule recognises comes back untouched, so
  /// a platform changing its format costs a slightly longer title, never a wrong one.
  CleanedTitle clean(String raw) {
    final text = raw.trim();
    for (final rule in _rules) {
      final m = rule.firstMatch(text);
      if (m == null) continue;
      final title = _tidy(_group(m, 'title'));
      if (title == null) continue;
      return CleanedTitle(title, author: _tidy(_group(m, 'author')));
    }
    return CleanedTitle(text);
  }

  static String? _group(RegExpMatch m, String name) {
    try {
      return m.namedGroup(name);
    } on ArgumentError {
      return null; // this rule has no such group
    }
  }

  static const _quotes = '"\'“”‘’';

  static String? _tidy(String? s) {
    if (s == null) return null;
    var t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length >= 2 && _quotes.contains(t[0]) && _quotes.contains(t[t.length - 1])) {
      t = t.substring(1, t.length - 1).trim();
    }
    return t.isEmpty ? null : t;
  }
}

class PlatformRules {
  PlatformRules._(this.version, this.platforms);

  final int version;
  final List<SourcePlatform> platforms;

  static const web = 'web';

  /// The table in use. Starts as the bundled copy (see [initBundled]) and is replaced when a
  /// newer valid one arrives from the server.
  static PlatformRules current = PlatformRules._(0, const []);

  /// Parses a rules document; null when it is not a usable table.
  static PlatformRules? tryParse(String json) {
    try {
      final data = jsonDecode(json);
      if (data is! Map<String, dynamic>) return null;
      final version = data['version'];
      final list = data['platforms'];
      if (version is! int || list is! List) return null;
      final platforms = <SourcePlatform>[];
      final seen = <String>{};
      for (final p in list) {
        if (p is! Map<String, dynamic>) continue;
        final key = p['key'];
        final hosts = p['hosts'];
        final color = _color(p['color']);
        if (key is! String || !RegExp(r'^[a-z0-9_-]{1,32}$').hasMatch(key) || !seen.add(key)) continue;
        if (hosts is! List || hosts.isEmpty || color == null) continue;
        platforms.add(SourcePlatform(
          key: key,
          name: (p['name'] as String?) ?? key,
          label: (p['label'] as String?) ?? key.toUpperCase(),
          color: color,
          hosts: [for (final h in hosts) h.toString().toLowerCase()],
          titleRules: [
            for (final r in (p['titleRules'] as List? ?? const []))
              if (r is String && r.length <= 400) r,
          ],
        ));
      }
      return platforms.isEmpty ? null : PlatformRules._(version, platforms);
    } catch (_) {
      return null;
    }
  }

  static Color? _color(Object? hex) {
    if (hex is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
    return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  }

  /// Loads the bundled table. Called once at start-up with the asset's text.
  static void initBundled(String json) {
    final parsed = tryParse(json);
    if (parsed != null) current = parsed;
  }

  /// Switches to [json] when it is valid and newer than what is in use. Returns whether it did.
  static bool adopt(String json) {
    final parsed = tryParse(json);
    if (parsed == null || parsed.version < current.version) return false;
    final changed = parsed.version != current.version;
    current = parsed;
    return changed;
  }

  SourcePlatform? byKey(String key) {
    for (final p in platforms) {
      if (p.key == key) return p;
    }
    return null;
  }

  SourcePlatform? forUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    for (final p in platforms) {
      if (p.matches(uri)) return p;
    }
    return null;
  }

  /// The platform key for [url], or 'web'.
  String detect(String url) => forUrl(url)?.key ?? web;

  /// Cleans a title that came from [url]'s own page or share text.
  CleanedTitle clean(String url, String raw) => forUrl(url)?.clean(raw) ?? CleanedTitle(raw.trim());

  /// True for a title that is just the site's name.
  bool isSiteName(String title) {
    final l = title.toLowerCase().trim();
    return platforms.any((p) => p.name.toLowerCase() == l);
  }

  /// Plain hosts (no path part) of the platforms named in [keys].
  List<String> hostsOf(Set<String> keys) => [
        for (final p in platforms)
          if (keys.contains(p.key))
            for (final h in p.hosts)
              if (!h.contains('/')) h,
      ];
}
