import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/thumbnail_store.dart';
import '../../state/app_state.dart';
import '../../data/sources.dart';
import '../../l10n/l10n.dart';

IconData sourceIcon(String source) => switch (source) {
      'youtube' || 'vimeo' || 'twitch' || 'bilibili' || 'netflix' => Icons.play_arrow_rounded,
      'instagram' || 'snapchat' => Icons.camera_alt_rounded,
      'tiktok' || 'spotify' || 'applemusic' || 'soundcloud' => Icons.music_note_rounded,
      'maps' => Icons.place_rounded,
      'github' => Icons.code_rounded,
      'shopee' || 'tokopedia' || 'lazada' || 'bukalapak' || 'amazon' => Icons.shopping_bag_rounded,
      'gofood' || 'grab' => Icons.restaurant_rounded,
      'traveloka' => Icons.flight_rounded,
      'medium' || 'substack' || 'quora' || 'notion' || 'gdocs' => Icons.article_rounded,
      'facebook' || 'x' || 'threads' || 'linkedin' || 'reddit' || 'pinterest' || 'bluesky' ||
      'telegram' || 'whatsapp' || 'naver' => Icons.forum_rounded,
      _ => Icons.link_rounded,
    };

/// Card image: the compressed picture kept on this device (see [ThumbnailStore]). It never
/// goes to the network, so cards look the same offline and after the site's picture expires.
/// While there is no stored picture yet (not fetched, or failed) it shows a placeholder drawn
/// from the folder color and the platform's icon.
class LinkThumbnail extends StatelessWidget {
  const LinkThumbnail({super.key, required this.item, required this.color, this.size, this.radius = 12});

  final Item item;
  final Color color;
  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = _Placeholder(color: color, icon: sourceIcon(item.source));
    final file = ThumbnailStore.instance?.fileFor(item.thumbPath);
    final Widget image = file == null
        ? placeholder
        : Image.file(
            file,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => placeholder,
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

/// A link's source badge. Pass `SourceCatalog.current.keyOf(item)` so custom sources show.
class SourcePill extends StatelessWidget {
  const SourcePill(this.source, {super.key});

  final String source;

  @override
  Widget build(BuildContext context) {
    final info = SourceCatalog.current.info(source);
    final (label, bg) = info == null ? ('WEB', AppColors.inkSoft) : (info.label, info.color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

/// A small pin mark for a pinned link.
class PinBadge extends StatelessWidget {
  const PinBadge({super.key, this.color = AppColors.brand, this.size = 15});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Icon(Icons.push_pin_rounded, size: size, color: color);
}

class NewPill extends StatelessWidget {
  const NewPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.amberSoft, borderRadius: BorderRadius.circular(8)),
      child: Text(tr('New'), style: TextStyle(color: AppColors.amberInk, fontSize: 11, fontWeight: FontWeight.w700)),
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
    this.pinnedCount = 0,
  });

  final Folder folder;
  final int count;
  final int newCount;
  final int pinnedCount;
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
            Text(
                [
                  trn(count, '1 link', '{n} links'),
                  if (pinnedCount > 0) tr('{n} pinned', {'n': pinnedCount}),
                ].join(' · '),
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
      return tr('Saved on this device only');
    case SyncState.syncing:
      return 'Syncing...';
    case SyncState.synced:
      return s.pendingChanges > 0 ? tr('{pendingChanges} change(s) waiting to sync', {'pendingChanges': s.pendingChanges}) : tr('Synced to your Shareby account');
    case SyncState.offline:
      return s.pendingChanges > 0
          ? tr("Offline. {pendingChanges} change(s) will sync when you're back online", {'pendingChanges': s.pendingChanges})
          : tr('Offline. Your saves are safe on this device');
    case SyncState.error:
      return s.syncMessage ?? tr("Couldn't sync. Will retry shortly");
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
