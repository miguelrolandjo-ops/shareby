/// Picks a broad, friendly folder name for a save that fits none of the user's folders.
///
/// Names are deliberately general ("K-Pop", not "NewJeans"). Before proposing a new
/// folder, the user's existing folder names are checked: if a broader folder they
/// already have fits (e.g. they have "Music"), that one is reused instead.
library;

class FolderProposal {
  const FolderProposal({required this.name, required this.emoji, this.existingId});

  final String name;
  final String emoji;

  /// Set when an existing folder already covers this topic; no new folder is needed.
  final String? existingId;
}

class _Topic {
  const _Topic(this.name, this.emoji, this.keywords, [this.broader = const []]);

  final String name;
  final String emoji;
  final List<String> keywords;

  /// Existing folder names (lowercase stems) this topic would also fit under.
  final List<String> broader;
}

class FolderNamer {
  const FolderNamer();

  static const _topics = <_Topic>[
    _Topic('K-Pop', '🎤', [
      'kpop', 'k-pop', 'newjeans', 'blackpink', 'bts', 'aespa', 'twice', 'seventeen', 'stray kids',
      'illit', 'le sserafim', 'itzy', 'nct', 'enhypen', 'txt', 'exo', 'ive', 'jennie', 'lisa', 'idol',
      'comeback', 'fancam', 'bias',
    ], ['music', 'musik', 'idol']),
    _Topic('Music', '🎵', [
      'music', 'musik', 'song', 'lagu', 'lyrics', 'lirik', 'cover', 'concert', 'konser', 'album',
      'playlist', 'guitar', 'piano', 'band', 'singer', 'spotify',
    ]),
    _Topic('Recipes', '🍳', [
      'resep', 'recipe', 'masak', 'cooking', 'goreng', 'ayam', 'sambal', 'sambel', 'rendang', 'bumbu',
      'kue', 'bake', 'baking', 'nasi', 'mie', 'dessert', 'cheesecake', 'homemade',
    ], ['cook', 'resep', 'food', 'makan']),
    _Topic('Food Spots', '🍜', [
      'kuliner', 'restaurant', 'resto', 'warung', 'street food', 'mukbang', 'foodie', 'makanan enak',
      'review makanan', 'ramen', 'sushi', 'buffet',
    ], ['food', 'makan', 'kuliner']),
    _Topic('Cafes', '☕', [
      'cafe', 'kafe', 'kopi', 'coffee', 'latte', 'barista', 'nongkrong', 'wfc', 'brunch',
    ], ['food', 'kuliner']),
    _Topic('Travel', '🌴', [
      'travel', 'trip', 'itinerary', 'wisata', 'pantai', 'beach', 'hotel', 'villa', 'liburan',
      'staycation', 'gunung', 'hiking', 'trek', 'flight', 'bali', 'japan', 'jepang', 'korea trip',
      'backpacker', 'destinasi',
    ], ['trip', 'wisata', 'liburan']),
    _Topic('Fitness', '🏀', [
      'workout', 'gym', 'lari', 'running', 'yoga', 'fitness', 'olahraga', 'futsal', 'basket', 'pilates',
      'sepatu lari', 'cardio', 'stretching', 'diet',
    ], ['sport', 'olahraga', 'health']),
    _Topic('Fashion', '👗', [
      'outfit', 'ootd', 'fashion', 'style', 'thrift', 'sneakers', 'hijab', 'dress', 'streetwear',
    ], ['inspo', 'style']),
    _Topic('Beauty', '💄', [
      'makeup', 'skincare', 'beauty', 'serum', 'lipstick', 'tutorial makeup', 'haircare', 'hair',
    ], ['inspo', 'style']),
    _Topic('Tech', '💻', [
      'tech', 'gadget', 'iphone', 'android', 'laptop', 'coding', 'programming', 'software', 'app',
      'ai', 'chatgpt', 'review hp',
    ]),
    _Topic('Gaming', '🎮', [
      'game', 'gaming', 'gameplay', 'mobile legends', 'valorant', 'genshin', 'minecraft', 'roblox',
      'playstation', 'nintendo', 'esports',
    ]),
    _Topic('Movies & TV', '🎬', [
      'movie', 'film', 'drama', 'drakor', 'series', 'netflix', 'trailer', 'anime', 'review film',
      'episode', 'sinopsis',
    ]),
    _Topic('Home & DIY', '🏡', [
      'diy', 'decor', 'dekorasi', 'interior', 'rumah', 'furniture', 'organize', 'renovasi', 'garden',
      'tanaman', 'room tour',
    ], ['inspo', 'home']),
    _Topic('Money', '💰', [
      'invest', 'investasi', 'saham', 'crypto', 'finance', 'keuangan', 'budget', 'nabung', 'bisnis',
      'business', 'passive income', 'reksadana',
    ]),
    _Topic('Learning', '📚', [
      'tutorial', 'belajar', 'learn', 'course', 'tips', 'study', 'language', 'bahasa', 'english',
      'lesson', 'edukasi', 'productivity',
    ]),
    _Topic('Pets', '🐱', [
      'cat', 'kucing', 'dog', 'anjing', 'puppy', 'kitten', 'pet', 'hewan', 'anabul',
    ]),
    _Topic('Funny', '😂', [
      'funny', 'lucu', 'meme', 'prank', 'komedi', 'comedy', 'ngakak', 'humor',
    ]),
    _Topic('Art & Design', '🎨', [
      'art', 'drawing', 'sketch', 'illustration', 'design', 'desain', 'photography', 'fotografi',
      'aesthetic', 'moodboard', 'painting',
    ], ['inspo']),
  ];

  /// A fitting icon for a folder the user named themselves ("Music" -> 🎵), else a plain folder.
  String emojiFor(String name) {
    final n = name.trim().toLowerCase();
    for (final t in _topics) {
      if (t.name.toLowerCase() == n || t.keywords.contains(n) || t.broader.contains(n)) return t.emoji;
    }
    return '📁';
  }

  /// Proposes a folder for [text] (title + url), given the user's [existingNames]
  /// keyed by folder id. Never returns a name that already exists.
  FolderProposal propose(String text, Map<String, String> existingNames) {
    final lower = ' ${text.toLowerCase()} ';
    final tokens = lower.split(RegExp(r'[^a-z0-9\-]+')).toSet();

    _Topic? best;
    var bestScore = 0;
    for (final t in _topics) {
      var score = 0;
      for (final k in t.keywords) {
        // Short single words must match a whole token ("ai" must not hit "rain").
        final hit = (k.length <= 4 && !k.contains(' ')) ? tokens.contains(k) : lower.contains(k);
        if (hit) score += k.length >= 6 ? 2 : 1;
      }
      if (score > bestScore) {
        bestScore = score;
        best = t;
      }
    }

    if (best == null) return const FolderProposal(name: 'Inspo', emoji: '✨');

    // Reuse a folder the user already has that covers this topic or a broader one.
    final stems = [best.name.toLowerCase(), ...best.broader];
    for (final entry in existingNames.entries) {
      final n = entry.value.toLowerCase();
      if (stems.any((s) => n == s || n.contains(s))) {
        return FolderProposal(name: entry.value, emoji: best.emoji, existingId: entry.key);
      }
    }
    return FolderProposal(name: best.name, emoji: best.emoji);
  }
}
