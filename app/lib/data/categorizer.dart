/// Suggests which personal folder a new save belongs to.
///
/// This is a lightweight word-overlap scorer that runs instantly and offline. It knows no
/// vocabulary of its own: it matches the folder's name and learns from what the user files.
/// It sits behind the [Categorizer] interface so it can later be swapped for an
/// on-device sentence-embedding model (e.g. multilingual MiniLM via LiteRT) that
/// compares the save against each folder's name and confirmed items.
library;

class Suggestion {
  const Suggestion(this.folderId, this.confidence);

  /// null = not confident enough; the save goes to Uncategorized.
  final String? folderId;
  final double confidence;
}

class CategoryCandidate {
  const CategoryCandidate({required this.id, required this.name, this.examples = const []});

  final String id;
  final String name;

  /// Titles of items already confirmed in this folder.
  final List<String> examples;
}

abstract class Categorizer {
  Suggestion suggest(String text, List<CategoryCandidate> candidates);
}

class KeywordCategorizer implements Categorizer {
  const KeywordCategorizer({this.threshold = 0.3});

  final double threshold;

  /// Words that carry no topic: the platform ("on Instagram"), the media type, and filler.
  /// Without these, every Instagram link "matches" any folder that already holds one.
  static const Set<String> _stop = {
    // Indonesian filler
    'yang', 'dan', 'buat', 'untuk', 'cara', 'ini', 'itu', 'dari', 'aja', 'banget', 'dengan', 'atau', 'juga',
    'ada', 'bisa', 'kita', 'kamu', 'aku', 'saya', 'nya', 'gak', 'nggak', 'udah', 'lagi', 'jadi', 'pada',
    // English filler
    'the', 'and', 'for', 'with', 'you', 'your', 'how', 'one', 'are', 'was', 'but', 'not', 'this', 'that',
    'have', 'has', 'from', 'they', 'their', 'what', 'when', 'will', 'about', 'more', 'some', 'all', 'out',
    'its', 'our', 'can', 'get', 'just', 'like', 'love', 'best', 'new', 'top', 'most', 'very', 'than', 'then',
    'who', 'why', 'here', 'there', 'been', 'into', 'over', 'make', 'made', 'only', 'also', 'any', 'too',
    // platforms and media types
    'www', 'com', 'http', 'https', 'instagram', 'tiktok', 'youtube', 'facebook', 'twitter', 'threads',
    'reel', 'reels', 'video', 'videos', 'watch', 'shorts', 'post', 'posts', 'photo', 'photos', 'story',
    'link', 'saved', 'viral', 'fyp', 'foryou', 'explore',
  };

  /// Hosts whose link paths are random ids, not words.
  static const _socialHosts = ['instagram.com', 'tiktok.com', 'youtube.com', 'youtu.be', 'facebook.com', 'fb.watch'];
  static final _url = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

  /// Drops links before scoring. A link to a social post is just an id; any other link keeps
  /// its readable path words ("best-cafes-canggu").
  static String _withoutSocialUrls(String text) => text.replaceAllMapped(_url, (m) {
        final uri = Uri.tryParse(m.group(0)!);
        final host = uri?.host.toLowerCase() ?? '';
        if (uri == null || _socialHosts.any((h) => host == h || host.endsWith('.$h'))) return ' ';
        return ' ${uri.pathSegments.join(' ')} ';
      });

  static final _splitter = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static final _cjk = RegExp(r'[぀-ヿ㐀-鿿가-힯]');

  /// Lowercased words in any script. Chinese, Japanese and Korean are written without
  /// spaces, so those also contribute two-character pieces to match on.
  static Set<String> tokenize(String s) {
    final out = <String>{};
    for (final t in s.toLowerCase().split(_splitter)) {
      if (t.isEmpty || _stop.contains(t)) continue;
      if (_cjk.hasMatch(t)) {
        if (t.length < 2) continue;
        out.add(t);
        for (var i = 0; i + 2 <= t.length; i++) {
          out.add(t.substring(i, i + 2));
        }
      } else if (t.length > 2) {
        out.add(t);
      }
    }
    return out;
  }

  @override
  Suggestion suggest(String text, List<CategoryCandidate> candidates) {
    final tokens = tokenize(_withoutSocialUrls(text));
    if (tokens.isEmpty || candidates.isEmpty) return const Suggestion(null, 0);

    final profiles = [for (final c in candidates) _Profile(c)];
    // A word that shows up in several folders' examples says little about any one of them.
    final exampleFolders = <String, int>{};
    for (final p in profiles) {
      for (final t in p.exampleTokens) {
        exampleFolders[t] = (exampleFolders[t] ?? 0) + 1;
      }
    }

    String? bestId;
    var best = 0.0;
    var second = 0.0;
    for (final p in profiles) {
      final score = _score(tokens, p, exampleFolders);
      if (score > best) {
        second = best;
        best = score;
        bestId = p.candidate.id;
      } else if (score > second) {
        second = score;
      }
    }
    if (bestId == null || best == 0) return const Suggestion(null, 0);

    final strength = best / (best + 1.2); // saturates as more words match
    final margin = (best - second) / best; // 0 when two folders tie
    final confidence = (strength * (0.5 + 0.5 * margin)).clamp(0.0, 1.0).toDouble();
    return confidence >= threshold ? Suggestion(bestId, confidence) : Suggestion(null, confidence);
  }

  double _score(Set<String> tokens, _Profile p, Map<String, int> exampleFolders) {
    var score = 0.0;
    var strongHits = 0; // matches on the folder's name, or a word learned from its saves
    var exampleHits = 0;
    for (final t in tokens) {
      if (p.nameTokens.contains(t)) {
        score += 1.0;
        strongHits++;
      } else if (p.exampleTokens.contains(t)) {
        // Learned from what the user filed here: a word that recurs in this folder's titles
        // and in no other folder's is as good as a keyword ("mtg" after a few MTG saves).
        if ((p.exampleCounts[t] ?? 0) >= 2 && exampleFolders[t] == 1) {
          score += 0.8;
          strongHits++;
        } else {
          score += 0.4 / (exampleFolders[t] ?? 1);
          exampleHits++;
        }
      }
    }
    // One word shared with some old title is a coincidence, not a reason to file it here.
    if (strongHits == 0 && exampleHits < 2) return 0;
    return score;
  }
}

/// What one folder is known by: its name and the titles of what the user filed in it.
/// Nothing is built in, so it works in any language the user saves in.
class _Profile {
  _Profile(this.candidate) : nameTokens = KeywordCategorizer.tokenize(candidate.name) {
    for (final e in candidate.examples) {
      for (final t in KeywordCategorizer.tokenize(e)) {
        exampleCounts[t] = (exampleCounts[t] ?? 0) + 1;
      }
    }
  }

  final CategoryCandidate candidate;
  final Set<String> nameTokens;

  /// Each word in this folder's saved titles -> in how many of them it appears.
  final Map<String, int> exampleCounts = {};
  Set<String> get exampleTokens => exampleCounts.keys.toSet();
}
