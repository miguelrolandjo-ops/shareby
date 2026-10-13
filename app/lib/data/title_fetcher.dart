import 'dart:convert';

import 'package:http/http.dart' as http;

import 'url_utils.dart';

/// What a link's page says about itself.
class PagePreview {
  const PagePreview({this.title, this.image});

  final String? title;
  final String? image;

  bool get isEmpty => title == null && image == null;
}

// Attribute order varies between sites, so match the tag first, then read its attributes.
final _metaTag = RegExp(r'<meta\b[^>]*>', caseSensitive: false);
final _titleTag = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false);

String? _attr(String tag, String name) {
  final m = RegExp('$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')', caseSensitive: false).firstMatch(tag);
  return m == null ? null : (m.group(1) ?? m.group(2));
}

/// Login walls and bare site names say nothing about the link itself.
bool isGenericTitle(String t) {
  final l = t.toLowerCase().trim();
  return l.isEmpty ||
      l == 'instagram' ||
      l == 'tiktok' ||
      l == 'youtube' ||
      l.startsWith('login') ||
      l.startsWith('log in') ||
      l.contains('make your day') ||
      l.contains('instagram photos and videos');
}

String? _clean(String? s) {
  if (s == null) return null;
  final t = decodeHtmlEntities(s).replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty ? null : t;
}

String? _usableTitle(String? s) {
  final t = _clean(s);
  return (t == null || isGenericTitle(t)) ? null : t;
}

bool _isHost(Uri u, String domain) => u.host == domain || u.host.endsWith('.$domain');

/// Best-effort title and preview image for [url]. Returns an empty preview on any
/// failure or timeout, so callers can always carry on without it.
Future<PagePreview> fetchPagePreview(String url, {Duration timeout = const Duration(seconds: 4)}) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return const PagePreview();

  // TikTok publishes an open oEmbed endpoint that returns title + thumbnail as JSON.
  if (_isHost(uri, 'tiktok.com')) {
    final viaOembed = await _tiktokOembed(url, timeout);
    if (!viaOembed.isEmpty) return viaOembed;
  }

  try {
    final res = await http.get(uri, headers: {
      // Instagram and others only serve their Open Graph tags to link-preview crawlers.
      'User-Agent': _isHost(uri, 'instagram.com') || _isHost(uri, 'tiktok.com')
          ? 'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)'
          : 'Mozilla/5.0 (Linux; Android 14) Shareby',
      'Accept-Language': 'en,id;q=0.8',
    }).timeout(timeout);
    if (res.statusCode >= 400) return const PagePreview();
    // Tags live in <head>; skip decoding the rest of a large page.
    final bytes = res.bodyBytes.length > 131072 ? res.bodyBytes.sublist(0, 131072) : res.bodyBytes;
    final html = utf8.decode(bytes, allowMalformed: true);

    String? ogTitle, ogImage, twitterImage;
    for (final m in _metaTag.allMatches(html)) {
      final tag = m.group(0)!;
      final key = (_attr(tag, 'property') ?? _attr(tag, 'name'))?.toLowerCase();
      final content = _attr(tag, 'content');
      if (key == null || content == null) continue;
      if (key == 'og:title') ogTitle ??= content;
      if (key == 'og:image') ogImage ??= content;
      if (key == 'twitter:image') twitterImage ??= content;
    }
    final title = _usableTitle(ogTitle) ?? _usableTitle(_titleTag.firstMatch(html)?.group(1));
    final image = _clean(ogImage ?? twitterImage);
    return PagePreview(title: title, image: image != null && image.startsWith('http') ? image : null);
  } catch (_) {
    return const PagePreview();
  }
}

Future<PagePreview> _tiktokOembed(String url, Duration timeout) async {
  try {
    final res = await http
        .get(Uri.https('www.tiktok.com', '/oembed', {'url': url}))
        .timeout(timeout);
    if (res.statusCode != 200) return const PagePreview();
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final image = _clean(j['thumbnail_url'] as String?);
    return PagePreview(title: _usableTitle(j['title'] as String?), image: image);
  } catch (_) {
    return const PagePreview();
  }
}

/// Title only; see [fetchPagePreview].
Future<String?> fetchPageTitle(String url, {Duration timeout = const Duration(seconds: 4)}) async =>
    (await fetchPagePreview(url, timeout: timeout)).title;
