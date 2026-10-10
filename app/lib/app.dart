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
      home: const RootShell(),
    );
  }
}
