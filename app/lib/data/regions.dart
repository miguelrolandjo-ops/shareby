/// Where the user lives decides two defaults: the app's language and which sources (apps
/// and shops) are switched on, so the source filter lists what people there actually use.
/// Both can be changed later in Profile.
library;

import '../l10n/l10n.dart';

class Region {
  const Region({
    required this.code,
    required this.name,
    required this.flag,
    required this.language,
    required this.sources,
  });

  /// ISO country code, or 'global'.
  final String code;

  /// English name; shown through [tr].
  final String name;
  final String flag;

  /// The default language. Regions whose own language Shareby doesn't have yet use English.
  final AppLanguage language;

  /// Built-in source keys (see assets/rules.json) switched on by default, most used first.
  final List<String> sources;

  String get displayName => tr(name);
}

/// Shared by everyone: generic web tools that are useful anywhere.
const _everywhere = ['maps', 'gdocs'];

const regions = <Region>[
  Region(
    code: 'id',
    name: 'Indonesia',
    flag: '🇮🇩',
    language: AppLanguage.id,
    sources: [
      'instagram', 'tiktok', 'youtube', 'x', 'facebook', 'threads', 'whatsapp', 'telegram', 'pinterest',
      'shopee', 'tokopedia', 'lazada', 'bukalapak', 'traveloka', 'gofood', 'grab', 'spotify', 'netflix',
      ..._everywhere,
    ],
  ),
  Region(
    code: 'my',
    name: 'Malaysia',
    flag: '🇲🇾',
    language: AppLanguage.en,
    sources: [
      'instagram', 'tiktok', 'youtube', 'facebook', 'x', 'threads', 'whatsapp', 'telegram', 'pinterest',
      'shopee', 'lazada', 'grab', 'traveloka', 'spotify', 'netflix', ..._everywhere,
    ],
  ),
  Region(
    code: 'sg',
    name: 'Singapore',
    flag: '🇸🇬',
    language: AppLanguage.en,
    sources: [
      'instagram', 'tiktok', 'youtube', 'facebook', 'x', 'threads', 'reddit', 'linkedin', 'whatsapp',
      'telegram', 'shopee', 'lazada', 'amazon', 'grab', 'spotify', 'netflix', ..._everywhere,
    ],
  ),
  Region(
    code: 'ph',
    name: 'Philippines',
    flag: '🇵🇭',
    language: AppLanguage.en,
    sources: [
      'facebook', 'tiktok', 'youtube', 'instagram', 'x', 'threads', 'reddit', 'pinterest', 'shopee', 'lazada',
      'grab', 'spotify', 'netflix', ..._everywhere,
    ],
  ),
  Region(
    code: 'in',
    name: 'India',
    flag: '🇮🇳',
    language: AppLanguage.en,
    sources: [
      'youtube', 'instagram', 'whatsapp', 'facebook', 'x', 'linkedin', 'telegram', 'reddit', 'quora',
      'pinterest', 'amazon', 'spotify', 'netflix', ..._everywhere,
    ],
  ),
  Region(
    code: 'kr',
    name: 'South Korea',
    flag: '🇰🇷',
    language: AppLanguage.en,
    sources: ['youtube', 'instagram', 'naver', 'x', 'tiktok', 'threads', 'spotify', 'netflix', ..._everywhere],
  ),
  Region(
    code: 'us',
    name: 'United States',
    flag: '🇺🇸',
    language: AppLanguage.en,
    sources: [
      'instagram', 'tiktok', 'youtube', 'x', 'threads', 'reddit', 'facebook', 'pinterest', 'linkedin',
      'snapchat', 'bluesky', 'amazon', 'spotify', 'applemusic', 'netflix', 'medium', 'substack', ..._everywhere,
    ],
  ),
  Region(
    code: 'gb',
    name: 'United Kingdom',
    flag: '🇬🇧',
    language: AppLanguage.en,
    sources: [
      'instagram', 'tiktok', 'youtube', 'x', 'threads', 'reddit', 'facebook', 'pinterest', 'linkedin',
      'snapchat', 'whatsapp', 'amazon', 'spotify', 'netflix', 'medium', 'substack', ..._everywhere,
    ],
  ),
  Region(
    code: 'global',
    name: 'Somewhere else',
    flag: '🌏',
    language: AppLanguage.en,
    sources: [
      'instagram', 'tiktok', 'youtube', 'x', 'facebook', 'threads', 'reddit', 'pinterest', 'linkedin',
      'whatsapp', 'amazon', 'spotify', 'netflix', ..._everywhere,
    ],
  ),
];

Region regionByCode(String? code) => regions.firstWhere((r) => r.code == code, orElse: () => regions.last);
