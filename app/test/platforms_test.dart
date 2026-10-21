import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shareby/data/platforms.dart';
import 'package:shareby/data/thumbnail_store.dart';
import 'package:shareby/data/url_utils.dart';

import 'test_rules.dart';

void main() {
  setUpAll(loadBundledRules);

  test('detects many platforms, including short-link hosts and path-based ones', () {
    expect(detectSource('https://www.linkedin.com/posts/x'), 'linkedin');
    expect(detectSource('https://lnkd.in/abc'), 'linkedin');
    expect(detectSource('https://fb.watch/xyz'), 'facebook');
    expect(detectSource('https://x.com/a/status/1'), 'x');
    expect(detectSource('https://shp.ee/abc'), 'shopee');
    expect(detectSource('https://maps.app.goo.gl/abc'), 'maps');
    expect(detectSource('https://www.google.com/maps/place/Cafe'), 'maps');
    expect(detectSource('https://www.google.com/search?q=x'), 'web');
    expect(detectSource('https://example.com'), 'web');
  });

  test('strips the "Name on Instagram:" prefix in English and Indonesian, keeping the author', () {
    final p = PlatformRules.current;
    final en = p.clean('https://www.instagram.com/p/a', 'Mia on Instagram: "Nasi goreng 3 bahan"');
    expect(en.title, 'Nasi goreng 3 bahan');
    expect(en.author, 'Mia');
    final id = p.clean('https://www.instagram.com/p/a', 'Mia di Instagram: Resep sambal');
    expect(id.title, 'Resep sambal');
    expect(id.author, 'Mia');
  });

  test('titles no rule recognises come back untouched', () {
    final c = PlatformRules.current.clean('https://www.instagram.com/p/a', 'Just a caption');
    expect(c.title, 'Just a caption');
    expect(c.author, isNull);
  });

  test('cleans other platforms', () {
    final p = PlatformRules.current;
    expect(p.clean('https://youtu.be/dQw4w9WgXcQ', 'Cara masak - YouTube').title, 'Cara masak');
    expect(p.clean('https://shopee.co.id/x', 'Sepatu lari | Shopee Indonesia').title, 'Sepatu lari');
    final tt = p.clean('https://vt.tiktok.com/Z/', 'Resep | Dapur Mia | TikTok');
    expect((tt.title, tt.author), ('Resep', 'Dapur Mia'));
  });

  test('share text is cleaned and keeps the author', () {
    const url = 'https://www.instagram.com/reel/abc';
    final c = cleanedShareTitle('Mia on Instagram: "Rendang" $url', url);
    expect((c.title, c.author), ('Rendang', 'Mia'));
  });

  test('a newer valid rules document is adopted; broken or older ones are ignored', () {
    final before = PlatformRules.current.version;
    expect(PlatformRules.adopt('not json'), isFalse);
    expect(PlatformRules.adopt('{"version": ${before - 1}, "platforms": []}'), isFalse);
    const doc = '{"version": 99, "platforms": [{"key":"foo","name":"Foo","label":"FOO","color":"#112233",'
        '"hosts":["foo.example"],"titleRules":["(unclosed","^(?<title>.+) \\\\| Foo\$"]}]}';
    expect(PlatformRules.adopt(doc), isTrue);
    expect(detectSource('https://foo.example/a'), 'foo');
    expect(PlatformRules.current.clean('https://foo.example/a', 'Hi | Foo').title, 'Hi'); // bad rule skipped
    loadBundledRules(); // restore for other tests
    PlatformRules.current = PlatformRules.tryParse(File('assets/rules.json').readAsStringSync())!;
  });

  test('the bundled rules match the server copy', () {
    expect(File('assets/rules.json').readAsStringSync().replaceAll('\r\n', '\n'),
        File('../server/src/rules.json').readAsStringSync().replaceAll('\r\n', '\n'));
  });

  test('pictures are shrunk to at most 480px and re-encoded as JPEG', () {
    final big = img.Image(width: 1200, height: 600);
    final jpg = shrinkToJpeg(Uint8List.fromList(img.encodePng(big)))!;
    final out = img.decodeJpg(jpg)!;
    expect(out.width, 480);
    expect(out.height, 240);
    final small = shrinkToJpeg(Uint8List.fromList(img.encodePng(img.Image(width: 100, height: 80))))!;
    expect(img.decodeJpg(small)!.width, 100); // never enlarged
    expect(shrinkToJpeg(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
