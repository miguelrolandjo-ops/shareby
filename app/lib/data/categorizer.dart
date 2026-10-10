/// Suggests which personal folder a new save belongs to.
///
/// This is a lightweight keyword/overlap scorer that runs instantly and offline.
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

  /// Folder-name stems mapped to words that usually belong there (Indonesian + English).
  static const Map<String, List<String>> _hints = {
    'cook': ['resep', 'masak', 'goreng', 'ayam', 'sambel', 'sambal', 'geprek', 'pedas', 'rendang',
      'bumbu', 'cheesecake', 'kue', 'recipe', 'bake', 'nasi', 'mie', 'dessert', 'makanan'],
    'resep': ['masak', 'goreng', 'ayam', 'sambel', 'bumbu', 'recipe', 'kue'],
    'food': ['makan', 'kuliner', 'restaurant', 'resto', 'warung', 'street', 'enak'],
    'trip': ['trip', 'itinerary', 'wisata', 'pantai', 'beach', 'hotel', 'villa', 'spot', 'travel',
      'sunrise', 'sunset', 'gunung', 'trek', 'jalan', 'liburan', 'staycation'],
    'travel': ['trip', 'itinerary', 'wisata', 'hotel', 'flight', 'liburan'],
    'cafe': ['cafe', 'kafe', 'kopi', 'coffee', 'latte', 'nongkrong', 'wfc', 'brunch', 'dessert'],
    'sport': ['workout', 'lari', 'running', 'gym', 'sepatu', 'olahraga', 'fitness', 'yoga', 'futsal', 'basket'],
    'inspo': ['moodboard', 'aesthetic', 'outfit', 'decor', 'dekorasi', 'ideas', 'ide', 'diy'],
  };

  static const Set<String> _stop = {
    'yang', 'dan', 'buat', 'untuk', 'cara', 'ini', 'itu', 'dari', 'aja', 'banget', 'the', 'and',
    'for', 'with', 'you', 'your', 'how', 'www', 'com', 'http', 'https', 'reel', 'video', 'watch',
  };

  static Set<String> tokenize(String s) => s
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.length > 2 && !_stop.contains(t))
      .toSet();

  @override
  Suggestion suggest(String text, List<CategoryCandidate> candidates) {
    final tokens = tokenize(text);
    if (tokens.isEmpty || candidates.isEmpty) return const Suggestion(null, 0);

    String? bestId;
    var best = 0.0;
    var second = 0.0;
    for (final c in candidates) {
      final score = _score(tokens, c);
      if (score > best) {
        second = best;
        best = score;
        bestId = c.id;
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

  double _score(Set<String> tokens, CategoryCandidate c) {
    final nameTokens = tokenize(c.name);
    final hintWords = <String>{};
    for (final entry in _hints.entries) {
      if (nameTokens.any((t) => t.startsWith(entry.key) || entry.key.startsWith(t))) {
        hintWords.addAll(entry.value);
      }
    }
    final exampleTokens = <String>{for (final e in c.examples) ...tokenize(e)};

    var score = 0.0;
    for (final t in tokens) {
      if (nameTokens.contains(t)) {
        score += 1.0;
      } else if (hintWords.contains(t)) {
        score += 0.8;
      } else if (exampleTokens.contains(t)) {
        score += 0.4;
      }
    }
    return score;
  }
}
