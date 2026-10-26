import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/auth_service.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../helpers.dart';
import '../sheets/add_folder_sheet.dart';
import '../sheets/invite_sheet.dart';
import '../widgets/common.dart';
import 'group_detail_screen.dart';

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      body: SafeArea(bottom: false, child: state.signedIn ? _SharedBoards(state: state) : const _Locked()),
    );
  }
}

/// Starts sign-in from anywhere (Friends tab, Profile).
///
/// Asks the server which methods it offers, then opens Google's account picker. A development
/// server (ALLOW_DEV_AUTH=true) without Google set up gets the "any email" dialog instead.
Future<void> startSignIn(BuildContext context) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  var spinnerUp = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  void hideSpinner() {
    if (spinnerUp) {
      spinnerUp = false;
      navigator.pop();
    }
  }

  try {
    final options = await state.signInOptions();
    if (options.google) {
      await state.signInWithGoogle(options);
    } else if (options.dev) {
      hideSpinner();
      if (!context.mounted) return;
      final details = await showDialog<(String, String)>(context: context, builder: (_) => const _DevSignInDialog());
      if (details == null || !context.mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      spinnerUp = true;
      await state.signInDev(provider: 'google', email: details.$1, displayName: details.$2);
    } else {
      throw StateError("Sign-in isn't set up on the server yet.");
    }
    messenger.showSnackBar(const SnackBar(content: Text('Signed in. Your saves are backing up and sharing is on.')));
  } on SignInCancelled {
    // The user closed Google's picker.
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
  } finally {
    hideSpinner();
  }
}

class _Locked extends StatelessWidget {
  const _Locked();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
      children: [
        Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.lilacSoft, borderRadius: BorderRadius.circular(24)),
          child: const Icon(Icons.group_rounded, size: 38, color: AppColors.lilac),
        ),
        const SizedBox(height: 20),
        Text('Build boards with friends', style: headStyle(26)),
        const SizedBox(height: 10),
        const Text(
          'Sign in to plan trips, gift lists and weekend ideas together. '
          'Signing in also backs up everything you have saved on this phone.',
          style: TextStyle(color: AppColors.inkSoft, fontSize: 15, height: 1.45),
        ),
        const SizedBox(height: 28),
        OutlinedButton.icon(
          onPressed: () => startSignIn(context),
          icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF4285F4))),
          label: const Text('Continue with Google'),
        ),
        const SizedBox(height: 22),
        const InfoNote(
          icon: Icons.lock_outline_rounded,
          text: 'Your personal folders stay private. Only boards you create here are shared.',
        ),
      ],
    );
  }
}

/// Development servers only: sign in as any email (see AuthService).
class _DevSignInDialog extends StatefulWidget {
  const _DevSignInDialog();

  @override
  State<_DevSignInDialog> createState() => _DevSignInDialogState();
}

class _DevSignInDialogState extends State<_DevSignInDialog> {
  final _email = TextEditingController();
  final _name = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim());
    return AlertDialog(
      title: const Text('Sign in (development)'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('This server allows test sign-ins: enter any email to act as that account.',
            style: TextStyle(color: AppColors.inkSoft, fontSize: 13)),
        const SizedBox(height: 14),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'you@gmail.com'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Your name'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: valid
              ? () {
                  final email = _email.text.trim();
                  final name = _name.text.trim().isEmpty ? email.split('@').first : _name.text.trim();
                  Navigator.pop(context, (email, name));
                }
              : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _SharedBoards extends StatelessWidget {
  const _SharedBoards({required this.state});
  final AppState state;

  Future<void> _newBoard(BuildContext context) async {
    final board = await showAddFolderSheet(context, shared: true);
    if (board != null && context.mounted) await showInviteSheet(context, board);
  }

  @override
  Widget build(BuildContext context) {
    final boards = state.sharedFolders;
    return RefreshIndicator(
      onRefresh: state.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Text('Friends', style: headStyle(26)),
          const SizedBox(height: 6),
          SyncStatusLine(state: state),
          const SizedBox(height: 22),
          SectionTitle('Shared boards',
              trailing: TextButton.icon(
                onPressed: () => _newBoard(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New board'),
              )),
          if (boards.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                const Text('No shared boards yet', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Create one and invite friends by email.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.inkSoft)),
                const SizedBox(height: 14),
                FilledButton(onPressed: () => _newBoard(context), child: const Text('Create a board')),
              ]),
            )
          else
            for (final b in boards) _BoardCard(board: b, state: state),
          const SizedBox(height: 14),
          const InfoNote(
            text: 'Tags and auto-sorting are for your personal folders. '
                'Everything on a shared board is placed by whoever pins it.',
          ),
        ],
      ),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.board, required this.state});
  final Folder board;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final color = Color(board.color);
    final members = state.membersOf(board.id);
    final inside = state.itemsIn(board.id);
    final pins = inside.length;
    final pinnedCount = inside.where((i) => i.isPinned).length;
    final role = switch (board.myRole) { 'owner' => 'Owner', 'viewer' => 'Can view', _ => 'Can add' };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => GroupDetailScreen.open(context, board.id),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: FolderPalette.soft(color), borderRadius: BorderRadius.circular(14)),
                child: Text(board.emoji, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(board.name, style: headStyle(17)),
                  const SizedBox(height: 3),
                  Text('${pins == 1 ? '1 pin' : '$pins pins'}${pinnedCount > 0 ? ' · $pinnedCount pinned' : ''} · $role',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
                ]),
              ),
              AvatarStack(members: members, size: 28),
            ]),
          ),
        ),
      ),
    );
  }
}
