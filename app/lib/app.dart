import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'l10n/l10n.dart';
import 'state/app_state.dart';
import 'ui/root_shell.dart';
import 'ui/screens/onboarding_screen.dart';

class SharebyApp extends StatelessWidget {
  const SharebyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds everything when the language changes or onboarding finishes.
    final language = context.select<AppState, AppLanguage>((s) => s.language);
    final onboarding = context.select<AppState, bool>((s) => s.needsOnboarding);
    return MaterialApp(
      key: ValueKey(language),
      title: tr('Shareby'),
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: language.locale,
      supportedLocales: [for (final l in AppLanguage.values) l.locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: onboarding ? const OnboardingScreen() : const RootShell(),
      builder: (context, child) => _RefreshBar(child: child!),
    );
  }
}

/// A thin "Refreshing..." strip at the very top while a pull-to-refresh works in the
/// background. It never covers the list or blocks scrolling.
class _RefreshBar extends StatelessWidget {
  const _RefreshBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final refreshing = context.select<AppState, bool>((s) => s.refreshing);
    final top = MediaQuery.paddingOf(context).top;
    return Stack(children: [
      child,
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: IgnorePointer(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: !refreshing
                ? const SizedBox.shrink()
                : Material(
                    key: const ValueKey('refreshing'),
                    color: AppColors.brand,
                    child: Padding(
                      padding: EdgeInsets.only(top: top),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text(
                            tr('Refreshing...'),
                            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const LinearProgressIndicator(minHeight: 2, color: Colors.white, backgroundColor: Colors.transparent),
                      ]),
                    ),
                  ),
          ),
        ),
      ),
    ]);
  }
}
