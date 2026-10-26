/// Sources: where a link comes from (Instagram, Shopee, a news site...).
///
/// Built-in sources come from the platform rules (assets/rules.json). On top of those the
/// user decides which built-ins are switched on (what the source filter lists) and can add
/// their own sources from a name and an example link. Custom sources live on this device:
/// a link's stored `source` stays what the rules detect (usually "web" for those sites), and
/// the custom source is recognised from the link's address whenever it is shown, filtered
/// or sorted, so nothing conflicts when another device doesn't know the custom source.
library;

import 'dart:ui' show Color;

import '../l10n/l10n.dart';
import 'models.dart';
import 'platforms.dart';

class CustomSource {
  const CustomSource({required this.id, required this.name, required this.host, required this.exampleUrl});

  final String id;
  final String name;

  /// e.g. "kompas.com": matches that host and its subdomains.
  final String host;
  final String exampleUrl;

  String get key => 'custom-$id';

  bool matches(Uri uri) {
    final h = uri.host.toLowerCase();
    return h == host || h.endsWith('.$host');
  }

  /// Badge text: initials of a multi-word name ("Kompas TV" -> "KT"), else the first letters.
  String get label {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final text = words.length > 1 ? words.take(3).map((w) => w[0]).join() : name.trim();
    return text.length > 4 ? text.substring(0, 3).toUpperCase() : text.toUpperCase();
  }

  static const _palette = [
    0xFF6D5BD0, 0xFF2E86AB, 0xFFE07A5F, 0xFF3D9970, 0xFFB5651D, 0xFFC2185B, 0xFF00897B, 0xFF5D6D7E,
  ];

  Color get color => Color(_palette[host.codeUnits.fold<int>(0, (a, b) => a + b) % _palette.length]);

  Map<String, Object> toJson() => {'id': id, 'name': name, 'host': host, 'example_url': exampleUrl};

  static CustomSource? tryParse(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], host = j['host'], url = j['example_url'];
    if (id is! String || name is! String || host is! String || url is! String) return null;
    if (name.trim().isEmpty || host.isEmpty) return null;
    return CustomSource(id: id, name: name, host: host, exampleUrl: url);
  }

  /// The site an example link belongs to: lowercase, without "www." / "m.". Null if the text
  /// isn't a web address.
  static String? hostOf(String exampleUrl) {
    var text = exampleUrl.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return null;
    var host = uri.host.toLowerCase();
    for (final prefix in ['www.', 'm.', 'mobile.']) {
      if (host.startsWith(prefix)) host = host.substring(prefix.length);
    }
    if (!host.contains('.') || host.startsWith('.') || host.endsWith('.')) return null;
    return host;
  }
}

/// How a source looks in the app.
class SourceInfo {
  const SourceInfo({required this.key, required this.name, required this.label, required this.color, this.custom = false});

  final String key;
  final String name;
  final String label;
  final Color color;
  final bool custom;
}

class SourceCatalog {
  SourceCatalog({this.enabled, this.custom = const []});

  /// The catalog in use; replaced when the user changes their sources.
  static SourceCatalog current = SourceCatalog();

  /// Built-in source keys switched on; null = all.
  final Set<String>? enabled;
  final List<CustomSource> custom;

  static PlatformRules get _rules => PlatformRules.current;

  bool isEnabled(String key) => enabled == null || enabled!.contains(key);

  CustomSource? customFor(Uri uri) {
    for (final c in custom) {
      if (c.matches(uri)) return c;
    }
    return null;
  }

  /// The source to show and filter by for a link with [url] whose detected source is [stored].
  String keyFor(String url, String stored) {
    if (stored != PlatformRules.web && _rules.byKey(stored) != null) return stored;
    final uri = Uri.tryParse(url);
    final c = uri == null ? null : customFor(uri);
    return c?.key ?? stored;
  }

  String keyOf(Item item) => keyFor(item.url, item.source);

  /// The source of a link that hasn't been saved yet.
  String keyForUrl(String url) => keyFor(url, _rules.detect(url));

  /// Looks of a source; null for plain web links.
  SourceInfo? info(String key) {
    final p = _rules.byKey(key);
    if (p != null) return SourceInfo(key: p.key, name: p.name, label: p.label, color: p.color);
    for (final c in custom) {
      if (c.key == key) return SourceInfo(key: c.key, name: c.name, label: c.label, color: c.color, custom: true);
    }
    return null;
  }

  /// Every built-in source, switched-on ones first.
  List<SourceInfo> get builtIns => [
        for (final p in _rules.platforms) SourceInfo(key: p.key, name: p.name, label: p.label, color: p.color),
      ];

  /// What the source filter offers: switched-on built-ins, then custom sources.
  List<SourceInfo> get filterOptions => [
        for (final s in builtIns)
          if (isEnabled(s.key)) s,
        for (final c in custom) SourceInfo(key: c.key, name: c.name, label: c.label, color: c.color, custom: true),
      ];

  /// Words that name a source rather than a topic ("kompas" in "Kompas: banjir Jakarta").
  Set<String> get customWords => {
        for (final c in custom) ...[
          ...c.name.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((w) => w.length > 2),
          c.host.split('.').first,
        ],
      };

  /// Checks a new custom source. Returns an error to show, or null when it can be added.
  /// [builtInMatch] receives the built-in source that already covers the address, if any.
  String? validate(String name, String exampleUrl, {void Function(SourceInfo builtIn)? builtInMatch}) {
    final n = name.trim();
    if (n.isEmpty) return tr('Give the source a name.');
    if (n.length > 30) return tr('Keep the name under 30 characters.');
    final host = CustomSource.hostOf(exampleUrl);
    if (host == null) return tr('Paste a full link from the site, like https://example.com/article.');
    final uri = Uri.parse('https://$host/');
    final p = _rules.forUrl(uri.toString()) ?? _rules.forUrl('https://www.$host/');
    if (p != null) {
      builtInMatch?.call(SourceInfo(key: p.key, name: p.name, label: p.label, color: p.color));
      return tr('{name} is already supported. Switch it on in the list above.', {'name': p.name});
    }
    for (final c in custom) {
      if (c.host == host) return tr('You already added this site as {name}.', {'name': c.name});
      if (c.name.toLowerCase() == n.toLowerCase()) return tr('You already have a source called {name}.', {'name': c.name});
    }
    return null;
  }
}
