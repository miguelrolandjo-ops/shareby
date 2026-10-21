import 'dart:io';

import 'package:shareby/data/platforms.dart';

/// Loads the rules file the app ships, so tests see the same platforms as the app.
void loadBundledRules() => PlatformRules.initBundled(File('assets/rules.json').readAsStringSync());
