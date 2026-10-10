import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import '../data/url_utils.dart';
import '../state/app_state.dart';
import 'sheets/add_link_sheet.dart';

/// Bottom sheet that grows with its content and stays above the keyboard.
Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: builder(ctx),
      ),
    ),
  );
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Turns exceptions into sentences a user can act on.
String friendlyError(Object error) {
  if (error is ApiUnreachable) return "Can't reach Shareby. Check your connection and try again.";
  if (error is ApiException) return error.message;
  if (error is StateError) return error.message;
  return 'Something went wrong. Please try again.';
}

Future<void> openLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  var ok = false;
  if (uri != null) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      ok = false;
    }
  }
  if (!ok && context.mounted) toast(context, "Couldn't open this link");
}

/// Ticks or unticks a link and offers Undo (which also restores who ticked it).
Future<void> toggleDone(BuildContext context, Item item) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  final nowDone = !item.isDone;
  try {
    await state.setDone(item, nowDone);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(nowDone ? 'Marked as done' : 'Moved back to to-do'),
      action: SnackBarAction(label: 'Undo', onPressed: () => state.restoreCompletion(item)),
    ));
}

/// "Done by Diana" / "Done by you" on shared boards.
String doneByLabel(Item item, String? myUserId) {
  if (item.completedBy != null && item.completedBy == myUserId) return 'Done by you';
  final name = item.completedByName;
  return name == null || name == 'You' ? 'Done by you' : 'Done by $name';
}

/// "Paste link": only opens the save sheet when the clipboard holds a real link.
Future<void> pasteFromClipboard(BuildContext context, {String? folderId}) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  if (!context.mounted) return;
  final url = extractUrl(data?.text);
  if (url == null) {
    toast(context, 'No link on your clipboard. Copy a link first, then tap Paste.');
    return;
  }
  await showAddLinkSheet(context,
      initialUrl: url, initialTitle: titleFromShareText(data?.text, url), folderId: folderId);
}

class SheetTitle extends StatelessWidget {
  const SheetTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: headStyle(22)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: const TextStyle(color: AppColors.inkSoft, fontSize: 13.5, height: 1.35)),
        ],
      ]),
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      );
}

/// Selectable row used in folder pickers (avoids the deprecated Radio APIs).
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.selected,
    required this.onTap,
    required this.title,
    required this.leading,
    this.subtitle,
  });

  final bool selected;
  final VoidCallback onTap;
  final String title;
  final String? subtitle;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.brandSoft : AppColors.greySoft,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (subtitle != null)
                    Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                ]),
              ),
              Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected ? AppColors.brand : AppColors.inkFaint),
            ]),
          ),
        ),
      ),
    );
  }
}

class EmojiBadge extends StatelessWidget {
  const EmojiBadge({super.key, required this.emoji, required this.color, this.size = 36});

  final String emoji;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: FolderPalette.soft(color), borderRadius: BorderRadius.circular(10)),
        child: Text(emoji, style: TextStyle(fontSize: size * 0.5)),
      );
}
