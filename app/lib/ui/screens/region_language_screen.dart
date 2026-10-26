import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/regions.dart';
import '../../l10n/l10n.dart';
import '../../state/app_state.dart';

/// Profile > Region & language.
class RegionLanguageScreen extends StatelessWidget {
  const RegionLanguageScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RegionLanguageScreen()));

  Future<void> _pickRegion(BuildContext context, AppState state, Region r) async {
    if (r.code == state.region.code) return;
    final reset = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Switch to {region}?', {'region': r.displayName})),
        content: Text(tr('Also switch on the sources people in {region} use most?', {'region': r.displayName})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Keep my sources'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Yes, switch them on'))),
        ],
      ),
    );
    if (reset == null) return;
    await state.setRegion(r, resetSources: reset);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Region & language'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
        Text(tr('Language'), style: headStyle(17)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final l in AppLanguage.values)
            ChoiceChip(
              label: Text(l.nativeName),
              selected: state.language == l,
              onSelected: (_) => state.setLanguage(l),
            ),
        ]),
        const SizedBox(height: 24),
        Text(tr('Region'), style: headStyle(17)),
        const SizedBox(height: 4),
        Text(tr('Decides which sources are switched on by default.'),
            style: const TextStyle(color: AppColors.inkSoft, fontSize: 13)),
        const SizedBox(height: 8),
        for (final r in regions)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Text(r.flag, style: const TextStyle(fontSize: 22)),
            title: Text(r.displayName),
            trailing: r.code == state.region.code ? const Icon(Icons.check_rounded, color: AppColors.brand) : null,
            onTap: () => _pickRegion(context, state, r),
          ),
      ]),
    );
  }
}
