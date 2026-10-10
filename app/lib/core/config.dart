/// Build-time configuration. Override with --dart-define, e.g.
///   flutter run --dart-define=API_BASE_URL=http://localhost:8080
class AppConfig {
  /// 10.0.2.2 is the host machine as seen from the Android emulator.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  /// Seed the example collections from the prototype on first launch.
  static const seedDemoData = bool.fromEnvironment('SEED_DEMO', defaultValue: true);

  /// Background sync cadence while the app is open (also syncs on resume and after edits).
  static const syncInterval = Duration(seconds: 45);

  /// A [New] item shown this many times without being confirmed is confirmed on the next showing.
  static const autoConfirmAfterViews = 2;

  /// Below this confidence an item goes to Uncategorized instead of a suggested folder.
  static const suggestionThreshold = 0.3;
}
