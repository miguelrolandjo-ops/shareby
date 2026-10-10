#!/usr/bin/env bash
# One-time setup: generates the android/ and ios/ folders with your installed Flutter,
# then applies Shareby's native Android share-sheet files on top.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d android ] || [ ! -d ios ]; then
  # Keeps existing lib/, test/, pubspec.yaml; only adds what's missing.
  flutter create --org com.shareby --project-name shareby --platforms android,ios .
fi

# flutter create adds a counter-app test that doesn't match this app.
if [ -f test/widget_test.dart ] && grep -q "MyApp" test/widget_test.dart; then
  rm test/widget_test.dart
fi

cp -R platform_overlay/android/. android/
flutter pub get

echo
echo "Done. Next:"
echo "  flutter analyze"
echo "  flutter test"
echo "  flutter run            # Android emulator; API defaults to http://10.0.2.2:8080"
