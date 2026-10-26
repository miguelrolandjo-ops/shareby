import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/refactor_planner.dart';
import '../../data/refactor_undo.dart';
import '../../state/app_state.dart';
import '../helpers.dart';
import '../../l10n/l10n.dart';

/// Regroup every link into a new set of folders, in two steps:
///  1. Setup: optionally type some groups of your own first.
///  2. Review: a proposed grouping you can trim, group by group. Nothing changes until Apply.
/// Takes back the last refactor and tells the user how it went. Used by the Undo button
/// and by the snackbar's Undo action right after applying.
Future<bool> undoLastRefactor(AppState state, ScaffoldMessengerState messenger) async {
  try {
    final n = await state.undoRefactor();
    messenger
        .showSnackBar(SnackBar(content: Text(trn(n, 'Undone. 1 link is back where it was', 'Undone. {n} links are back where they were'))));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    return false;
  }
}

String _ago(DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return tr('just now');
  if (d.inMinutes < 60) return tr('{n} min ago', {'n': d.inMinutes});
  return trn(d.inHours, '1 hour ago', '{n} hours ago');
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
      toast(context, tr('You already added "{name}"', {'name': name}));
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
        content: Text(trn(moved, 'Regrouped 1 link', 'Regrouped {n} links')),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(label: tr('Undo'), onPressed: () => undoLastRefactor(state, messenger)),
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
          title: Text(plan == null ? tr('Refactor collections') : tr('Review new groups'), style: headStyle(20)),
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
          Text(tr('Last refactor'), style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            '${_ago(undo.at)} · ${trn(undo.linkCount, '1 link moved.', '{n} links moved.')} '
            '${tr('You can undo it for 24 hours.')}',
            style: const TextStyle(color: AppColors.inkSoft, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _undoing ? null : _undo,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.undo_rounded, size: 18),
            label: Text(_undoing ? 'Undoing...' : tr('Undo changes')),
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
            ? tr('You have no links to regroup yet.')
            : tr('Regroup all {count} of your links into new folders. You review the result before anything changes.', {'count': count}),
        style: const TextStyle(color: AppColors.inkSoft, height: 1.4),
      ),
      if (undo != null) _undoCard(undo),
      if (folders.isNotEmpty) ...[
        const SizedBox(height: 20),
        FieldLabel(tr('Your current folders')),
        Text(
          tr('Keep a folder to make it a group again. Uncheck one you no longer want, and its links are regrouped.'),
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
            subtitle: Text(trn(state.itemsIn(f.id).length, '1 link', '{n} links')),
          ),
      ],
      const SizedBox(height: 20),
      FieldLabel(tr('Add your own groups (optional)')),
      TextField(
        controller: _input,
        textCapitalization: TextCapitalization.words,
        maxLength: 80,
        decoration: InputDecoration(
          hintText: tr('e.g. Music'),
          counterText: '',
          suffixIcon: IconButton(tooltip: tr('Add group'), icon: const Icon(Icons.add_rounded), onPressed: _addSeed),
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
          label: Text(tr('Propose groups')),
        )
      else ...[
        FilledButton.icon(
          onPressed: count == 0 ? null : () => _propose(proposeRest: true),
          icon: const Icon(Icons.auto_awesome_rounded),
          label: Text(tr('Let AI propose the rest')),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: count == 0 ? null : () => _propose(proposeRest: false),
          child: Text(tr('Use only my groups')),
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
          Text(
            tr("Remove any group you don't want. Links in a removed group stay where they are, and old folders are only deleted once this empties them."),
            style: TextStyle(color: AppColors.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 14),
          if (plan.groups.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text(tr('No groups left. Go back to start again.'))),
            ),
          for (final g in plan.groups) _groupCard(g, items),
          if (staying > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                trn(staying, "1 link doesn't fit any group and will stay where it is.",
                    tr("{n} links don't fit any group and will stay where they are.")),
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
              child: Text(tr('Back')),
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

  /// Where a group came from, at a glance: orange-yellow = a folder you already have,
  /// green = proposed by Shareby, blue = typed by you.
  Widget _originTag(RefactorGroup g) {
    final (String label, Color bg, Color fg) = g.existing
        ? (tr('Current folder'), AppColors.amberSoft, AppColors.amberInk)
        : g.fromUser
            ? (
                tr('Yours'),
                FolderPalette.soft(const Color(FolderPalette.sky)),
                FolderPalette.deep(const Color(FolderPalette.sky))
              )
            : (tr('Proposed'), AppColors.brandSoft, AppColors.brand);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: fg)),
    );
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
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Text(trn(titles.length, '1 link', '{n} links'), style: const TextStyle(fontSize: 12.5)),
              const SizedBox(width: 8),
              _originTag(g),
            ]),
          ),
          trailing: IconButton(
            tooltip: tr('Remove group'),
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() => _plan!.groups.remove(g)),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (titles.isEmpty)
              Text(tr('No links matched this group yet.'), style: TextStyle(color: AppColors.inkFaint))
            else
              for (final t in titles.take(12))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• $t', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            if (titles.length > 12)
              Text(tr('and {titles} more', {'titles': titles.length - 12}), style: const TextStyle(color: AppColors.inkFaint)),
          ],
        ),
      ),
    );
  }
}
