import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config.dart';
import 'data/api_client.dart';
import 'data/auth_service.dart';
import 'data/local_db.dart';
import 'data/platforms.dart';
import 'data/repository.dart';
import 'data/session_store.dart';
import 'data/settings_store.dart';
import 'data/share_intake.dart';
import 'data/sync_service.dart';
import 'data/thumbnail_store.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local first: the database and session load from the device, no network needed.
  final db = await LocalDb.open();
  final prefs = await SharedPreferences.getInstance();
  final sessions = await SessionStore.open(prefs);
  final settings = SettingsStore(prefs)..apply(); // language and sources before the first frame
  final api = ApiClient(baseUrl: AppConfig.apiBaseUrl, tokenProvider: () => sessions.current?.token);

  // Platform + title rules: the copy shipped in the app, then the newest one fetched earlier.
  PlatformRules.initBundled(await rootBundle.loadString('assets/rules.json'));
  final cachedRules = sessions.rulesRaw;
  if (cachedRules != null) PlatformRules.adopt(cachedRules);
  final thumbs = await ThumbnailStore.open();

  final state = AppState(
    db: db,
    repo: Repository(db: db, sessions: sessions, thumbs: thumbs),
    sync: SyncService(db: db, api: api, sessions: sessions),
    auth: AuthService(api: api, store: sessions),
    sessions: sessions,
    api: api,
    shareIntake: ShareIntake(),
    settings: settings,
  );
  await state.init();

  runApp(ChangeNotifierProvider<AppState>.value(value: state, child: const SharebyApp()));
}
