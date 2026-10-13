import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/refactor_planner.dart';
import '../../data/refactor_undo.dart';
import '../../state/app_state.dart';
import '../helpers.dart';

/// Regroup every link into a new set of folders, in two steps:
///  1. Setup: optionally type some groups of your own first.
///  2. Review: a proposed grouping you can trim, group by group. Nothing changes until Apply.
/// Takes back the last refactor and tells the user how it went. Used by the Undo button
/// and by the snackbar's Undo action right after applying.
Future<bool> undoLastRefactor(AppState state, ScaffoldMessengerState messenger) async {
  try {
    final n = await state.undoRefactor();
    messenger
        .showSnackBar(SnackBar(content: Text('Undone. $n ${n == 1 ? 'link is' : 'links are'} back where they were')));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    return false;
  }
}

String _ago(DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  final h = d.inHours;
  return '$h ${h == 1 ? 'hour' : 'hours'} ago';
}

class RefactorScreen extends StatefulWidget {
  const RefactorScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RefactorScreen()));

  @override
  State<RefactorScreen> createState() => _RefactorScreenState();
}

class _RefactorScreenState extends State<RefactorScreen> {
  final _input = TextEditingController();
  final List<String> _seeds = [];

  /// Current folders the user unchecked: they are not kept as groups, so their links get regrouped.
  final Set<String> _dropped = {};
  RefactorPlan? _plan;
  bool _applying = false;
  bool _undoing = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _addSeed() {
    final name = _input.text.trim();
    if (name.isEmpty) return;
    if (_seeds.any((s) => s.toLowerCase() == name.toLowerCase())) {
      toast(context, 'You already added "$name"');
      return;
    }
    setState(() {
      _seeds.add(name);
      _input.clear();
    });
  }

  /// Kept folders first (with what's in them, so matching learns from it), then typed groups.
  List<RefactorSeed> _allSeeds(AppState state) => [
        for (final f in state.personalFolders)
          if (!_dropped.contains(f.id))
            RefactorSeed(
              f.name,
              existingFolderId: f.id,
              examples: [for (final i in state.itemsIn(f.id).take(25)) i.title],
            ),
        for (final name in _seeds) RefactorSeed(name),
      ];

  void _propose({required bool proposeRest}) {
    final state = context.read<AppState>();
    setState(() =>
        _plan = const RefactorPlanner().plan(state.personalItems, seeds: _allSeeds(state), proposeRest: proposeRest));
  }

