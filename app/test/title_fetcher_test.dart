import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shareby/data/models.dart';
import 'package:shareby/data/title_fetcher.dart';

import 'test_rules.dart';

Future<PagePreview> lookup(String url, Future<http.Response> Function(http.Request) handler) =>
    http.runWithClient(() => fetchPagePreview(url), () => MockClient(handler));

const page = '<html><head><title>Fallback</title>'
    '<meta property="og:title" content="Dunkin&#x2122;&#xfe0f; haul">'
    '<meta content="https://cdn.example.com/p.jpg" property="og:image"></head></html>';

void main() {
  setUpAll(loadBundledRules);

  const url = 'https://www.instagram.com/reel/abc/';

  group('a lookup counts as reached only when the site answered', () {
    test('a page with a title and image', () async {
      final p = await lookup(url, (_) async => http.Response(page, 200));
      expect(p.reached, isTrue);
      expect(p.title, 'Dunkin™️ haul');
      expect(p.image, 'https://cdn.example.com/p.jpg');
    });

    test('a page that answers with no title or image is still a final answer', () async {
      final p = await lookup(url, (_) async => http.Response('<html></html>', 200));
      expect(p.reached, isTrue);
      expect(p.isEmpty, isTrue);
    });

    test('a login-wall title is ignored, but the answer is final', () async {
      final p = await lookup(url, (_) async => http.Response('<title>Instagram</title>', 200));
      expect(p.reached, isTrue);
      expect(p.title, isNull);
    });

    test('404 is final: retrying will not help', () async {
      expect((await lookup(url, (_) async => http.Response('', 404))).reached, isTrue);
    });

    test('offline is not reached', () async {
      final p = await lookup(url, (_) async => throw const SocketException('Network is unreachable'));
      expect(p.reached, isFalse);
    });

    test('a server error or rate limit is not reached: try again later', () async {
      expect((await lookup(url, (_) async => http.Response('', 503))).reached, isFalse);
      expect((await lookup(url, (_) async => http.Response('', 429))).reached, isFalse);
    });

    test('TikTok uses its oEmbed answer', () async {
      final p = await lookup('https://www.tiktok.com/@a/video/1', (r) async {
        expect(r.url.path, '/oembed');
        return http.Response('{"title":"Cat video","thumbnail_url":"https://p16.tiktokcdn.com/t.jpg"}', 200);
      });
      expect(p.reached, isTrue);
      expect(p.title, 'Cat video');
      expect(p.image, 'https://p16.tiktokcdn.com/t.jpg');
    });
  });

  group('Item.fetched', () {
    Item item({bool fetched = false}) => Item(
          id: 'i',
          url: 'https://example.com',
          title: 'Saved from example.com',
          source: 'web',
          status: 'confirmed',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          fetched: fetched,
        );

    test('a new link is not fetched yet', () {
      expect(item().fetched, isFalse);
    });

    test('survives the database round trip and copyWith', () {
      final stored = Item.fromDb(item().copyWith(fetched: true).toDb(dirty: false));
      expect(stored.fetched, isTrue);
      expect(stored.copyWith(title: 'x').fetched, isTrue); // other edits keep it
    });

    test('is device-local: never sent to the server', () {
      expect(item(fetched: true).toApi().containsKey('fetched'), isFalse);
    });
  });
}
