import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

IconData sourceIcon(String source) => switch (source) {
      'youtube' => Icons.play_arrow_rounded,
      'instagram' => Icons.camera_alt_rounded,
      'tiktok' => Icons.music_note_rounded,
      _ => Icons.link_rounded,
    };

/// Card image. Uses the real thumbnail when there is one and it loads; otherwise
/// (no image, offline, blocked) a placeholder drawn from the folder color and source icon.
class LinkThumbnail extends StatelessWidget {
  const LinkThumbnail({super.key, required this.item, required this.color, this.size, this.radius = 12});

  final Item item;
  final Color color;
  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = _Placeholder(color: color, icon: sourceIcon(item.source));
    final url = item.thumbnailUrl;
    final Widget image = (url == null || url.isEmpty)
        ? placeholder
        : Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => placeholder,
            loadingBuilder: (context, child, progress) => progress == null ? child : placeholder,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: image),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.white, 0.6)!],
        ),
      ),
      child: Center(child: Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 22)),
    );
  }
}

class SourcePill extends StatelessWidget {
  const SourcePill(this.source, {super.key});

  final String source;

  @override
  Widget build(BuildContext context) {
    final (label, bg) = switch (source) {
      'youtube' => ('YT', const Color(0xFFD93025)),
      'instagram' => ('IG', const Color(0xFFD62976)),
      'tiktok' => ('TT', const Color(0xFF111111)),
      _ => ('WEB', AppColors.inkSoft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

/// The tick on the right of a link. 44px touch target around a smaller circle.
class DoneToggle extends StatelessWidget {
  const DoneToggle({super.key, required this.done, required this.onTap, this.size = 28, this.filledBackground = false});

  final bool done;
  final VoidCallback onTap;
  final double size;

  /// White fill when unticked, for use over a thumbnail.
  final bool filledBackground;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: done,
      button: true,
      label: done ? 'Done. Tap to mark as not done' : 'Mark as done',
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? AppColors.brand : (filledBackground ? Colors.white : Colors.transparent),
                border: Border.all(color: done ? AppColors.brand : AppColors.line, width: 2),
              ),
              child: done ? Icon(Icons.check_rounded, size: size * 0.62, color: Colors.white) : null,
            ),
          ),
        ),
      ),
    );
  }
}

class NewPill extends StatelessWidget {
  const NewPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.amberSoft, borderRadius: BorderRadius.circular(8)),
      child: const Text('New', style: TextStyle(color: AppColors.amberInk, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

Color avatarColor(String seed) {
  final hash = seed.codeUnits.fold<int>(7, (h, c) => (h * 31 + c) & 0x7fffffff);
  return Color(FolderPalette.all[hash % (FolderPalette.all.length - 1)]);
}

class InitialAvatar extends StatelessWidget {
  const InitialAvatar({super.key, required this.name, this.size = 32, this.seed});

  final String name;
  final double size;
  final String? seed;

  @override
  Widget build(BuildContext context) {
    final color = avatarColor(seed ?? name);
    final letter = name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: FolderPalette.soft(color),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Text(letter,
          style: TextStyle(color: FolderPalette.deep(color), fontWeight: FontWeight.w700, fontSize: size * 0.4)),
    );
  }
}

class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, required this.members, this.size = 28, this.max = 4});

  final List<Member> members;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = members.take(max).toList();
    final step = size * 0.68;
    return SizedBox(
      width: shown.isEmpty ? 0 : step * (shown.length - 1) + size,
      height: size,
      child: Stack(children: [
        for (var i = 0; i < shown.length; i++)
          Positioned(
            left: step * i,
            child: InitialAvatar(name: shown[i].displayName, seed: shown[i].userId, size: size),
          ),
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(child: Text(text, style: headStyle(19))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class InfoNote extends StatelessWidget {
  const InfoNote({super.key, required this.text, this.icon = Icons.info_outline_rounded});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: AppColors.brand),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.brandDark, height: 1.35))),
      ]),
    );
  }
}

/// Collection tile on Home.
class FolderCard extends StatelessWidget {
  const FolderCard({
    super.key,
    required this.folder,
    required this.count,
    required this.newCount,
    required this.onTap,
    this.doneCount = 0,
  });

  final Folder folder;
  final int count;
  final int newCount;
  final int doneCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(folder.color);
    return Material(
      color: FolderPalette.soft(color),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(12)),
                child: Text(folder.emoji, style: const TextStyle(fontSize: 20)),
              ),
              const Spacer(),
              if (newCount > 0) const NewPill(),
            ]),
            const Spacer(),
            Text(folder.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: headStyle(17, color: FolderPalette.deep(color))),
            const SizedBox(height: 2),
            Text('${count == 1 ? '1 link' : '$count links'}${doneCount > 0 ? ' · $doneCount done' : ''}',
                style: TextStyle(fontSize: 12.5, color: FolderPalette.deep(color).withValues(alpha: 0.8))),
          ]),
        ),
      ),
    );
  }
}

String syncLabel(AppState s) {
  switch (s.syncState) {
    case SyncState.localOnly:
      return 'Saved on this device only';
    case SyncState.syncing:
      return 'Syncing...';
    case SyncState.synced:
      return s.pendingChanges > 0 ? '${s.pendingChanges} change(s) waiting to sync' : 'Synced to your Shareby account';
    case SyncState.offline:
      return s.pendingChanges > 0
          ? "Offline. ${s.pendingChanges} change(s) will sync when you're back online"
          : "Offline. Your saves are safe on this device";
    case SyncState.error:
      return s.syncMessage ?? "Couldn't sync. Will retry shortly";
  }
}

class SyncStatusLine extends StatelessWidget {
  const SyncStatusLine({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (state.syncState) {
      SyncState.localOnly => (Icons.phone_android_rounded, AppColors.inkSoft),
      SyncState.syncing => (Icons.sync_rounded, AppColors.brand),
      SyncState.synced => (Icons.cloud_done_rounded, AppColors.brand),
      SyncState.offline => (Icons.cloud_off_rounded, AppColors.amberInk),
      SyncState.error => (Icons.error_outline_rounded, const Color(0xFFC0392B)),
    };
    return Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 6),
      Expanded(child: Text(syncLabel(state), style: TextStyle(fontSize: 12.5, color: color))),
    ]);
  }
}
