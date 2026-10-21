import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../helpers.dart';

/// Edit a saved link's title and address. Changing the address looks the page up again.
Future<void> showEditLinkSheet(BuildContext context, Item item) =>
    showAppSheet<void>(context, (_) => _EditLinkSheet(item: item));

class _EditLinkSheet extends StatefulWidget {
  const _EditLinkSheet({required this.item});

  final Item item;

  @override
  State<_EditLinkSheet> createState() => _EditLinkSheetState();
}

class _EditLinkSheetState extends State<_EditLinkSheet> {
  late final _url = TextEditingController(text: widget.item.url);
  late final _title = TextEditingController(text: widget.item.title);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final state = context.read<AppState>();
    try {
      await state.updateLink(widget.item, title: _title.text, url: _url.text);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      const SheetTitle('Edit link', subtitle: 'Change the title or the address.'),
      const FieldLabel('Link'),
      TextField(
        controller: _url,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: InputDecoration(hintText: 'https://...', errorText: _error),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      ),
      const SizedBox(height: 8),
      const FieldLabel('Title'),
      TextField(
        controller: _title,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'What is this?'),
        onSubmitted: (_) => _saving ? null : _save(),
      ),
      const SizedBox(height: 16),
      FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Save changes')),
    ]);
  }
}
