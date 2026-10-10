import 'package:flutter_test/flutter_test.dart';
import 'package:shareby/data/url_utils.dart';

void main() {
  test('extracts the link from share text and trims punctuation', () {
    expect(extractUrl('Check this out! https://www.instagram.com/reel/Cx12ab/?igsh=xyz.'),
        'https://www.instagram.com/reel/Cx12ab/?igsh=xyz');
    expect(extractUrl('no link here'), isNull);
    expect(extractUrl(null), isNull);
  });

  test('detects the source app', () {
    expect(detectSource('https://www.instagram.com/p/abc'), 'instagram');
    expect(detectSource('https://youtu.be/dQw4w9WgXcQ'), 'youtube');
    expect(detectSource('https://vt.tiktok.com/ZS123/'), 'tiktok');
    expect(detectSource('https://example.com'), 'web');
  });

  test('derives YouTube thumbnails for watch, short and shorts links', () {
    const thumb = 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg';
    expect(youtubeThumbnail('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), thumb);
    expect(youtubeThumbnail('https://youtu.be/dQw4w9WgXcQ'), thumb);
    expect(youtubeThumbnail('https://youtube.com/shorts/dQw4w9WgXcQ'), thumb);
    expect(youtubeThumbnail('https://www.instagram.com/reel/abc'), isNull);
  });

  test('uses the caption as the title, or a readable fallback', () {
    const url = 'https://www.tiktok.com/@a/video/1';
    expect(titleFromShareText('Resep sambal matah $url', url), 'Resep sambal matah');
    expect(titleFromShareText(url, url), 'Saved from tiktok.com');
  });
}
