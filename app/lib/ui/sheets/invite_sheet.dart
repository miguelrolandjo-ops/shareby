import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../helpers.dart';
import '../widgets/common.dart';

Future<void> showInviteSheet(BuildContext context, Folder board) =>
    showAppSheet<void>(context, (_) => _InviteSheet(board: board));

class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.board});
  final Folder board;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _email = TextEditingController();
  String _role = 'editor';
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Enter an email address like name@gmail.com');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final status = await context.read<AppState>().invite(widget.board, email, _role);
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(status == 'added'
            ? '$email can now see ${widget.board.name}'
            : "Invite saved. $email gets access when they sign in to Shareby"),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = context.watch<AppState>().membersOf(widget.board.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SheetTitle('Invite to ${widget.board.name}',
          subtitle: 'They sign in with the Google or Apple account that uses this email.'),
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        autofocus: true,
        decoration: InputDecoration(hintText: 'friend@gmail.com', errorText: _error, errorMaxLines: 3),
      ),
      const SizedBox(height: 14),
      ChoiceRow(
        selected: _role == 'editor',
        onTap: () => setState(() => _role = 'editor'),
        title: 'Can add pins',
        subtitle: 'Saves links to this board and removes their own',
        leading: const Icon(Icons.edit_rounded, color: AppColors.brand),
      ),
      ChoiceRow(
        selected: _role == 'viewer',
        onTap: () => setState(() => _role = 'viewer'),
        title: 'Can view',
        subtitle: 'Sees everything, adds nothing',
        leading: const Icon(Icons.visibility_rounded, color: AppColors.brand),
      ),
      const SizedBox(height: 12),
      FilledButton(onPressed: _sending ? null : _send, child: Text(_sending ? 'Sending...' : 'Send invite')),
      if (members.isNotEmpty) ...[
        const SizedBox(height: 18),
        const FieldLabel('On this board'),
        for (final m in members)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: InitialAvatar(name: m.displayName, seed: m.userId, size: 36),
            title: Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: Text(switch (m.role) { 'owner' => 'Owner', 'viewer' => 'Can view', _ => 'Can add' },
                style: const TextStyle(color: AppColors.inkSoft, fontSize: 12.5)),
          ),
      ],
    ]);
  }
}
