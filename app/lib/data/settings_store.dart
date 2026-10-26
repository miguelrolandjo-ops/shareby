import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import 'regions.dart';
import 'sources.dart';

/// The user's own choices, kept on this device: region, language and sources.
class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const _regionKey = 'region_v1';
  // Also read by the Android share dialog (FlutterSharedPreferences, "flutter." prefix).
  static const _languageKey = 'app_language';
  static const _enabledKey = 'sources_enabled_v1';
  static const _customKey = 'sources_custom_v1';

  /// Null until the user has been through onboarding.
  String? get regionCode => _prefs.getString(_regionKey);
  bool get onboarded => regionCode != null;
  Region get region => regionByCode(regionCode);

  AppLanguage get language => AppLanguage.fromCode(_prefs.getString(_languageKey));

  /// Built-in sources switched on; null before onboarding (then every one is).
  Set<String>? get enabledSources => _prefs.getStringList(_enabledKey)?.toSet();

  List<CustomSource> get customSources {
    final raw = _prefs.getString(_customKey);
    if (raw == null) return const [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          if (CustomSource.tryParse(j) case final c?) c,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> setRegion(String code) async => _prefs.setString(_regionKey, code);
  Future<void> setLanguage(AppLanguage language) async => _prefs.setString(_languageKey, language.name);
  Future<void> setEnabledSources(Set<String> keys) async => _prefs.setStringList(_enabledKey, keys.toList()..sort());
  Future<void> setCustomSources(List<CustomSource> list) async =>
      _prefs.setString(_customKey, jsonEncode([for (final c in list) c.toJson()]));

  /// What the rest of the app reads: [SourceCatalog.current] and [L10n.current].
  void apply() {
    L10n.current = language;
    SourceCatalog.current = SourceCatalog(enabled: enabledSources, custom: customSources);
  }
}
