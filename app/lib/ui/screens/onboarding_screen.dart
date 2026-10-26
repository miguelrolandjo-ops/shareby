import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/regions.dart';
import '../../data/sources.dart';
import '../../l10n/l10n.dart';
import '../../state/app_state.dart';
import '../widgets/source_widgets.dart';

/// First run: where are you (sets the language and the usual sources), then which sources
/// you use. Both can be changed later in Profile.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  Region? _region;
  late AppLanguage _language = L10n.current;
  Set<String> _sources = {};
  int _step = 0;
  bool _saving = false;

  void _pickRegion(Region r) {
    setState(() {
      _region = r;
      _language = r.language;
      _sources = r.sources.toSet();
      L10n.current = r.language; // preview the screens in that language right away
    });
  }

  void _pickLanguage(AppLanguage l) => setState(() {
        _language = l;
        L10n.current = l;
      });

  Future<void> _finish() async {
    setState(() => _saving = true);
    await context.read<AppState>().completeOnboarding(region: _region!, language: _language, sources: _sources);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step = 0);
      },
      child: Scaffold(
        body: SafeArea(child: _step == 0 ? _regionStep() : _sourcesStep()),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(children: [
            if (_step == 1) ...[
              OutlinedButton(onPressed: () => setState(() => _step = 0), child: Text(tr('Back'))),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: FilledButton(
                onPressed: _region == null || _saving
                    ? null
                    : _step == 0
                        ? () => setState(() => _step = 1)
                        : _finish,
                child: Text(_step == 0 ? tr('Continue') : (_saving ? tr('Getting ready...') : tr('Start using Shareby'))),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _regionStep() {
    return ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 20), children: [
      Text(tr('Welcome to Shareby'), style: headStyle(28)),
      const SizedBox(height: 6),
      Text(
        tr('Where are you? We use it to pick your language and the apps people around you save from.'),
        style: const TextStyle(color: AppColors.inkSoft, height: 1.4),
      ),
      const SizedBox(height: 18),
      for (final r in regions)
        _OptionRow(
          leading: Text(r.flag, style: const TextStyle(fontSize: 24)),
          title: r.displayName,
          selected: _region?.code == r.code,
          onTap: () => _pickRegion(r),
        ),
      if (_region != null) ...[
        const SizedBox(height: 18),
        Text(tr('Language'), style: headStyle(16)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final l in AppLanguage.values)
            ChoiceChip(label: Text(l.nativeName), selected: _language == l, onSelected: (_) => _pickLanguage(l)),
        ]),
      ],
    ]);
  }

  Widget _sourcesStep() {
    final all = SourceCatalog.current.builtIns;
    final usual = _region!.sources.toSet();
    // The region's usual sources first, in its order; the rest alphabetically.
    final ordered = [
      for (final key in _region!.sources)
        ...all.where((s) => s.key == key),
      ...(all.where((s) => !usual.contains(s.key)).toList()..sort((a, b) => a.name.compareTo(b.name))),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 20), children: [
      Text(tr('Where do you save from?'), style: headStyle(28)),
      const SizedBox(height: 6),
      Text(
        tr('We switched on what people in {region} use most. These are the sources you can filter by. '
            'You can add your own sources later in Profile.', {'region': _region!.displayName}),
        style: const TextStyle(color: AppColors.inkSoft, height: 1.4),
      ),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in ordered)
          FilterChip(
            avatar: SourceBadge(info: s, size: 18),
            label: Text(s.name),
            selected: _sources.contains(s.key),
            onSelected: (on) => setState(() => on ? _sources.add(s.key) : _sources.remove(s.key)),
          ),
      ]),
    ]);
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.leading, required this.title, required this.selected, required this.onTap});

  final Widget leading;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.brandSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              leading,
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected ? AppColors.brand : AppColors.inkFaint),
            ]),
          ),
        ),
      ),
    );
  }
}
