import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'friends_screen.dart';

/// Opened from the avatar or settings icon on Home. Back returns to Home.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen()));

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    return '${d.inHours} h ago';
  }

  Future<void> _confirmSignOut(BuildContext context, AppState state) async {
    final pending = state.pendingChanges;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          '${pending > 0 ? '$pending change(s) have not synced yet and will stay on this phone only. ' : ''}'
          'Your personal saves stay on this phone. Shared boards are removed from it until you sign in again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) await state.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.user;
    final folders = state.personalFolders.length;
    final links = state.allItems.length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('Profile', style: headStyle(20)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Row(children: [
            InitialAvatar(name: user?.displayName ?? '?', seed: user?.userId, size: 64),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.displayName ?? 'Not signed in', style: headStyle(22)),
                const SizedBox(height: 2),
                Text(
                  user == null
                      ? 'Everything is saved on this phone'
                      : '${user.email} · ${user.provider == 'apple' ? 'Apple' : 'Google'}',
                  style: const TextStyle(color: AppColors.inkSoft),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Storage', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                '$links links in $folders folders${state.sharedFolders.isEmpty ? '' : ' + ${state.sharedFolders.length} shared boards'}',
                style: const TextStyle(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 12),
              SyncStatusLine(state: state),
              if (state.lastSyncedAt != null) ...[
                const SizedBox(height: 4),
                Text('Last synced ${_ago(state.lastSyncedAt!)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.inkFaint)),
              ],
              if (user != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: state.syncState == SyncState.syncing ? null : state.syncNow,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Sync now'),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          if (user == null) ...[
            const Text(
              'Sign in to back up your saves and share boards with friends. You can keep using Shareby without an account.',
              style: TextStyle(color: AppColors.inkSoft, height: 1.4),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => startSignIn(context, 'google'), child: const Text('Continue with Google')),
            const SizedBox(height: 10),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () => startSignIn(context, 'apple'),
              child: const Text('Continue with Apple'),
            ),
          ] else
            TextButton(
              onPressed: () => _confirmSignOut(context, state),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFC0392B)),
              child: const Text('Sign out'),
            ),
        ],
      ),
    );
  }
}
