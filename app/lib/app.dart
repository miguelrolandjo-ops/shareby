import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'ui/root_shell.dart';

class SharebyApp extends StatelessWidget {
  const SharebyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shareby',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // The interface is written in English; pin it so system-provided labels (tooltips,
      // text selection, date pickers) stay English on phones set to another language.
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      home: const RootShell(),
    );
  }
}
