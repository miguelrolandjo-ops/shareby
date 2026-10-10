import 'package:flutter/services.dart';

import 'models.dart';

/// Collects links saved from other apps' share sheets.
///
/// On Android, ShareReceiverActivity (native Kotlin) shows a small dialog over the
/// source app and stores the link in a native inbox without starting Flutter, so
/// sharing feels instant. The app drains that inbox on launch and on resume.
/// iOS needs a Share Extension target (see README); until then this returns nothing.
class ShareIntake {
  static const _channel = MethodChannel('shareby/share_intake');

  Future<List<PendingShare>> drain() async {
    try {
      final raw = await _channel.invokeListMethod<Object?>('drainPending') ?? const <Object?>[];
      return raw.whereType<Map<Object?, Object?>>().map((m) {
        final url = m['url'];
        if (url is! String || url.isEmpty) return null;
        final text = m['text'];
        return PendingShare(url: url, text: text is String ? text : null, choose: m['choose'] == true);
      }).whereType<PendingShare>().toList();
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }
}
