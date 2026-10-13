import 'categorizer.dart';
import 'folder_namer.dart';
import 'models.dart';

/// A group to start from: one the user typed, or a current folder they chose to keep.
class RefactorSeed {
  const RefactorSeed(this.name, {this.examples = const [], this.existingFolderId});

  final String name;

  /// Titles already in the folder, so matching learns from what the user filed there.
  final List<String> examples;

  /// Set for a kept folder; links already living in it stay put unless another group fits better.
  final String? existingFolderId;
}

/// One group in a proposed regrouping: a folder to create and the links to move into it.
class RefactorGroup {
  RefactorGroup({
    required this.name,
    required this.emoji,
    required this.itemIds,
    this.fromUser = false,
    this.existing = false,
  });

  String name;
  final String emoji;
  final List<String> itemIds;

  /// true = typed by the user or kept from a current folder, false = proposed by the app.
  final bool fromUser;

  /// true = this is a folder that already exists (kept by the user).
  final bool existing;
}

class RefactorPlan {
  RefactorPlan(this.groups, this.unassigned);

  final List<RefactorGroup> groups;

  /// Links no group claimed. They stay where they are.
  final List<String> unassigned;

  int get linkCount => groups.fold(0, (n, g) => n + g.itemIds.length);
}

/// Proposes a brand-new categorization for [items].
///
/// The user's own [seeds] come first: each link goes to the seed that fits it best.
/// With [proposeRest], links no seed claims are grouped under broad topic names
/// (the same naming used by "Auto create suggested folder").
class RefactorPlanner {
  const RefactorPlanner({this.categorizer = const KeywordCategorizer(), this.namer = const FolderNamer()});

  final Categorizer categorizer;
  final FolderNamer namer;

  RefactorPlan plan(List<Item> items, {List<RefactorSeed> seeds = const [], bool proposeRest = true}) {
    final cleanSeeds = <RefactorSeed>[];
    for (final s in seeds) {
      final name = s.name.trim();
      if (name.isEmpty || cleanSeeds.any((e) => e.name.toLowerCase() == name.toLowerCase())) continue;
      cleanSeeds.add(RefactorSeed(name, examples: s.examples, existingFolderId: s.existingFolderId));
    }

    final groups = <RefactorGroup>[
      for (final s in cleanSeeds)
        RefactorGroup(
          name: s.name,
          emoji: namer.emojiFor(s.name),
          itemIds: [],
          fromUser: true,
          existing: s.existingFolderId != null,
        ),
    ];
    final byName = {for (final g in groups) g.name.toLowerCase(): g};
    final keptByFolderId = {
      for (final s in cleanSeeds)
        if (s.existingFolderId != null) s.existingFolderId!: byName[s.name.toLowerCase()]!,
    };
    final candidates = [
      for (final s in cleanSeeds) CategoryCandidate(id: s.name.toLowerCase(), name: s.name, examples: s.examples),
    ];
    final seedNames = {for (final g in groups) g.name.toLowerCase(): g.name};
    final unassigned = <String>[];

    for (final item in items) {
      final text = '${item.title} ${item.url}';

      // 1. A seed the keyword scorer is confident about.
      final hit = candidates.isEmpty ? const Suggestion(null, 0) : categorizer.suggest(text, candidates);
      if (hit.folderId != null) {
        byName[hit.folderId]!.itemIds.add(item.id);
        continue;
      }

      // 2. The topic's broader seed (a "Music" seed claims K-Pop links), else a new broad group.
      final proposal = namer.propose(text, seedNames);
      if (proposal.existingId != null) {
        byName[proposal.existingId]!.itemIds.add(item.id);
      } else if (keptByFolderId[item.folderId] != null) {
        // It lives in a folder the user chose to keep and nothing fits it better: leave it be.
        keptByFolderId[item.folderId]!.itemIds.add(item.id);
      } else if (proposeRest) {
        final key = proposal.name.toLowerCase();
        byName
            .putIfAbsent(key, () {
              final g = RefactorGroup(name: proposal.name, emoji: proposal.emoji, itemIds: []);
              groups.add(g);
              return g;
            })
            .itemIds
            .add(item.id);
      } else {
        unassigned.add(item.id);
      }
    }

    // User groups stay visible even when empty (so they can be removed); proposals only if used.
    groups.removeWhere((g) => !g.fromUser && g.itemIds.isEmpty);
    groups.sort((a, b) {
      if (a.fromUser != b.fromUser) return a.fromUser ? -1 : 1;
      return b.itemIds.length.compareTo(a.itemIds.length);
    });
    return RefactorPlan(groups, unassigned);
  }
}
