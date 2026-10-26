import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/sources.dart';
import '../../l10n/l10n.dart';
import '../../state/app_state.dart';
import '../helpers.dart';
import '../widgets/source_widgets.dart';

/// Profile > Sources: switch built-in sources on or off, and add your own.
class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SourcesScreen()));

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final catalog = SourceCatalog.current;
    final builtIns = [...catalog.builtIns]
      ..sort((a, b) {
        final on = (catalog.isEnabled(b.key) ? 1 : 0) - (catalog.isEnabled(a.key) ? 1 : 0);
        return on != 0 ? on : a.name.compareTo(b.name);
      });
    return Scaffold(
      appBar: AppBar(title: Text(tr('Sources'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
        Text(
          tr('Sources are the apps and sites your links come from. Switched-on sources show up in the '
              'source filter, and sorting learns which folders each source usually goes to.'),
          style: const TextStyle(color: AppColors.inkSoft, height: 1.4),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: Text(tr('Your sources'), style: headStyle(17))),
          TextButton.icon(
            onPressed: () => showAddSourceDialog(context),
            icon: const Icon(Icons.add_rounded),
            label: Text(tr('Add')),
          ),
        ]),
        if (catalog.custom.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              tr('Save from a site Shareby doesn\'t know, like a news site or a local shop? Add it here '
                  'so you can filter by it.'),
              style: const TextStyle(color: AppColors.inkSoft, fontSize: 13, height: 1.35),
            ),
          ),
        for (final c in catalog.custom)
          _Row(
            badge: SourceBadge(info: catalog.info(c.key)!),
            title: c.name,
            subtitle: c.host,
            trailing: IconButton(
              tooltip: tr('Remove'),
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _confirmRemove(context, state, c),
            ),
          ),
        const SizedBox(height: 20),
        Text(tr('Supported sources'), style: headStyle(17)),
        const SizedBox(height: 6),
        for (final s in builtIns)
          _Row(
            badge: SourceBadge(info: s),
            title: s.name,
            trailing: Switch(
              value: catalog.isEnabled(s.key),
              onChanged: (on) => state.setSourceEnabled(s.key, on),
            ),
          ),
      ]),
    );
  }

  Future<void> _confirmRemove(BuildContext context, AppState state, CustomSource c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Remove {name}?', {'name': c.name})),
        content: Text(tr('Links from this site stay saved; they just show as web links again.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Remove'))),
        ],
      ),
    );
    if (ok == true) await state.removeCustomSource(c);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.badge, required this.title, this.subtitle, this.trailing});

  final Widget badge;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        badge,
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Name + example link. The example decides which site counts as this source.
Future<void> showAddSourceDialog(BuildContext context) async {
  final added = await showDialog<CustomSource>(context: context, builder: (_) => const _AddSourceDialog());
  if (added != null && context.mounted) toast(context, tr('{name} added', {'name': added.name}));
}

class _AddSourceDialog extends StatefulWidget {
  const _AddSourceDialog();

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  String? _error;
  SourceInfo? _builtIn;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final state = context.read<AppState>();
    SourceInfo? builtIn;
    final error = SourceCatalog.current.validate(_name.text, _url.text, builtInMatch: (b) => builtIn = b);
    if (error != null) {
      setState(() {
        _error = error;
        _builtIn = builtIn;
      });
      return;
    }
    final added = await state.addCustomSource(name: _name.text, exampleUrl: _url.text);
    if (mounted) Navigator.pop(context, added);
  }

  @override
  Widget build(BuildContext context) {
    final host = CustomSource.hostOf(_url.text);
    return AlertDialog(
      title: Text(tr('Add a source')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: tr('Name'), hintText: tr('e.g. Kompas')),
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(labelText: tr('Example link'), hintText: 'https://www.kompas.com/...'),
          onChanged: (_) => setState(() {
            _error = null;
            _builtIn = null;
          }),
        ),
        if (host != null && _error == null) ...[
          const SizedBox(height: 8),
          Text(tr('Links from {host} will count as this source.', {'host': host}),
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(fontSize: 12.5, color: Color(0xFFC0392B))),
        ],
      ]),
      actions: [
        if (_builtIn != null && !SourceCatalog.current.isEnabled(_builtIn!.key))
          TextButton(
            onPressed: () async {
              final name = _builtIn!.name;
              await context.read<AppState>().setSourceEnabled(_builtIn!.key, true);
              if (!context.mounted) return;
              Navigator.pop(context);
              toast(context, tr('{name} switched on', {'name': name}));
            },
            child: Text(tr('Switch it on')),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        FilledButton(onPressed: _add, child: Text(tr('Add'))),
      ],
    );
  }
}
