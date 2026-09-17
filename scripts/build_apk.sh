#!/usr/bin/env bash
# بناء APK محلياً (يتطلب Flutter + Android SDK + ذاكرة ≥ 4GB)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_URL="${API_URL:-https://dallini-app.onrender.com}"
cd "$ROOT"
rm -rf mobile
flutter create --platforms=android --org com.dallini mobile
cp mobile_source/pubspec.yaml mobile/pubspec.yaml
cp mobile_source/lib/app_fixed.dart mobile/lib/main.dart
python3 - <<'PY'
from pathlib import Path
p = Path('mobile/android/app/src/main/AndroidManifest.xml')
s = p.read_text()
s = s.replace('android:label="mobile"', 'android:label="دلّيني"')
marker = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
perms = ('<uses-permission android:name="android.permission.INTERNET"/>\n'
         '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n'
         '<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>\n'
         '<uses-permission android:name="android.permission.RECORD_AUDIO"/>')
if 'android.permission.INTERNET' not in s:
    s = s.replace(marker, marker + '\n' + perms)
p.write_text(s)
PY
cd mobile
flutter pub get
dart analyze lib/main.dart --no-fatal-warnings
flutter build apk --release --dart-define=API_URL="$API_URL"
echo "APK: $ROOT/mobile/build/app/outputs/flutter-apk/app-release.apk"
