import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config.dart';
import 'data/api_client.dart';
import 'data/auth_service.dart';
import 'data/local_db.dart';
import 'data/repository.dart';
import 'data/session_store.dart';
import 'data/share_intake.dart';
import 'data/sync_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local first: the database and session load from the device, no network needed.
  final db = await LocalDb.open();
  final sessions = SessionStore(await SharedPreferences.getInstance());
  final api = ApiClient(baseUrl: AppConfig.apiBaseUrl, tokenProvider: () => sessions.current?.token);

  final state = AppState(
    db: db,
    repo: Repository(db: db, sessions: sessions),
    sync: SyncService(db: db, api: api, sessions: sessions),
    auth: AuthService(api: api, store: sessions),
    sessions: sessions,
    api: api,
    shareIntake: ShareIntake(),
  );
  await state.init();

  runApp(ChangeNotifierProvider<AppState>.value(value: state, child: const SharebyApp()));
}
