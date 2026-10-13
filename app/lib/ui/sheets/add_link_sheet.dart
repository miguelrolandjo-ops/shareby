import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/title_fetcher.dart';
import '../../data/url_utils.dart';
import '../../state/app_state.dart';
import '../helpers.dart';
import 'add_folder_sheet.dart';

const _kAutoCreate = '__auto_create__';

/// Save a link: "sort it for me" (auto-suggest) or pick a collection now.
Future<void> showAddLinkSheet(
  BuildContext context, {
  String? initialUrl,
  String? initialTitle,
  String? folderId,
  bool fromShare = false,
}) {
  return showAppSheet<void>(
    context,
    (_) => _AddLinkSheet(
      initialUrl: initialUrl,
      initialTitle: initialTitle,
      folderId: folderId,
      fromShare: fromShare,
    ),
  );
}

class _AddLinkSheet extends StatefulWidget {
  const _AddLinkSheet({this.initialUrl, this.initialTitle, this.folderId, required this.fromShare});

  final String? initialUrl;
  final String? initialTitle;
  final String? folderId;
  final bool fromShare;

  @override
  State<_AddLinkSheet> createState() => _AddLinkSheetState();
}

class _AddLinkSheetState extends State<_AddLinkSheet> {
  late final _url = TextEditingController(text: widget.initialUrl ?? '');
  // A placeholder like "Saved from instagram.com" is never shown as if the user typed it.
  late final _title = TextEditingController(
    text: (widget.initialTitle == null || isFallbackTitle(widget.initialTitle!)) ? '' : widget.initialTitle,
  );
  bool _lookingUpTitle = false;
  late bool _sortLater = widget.folderId == null && !widget.fromShare;
  late String? _selected = widget.folderId;
  bool _saving = false;
  String? _urlError;

  @override
  void initState() {
    super.initState();
    final url = widget.initialUrl;
    if (url != null && _title.text.trim().isEmpty) _lookUpTitle(url);
  }

  /// Fills the Title field from the page in the background. Never blocks saving, and never
  /// overwrites something the user has typed in the meantime.
  Future<void> _lookUpTitle(String url) async {
    setState(() => _lookingUpTitle = true);
    final title = await fetchPageTitle(url);
    if (!mounted) return;
    setState(() {
      _lookingUpTitle = false;
      if (title != null && _title.text.trim().isEmpty) _title.text = title;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    super.dispose();
  }

  /// Picking a folder saves right away when the link came from another app's share
  /// sheet (one tap); inside the app it just selects, and "Save link" confirms.
  void _pick(String id) {
    setState(() => _selected = id);
    if (widget.fromShare) _save();
  }

  Future<void> _createYourself() async {
    final folder = await showAddFolderSheet(context);
    if (folder != null && mounted) _pick(folder.id);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final url = extractUrl(data?.text);
    if (!mounted) return;
    if (url == null) {
      setState(() => _urlError = 'Your clipboard has no link');
      return;
    }
    setState(() {
      _url.text = url;
      _urlError = null;
      if (_title.text.trim().isEmpty) _title.text = titleFromShareText(data?.text, url);
    });
  }

  Future<void> _save() async {
    final url = extractUrl(_url.text);
    if (url == null) {
      setState(() => _urlError = 'Enter a link that starts with http:// or https://');
      return;
    }
    if (!_sortLater && _selected == null) {
      toast(context, 'Pick a collection, or choose "Sort it for me"');
      return;
    }
    setState(() => _saving = true);
    final state = context.read<AppState>();
    try {
      var target = _sortLater ? null : _selected;
      if (target == _kAutoCreate) {
        target = (await state.autoFolderFor(url: url, title: _title.text)).id;
      }
      final item = await state.addLink(url: url, title: _title.text, folderId: target);
      if (!mounted) return;
      final where = item.folderId == null ? 'Uncategorized' : (state.folderById(item.folderId)?.name ?? 'your collection');
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
          content: Text(_sortLater ? 'Saved. Suggested: $where. Confirm it on Home' : 'Saved to $where')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final personal = state.personalFolders;
    final shared = state.sharedFolders.where((f) => f.canAddLinks).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SheetTitle(widget.fromShare ? 'Save to Shareby' : 'Save a link',
          subtitle: widget.fromShare ? 'Shared from another app' : null),
      const FieldLabel('Link'),
      TextField(
        controller: _url,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: InputDecoration(
          hintText: 'https://...',
          errorText: _urlError,
          suffixIcon: IconButton(
            tooltip: 'Paste',
            icon: const Icon(Icons.content_paste_rounded),
            onPressed: _paste,
          ),
        ),
        onChanged: (_) {
          if (_urlError != null) setState(() => _urlError = null);
        },
      ),
      const SizedBox(height: 8),
      const FieldLabel('Title'),
      TextField(
        controller: _title,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: _lookingUpTitle ? 'Looking up the title…' : 'What is this? (optional)'),
      ),
      const SizedBox(height: 16),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('Sort it for me'), icon: Icon(Icons.auto_awesome_rounded)),
          ButtonSegment(value: false, label: Text('Choose now'), icon: Icon(Icons.folder_outlined)),
        ],
        selected: {_sortLater},
        onSelectionChanged: (s) => setState(() => _sortLater = s.first),
        showSelectedIcon: false,
      ),
      const SizedBox(height: 12),
      if (_sortLater)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            "We'll suggest one of your personal folders and mark it New on Home. "
            "Confirm or change it there. If you don't, it's filed automatically after it's been shown twice.",
            style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.4),
          ),
        )
      else ...[
        ChoiceRow(
          selected: false,
          onTap: _createYourself,
          title: 'Create one yourself',
          subtitle: 'Name a new folder',
          leading: const EmojiBadge(emoji: '✏️', color: Color(FolderPalette.grey)),
        ),
        ChoiceRow(
          selected: _selected == _kAutoCreate,
          onTap: _saving ? () {} : () => _pick(_kAutoCreate),
          title: 'Auto create suggested folder',
          subtitle: 'We pick a general name that fits, or reuse one you have',
          leading: const EmojiBadge(emoji: '✨', color: Color(FolderPalette.amber)),
        ),
        for (final f in personal) _folderRow(f),
        _folderRow(Folder.uncategorized()),
        if (shared.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 8),
            child: Text('Shared boards', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
          ),
          for (final f in shared) _folderRow(f, subtitle: 'Shared with friends · no tags'),
        ],
      ],
      const SizedBox(height: 12),
      // From a share, tapping a folder already saves; only "sort it for me" needs the button.
      if (!widget.fromShare || _sortLater || _saving)
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save link'),
        ),
    ]);
  }

  Widget _folderRow(Folder f, {String? subtitle}) => ChoiceRow(
        selected: _selected == f.id,
        onTap: _saving ? () {} : () => _pick(f.id),
        title: f.name,
        subtitle: subtitle,
        leading: EmojiBadge(emoji: f.emoji, color: Color(f.color)),
      );
}
