/// Helpers for turning shared text into a clean link, title and thumbnail.
library;

import 'platforms.dart';

final _urlPattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);
const _trailingJunk = '.,;:!?)\'"';

/// Finds the first http(s) link in [text]. Returns null if there is none, so
/// "paste from clipboard" only ever pastes a real link.
String? extractUrl(String? text) {
  if (text == null) return null;
  final match = _urlPattern.firstMatch(text);
  if (match == null) return null;
  var url = match.group(0)!;
  while (url.isNotEmpty && _trailingJunk.contains(url[url.length - 1])) {
    url = url.substring(0, url.length - 1);
  }
  return Uri.tryParse(url)?.hasAuthority == true ? url : null;
}

/// The platform key for [url] ('instagram', 'shopee'... or 'web'). See [PlatformRules].
String detectSource(String url) => PlatformRules.current.detect(url);

/// YouTube thumbnails can be derived from the link itself, so they work
/// without our server. Other sources get an Open Graph lookup during sync.
String? youtubeThumbnail(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  String? id;
  if (host == 'youtu.be') {
    id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
  } else if (host.endsWith('youtube.com')) {
    id = uri.queryParameters['v'];
    final segments = uri.pathSegments;
    if (id == null && segments.length >= 2 && (segments[0] == 'shorts' || segments[0] == 'embed')) {
      id = segments[1];
    }
  }
  if (id == null || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) return null;
  return 'https://img.youtube.com/vi/$id/hqdefault.jpg';
}

const _namedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'trade': '™',
  'copy': '©',
  'reg': '®',
  'hellip': '…',
  'ndash': '–',
  'mdash': '—',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
  'bull': '•',
  'middot': '·',
  'deg': '°',
  'hearts': '♥',
};

final _entity = RegExp(r'&(?:#[xX]([0-9a-fA-F]+)|#([0-9]+)|([a-zA-Z][a-zA-Z0-9]*));');

/// Turns HTML entities into the characters they stand for: `&#x2122;&#xfe0f;` -> "™️",
/// `&amp;` -> "&". Page titles often arrive this way, sometimes escaped twice.
/// Text without entities comes back unchanged.
String decodeHtmlEntities(String input) {
  var s = input;
  for (var pass = 0; pass < 2 && s.contains('&'); pass++) {
    final next = s.replaceAllMapped(_entity, (m) {
      final code = m.group(1) != null ? int.tryParse(m.group(1)!, radix: 16) : int.tryParse(m.group(2) ?? '');
      if (m.group(3) != null) return _namedEntities[m.group(3)!] ?? m.group(0)!;
      if (code == null || code <= 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) return m.group(0)!;
      return String.fromCharCode(code);
    });
    if (next == s) break;
    s = next;
  }
  return s;
}

String fallbackTitle(String url) {
  final host = (Uri.tryParse(url)?.host ?? '').replaceFirst(RegExp(r'^www\.'), '');
  return host.isEmpty ? url : 'Saved from $host';
}

bool isFallbackTitle(String title) => title.startsWith('Saved from ');

/// Share sheets usually send "caption text https://link" — keep the caption as the title,
/// without the platform's own wording ("Mia on Instagram: caption" -> "caption", by Mia).
CleanedTitle cleanedShareTitle(String? text, String url) {
  if (text == null) return CleanedTitle(fallbackTitle(url));
  final raw = decodeHtmlEntities(text.replaceAll(url, '')).replaceAll(RegExp(r'\s+'), ' ').trim();
  if (raw.length < 3) return CleanedTitle(fallbackTitle(url));
  final cleaned = PlatformRules.current.clean(url, raw);
  final title = cleaned.title.length < 3 ? raw : cleaned.title;
  return CleanedTitle(title.length > 120 ? '${title.substring(0, 117)}...' : title, author: cleaned.author);
}

String titleFromShareText(String? text, String url) => cleanedShareTitle(text, url).title;
