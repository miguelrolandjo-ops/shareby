/// Helpers for turning shared text into a clean link, title and thumbnail.
library;

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

String detectSource(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host.endsWith('instagram.com')) return 'instagram';
  if (host.endsWith('youtube.com') || host == 'youtu.be') return 'youtube';
  if (host.endsWith('tiktok.com')) return 'tiktok';
  return 'web';
}

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

String fallbackTitle(String url) {
  final host = (Uri.tryParse(url)?.host ?? '').replaceFirst(RegExp(r'^www\.'), '');
  return host.isEmpty ? url : 'Saved from $host';
}

bool isFallbackTitle(String title) => title.startsWith('Saved from ');

/// Share sheets usually send "caption text https://link" — keep the caption as the title.
String titleFromShareText(String? text, String url) {
  if (text == null) return fallbackTitle(url);
  final cleaned = text.replaceAll(url, '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.length < 3) return fallbackTitle(url);
  return cleaned.length > 120 ? '${cleaned.substring(0, 117)}...' : cleaned;
}