  Future<void> _apply() async {
    final plan = _plan!;
    setState(() => _applying = true);
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final moved = await state.applyRefactor(plan);
      messenger.showSnackBar(SnackBar(
        content: Text('Regrouped $moved ${moved == 1 ? 'link' : 'links'}'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(label: 'Undo', onPressed: () => undoLastRefactor(state, messenger)),
      ));
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _applying = false);
      toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return PopScope(
      canPop: plan == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _plan = null); // Back from Review returns to Setup
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          title: Text(plan == null ? 'Refactor collections' : 'Review new groups', style: headStyle(20)),
        ),
        body: plan == null ? _setup(context) : _review(context, plan),
      ),
    );
  }

  Future<void> _undo() async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _undoing = true);
    await undoLastRefactor(state, messenger);
    if (mounted) setState(() => _undoing = false);
  }

  Widget _undoCard(RefactorUndo undo) => Container(
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Last refactor', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            '${_ago(undo.at)} · ${undo.linkCount} ${undo.linkCount == 1 ? 'link' : 'links'} moved. '
            'You can undo it for 24 hours.',
            style: const TextStyle(color: AppColors.inkSoft, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _undoing ? null : _undo,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.undo_rounded, size: 18),
            label: Text(_undoing ? 'Undoing...' : 'Undo changes'),
          ),
        ]),
      );

  // ------------------------------------------------------------------ setup

  Widget _setup(BuildContext context) {
    final state = context.watch<AppState>();
    final count = state.personalItems.length;
    final folders = state.personalFolders;
    final undo = state.refactorUndo;
    final hasGroups = _seeds.isNotEmpty || folders.any((f) => !_dropped.contains(f.id));
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      Text(
        count == 0
            ? 'You have no links to regroup yet.'
            : 'Regroup all $count of your links into new folders. You review the result before anything changes.',
        style: const TextStyle(color: AppColors.inkSoft, height: 1.4),
      ),
      if (undo != null) _undoCard(undo),
      if (folders.isNotEmpty) ...[
        const SizedBox(height: 20),
        const FieldLabel('Your current folders'),
        const Text(
          'Keep a folder to make it a group again. Uncheck one you no longer want, '
          'and its links are regrouped.',
          style: TextStyle(color: AppColors.inkSoft, fontSize: 13, height: 1.35),
        ),
        const SizedBox(height: 6),
        for (final f in folders)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: !_dropped.contains(f.id),
            onChanged: (keep) => setState(() => keep == true ? _dropped.remove(f.id) : _dropped.add(f.id)),
            title: Text('${f.emoji}  ${f.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${state.itemsIn(f.id).length} links'),
          ),
      ],
      const SizedBox(height: 20),
      const FieldLabel('Add your own groups (optional)'),
      TextField(
        controller: _input,
        textCapitalization: TextCapitalization.words,
        maxLength: 80,
        decoration: InputDecoration(
          hintText: 'e.g. Music',
          counterText: '',
          suffixIcon: IconButton(tooltip: 'Add group', icon: const Icon(Icons.add_rounded), onPressed: _addSeed),
        ),
        onSubmitted: (_) => _addSeed(),
      ),
      if (_seeds.isNotEmpty) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in _seeds)
            InputChip(
              label: Text(s),
              onDeleted: () => setState(() => _seeds.remove(s)),
              backgroundColor: AppColors.surface,
              side: const BorderSide(color: AppColors.line),
            ),
        ]),
      ],
      const SizedBox(height: 28),
      if (!hasGroups)
        FilledButton.icon(
          onPressed: count == 0 ? null : () => _propose(proposeRest: true),
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('Propose groups'),
        )
      else ...[
        FilledButton.icon(
          onPressed: count == 0 ? null : () => _propose(proposeRest: true),
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('Let AI propose the rest'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: count == 0 ? null : () => _propose(proposeRest: false),
          child: const Text('Use only my groups'),
        ),
      ],
    ]);
  }

  // ----------------------------------------------------------------- review

  Widget _review(BuildContext context, RefactorPlan plan) {
    final items = {for (final i in context.watch<AppState>().personalItems) i.id: i};
    final staying = plan.unassigned.length;
    final movable = plan.groups.where((g) => g.itemIds.isNotEmpty).toList();
    final links = movable.fold<int>(0, (n, g) => n + g.itemIds.length);

    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), children: [
          const Text(
            'Remove any group you don\'t want. Links in a removed group stay where they are, '
            'and old folders are only deleted once this empties them.',
            style: TextStyle(color: AppColors.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 14),
          if (plan.groups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('No groups left. Go back to start again.')),
            ),
          for (final g in plan.groups) _groupCard(g, items),
          if (staying > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '$staying ${staying == 1 ? 'link doesn\'t' : 'links don\'t'} fit any group and will stay where '
                '${staying == 1 ? 'it is' : 'they are'}.',
                style: const TextStyle(color: AppColors.inkFaint, height: 1.4, fontSize: 13),
              ),
            ),
        ]),
      ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(children: [
            // The theme's buttons have an unbounded minimum width; give both a finite one so
            // they share the row instead of pushing Apply off screen.
            OutlinedButton(
              onPressed: _applying ? null : () => setState(() => _plan = null),
              style: OutlinedButton.styleFrom(minimumSize: const Size(88, 52)),
              child: const Text('Back'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                onPressed: _applying || links == 0 ? null : _apply,
                child: Text(
                  _applying ? 'Applying...' : 'Apply ($links ${links == 1 ? 'link' : 'links'})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _groupCard(RefactorGroup g, Map<String, Item> items) {
    final titles = [
      for (final id in g.itemIds)
        if (items[id] != null) items[id]!.title
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Text(g.emoji, style: const TextStyle(fontSize: 22)),
          title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            '${titles.length} ${titles.length == 1 ? 'link' : 'links'}${g.existing ? ' · current folder' : g.fromUser ? ' · yours' : ' · proposed'}',
            style: const TextStyle(fontSize: 12.5),
          ),
          trailing: IconButton(
            tooltip: 'Remove group',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() => _plan!.groups.remove(g)),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (titles.isEmpty)
              const Text('No links matched this group yet.', style: TextStyle(color: AppColors.inkFaint))
            else
              for (final t in titles.take(12))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• $t', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            if (titles.length > 12)
              Text('and ${titles.length - 12} more', style: const TextStyle(color: AppColors.inkFaint)),
          ],
        ),
      ),
    );
  }
}
