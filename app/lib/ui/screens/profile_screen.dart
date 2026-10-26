import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../l10n/l10n.dart';
import '../../state/app_state.dart';
import '../helpers.dart';
import '../widgets/common.dart';
import 'friends_screen.dart';
import 'region_language_screen.dart';
import 'sources_screen.dart';
import '../../data/sources.dart';

/// Opened from the avatar or settings icon on Home. Back returns to Home.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen()));

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return tr('just now');
    if (d.inMinutes < 60) return tr('{n} min ago', {'n': d.inMinutes});
    return trn(d.inHours, '1 hour ago', '{n} hours ago');
  }

  Future<void> _confirmSignOut(BuildContext context, AppState state) async {
    final pending = state.pendingChanges;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sign out?')),
        content: Text(
          (pending > 0
                  ? '${trn(pending, '1 change has not synced yet and will stay on this phone only.', '{n} changes have not synced yet and will stay on this phone only.')} '
                  : '') +
              tr('Your personal saves stay on this phone. Shared boards are removed from it until you sign in again.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sign out'))),
        ],
      ),
    );
    if (ok == true) await state.signOut();
  }

  /// Google Play requires in-app account deletion for apps with sign-in.
  Future<void> _confirmDeleteAccount(BuildContext context, AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Delete your account?')),
        content: Text(
          tr("Your backup, the boards you own and the pins you added to friends' boards are deleted from the server for good. Personal saves already on this phone stay here."),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFC0392B)),
            child: Text(tr('Delete account')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await state.deleteAccount();
      messenger.showSnackBar(SnackBar(content: Text(tr('Your account was deleted.'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
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
        title: Text(tr('Profile'), style: headStyle(20)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Row(children: [
            InitialAvatar(name: user?.displayName ?? '?', seed: user?.userId, size: 64),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.displayName ?? tr('Not signed in'), style: headStyle(22)),
                const SizedBox(height: 2),
                Text(
                  user == null
                      ? tr('Everything is saved on this phone')
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
              Text(tr('Storage'), style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                state.sharedFolders.isEmpty
                    ? tr('{links} links in {folders} folders', {'links': links, 'folders': folders})
                    : tr('{links} links in {folders} folders + {boards} shared boards',
                        {'links': links, 'folders': folders, 'boards': state.sharedFolders.length}),
                style: const TextStyle(color: AppColors.inkSoft),
              ),
              const SizedBox(height: 12),
              SyncStatusLine(state: state),
              if (state.lastSyncedAt != null) ...[
                const SizedBox(height: 4),
                Text(tr('Last synced {lastSyncedAt}', {'lastSyncedAt': _ago(state.lastSyncedAt!)}),
                    style: const TextStyle(fontSize: 12, color: AppColors.inkFaint)),
              ],
              if (user != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: state.syncState == SyncState.syncing ? null : state.syncNow,
                  icon: const Icon(Icons.sync_rounded),
                  label: Text(tr('Sync now')),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              ListTile(
                leading: Text(state.region.flag, style: const TextStyle(fontSize: 22)),
                title: Text(tr('Region & language')),
                subtitle: Text('${state.region.displayName} · ${state.language.nativeName}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => RegionLanguageScreen.open(context),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.apps_rounded, color: AppColors.brand),
                title: Text(tr('Sources')),
                subtitle: Text(tr('{on} switched on · {custom} of your own', {
                  'on': SourceCatalog.current.builtIns.where((s) => SourceCatalog.current.isEnabled(s.key)).length,
                  'custom': SourceCatalog.current.custom.length,
                })),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => SourcesScreen.open(context),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.image_search_rounded, color: AppColors.brand),
                title: Text(tr('Refresh all previews')),
                subtitle: Text(tr('Looks every link up again for its picture and title. Takes a while.')),
                enabled: !state.refreshing,
                onTap: () {
                  state.refetchAllPreviews();
                  toast(context, tr('Refreshing previews in the background'));
                },
              ),
            ]),
          ),
          const SizedBox(height: 16),
          if (user == null) ...[
            Text(
              tr('Sign in to back up your saves and share boards with friends. You can keep using Shareby without an account.'),
              style: TextStyle(color: AppColors.inkSoft, height: 1.4),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => startSignIn(context), child: Text(tr('Continue with Google'))),
          ] else ...[
            TextButton(
              onPressed: () => _confirmSignOut(context, state),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFC0392B)),
              child: Text(tr('Sign out')),
            ),
            TextButton(
              onPressed: () => _confirmDeleteAccount(context, state),
              style: TextButton.styleFrom(foregroundColor: AppColors.inkSoft),
              child: Text(tr('Delete account')),
            ),
          ],
        ],
      ),
    );
  }
}
