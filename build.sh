set -e
flutter create --org com.tgrd76 --project-name aerosim_app --platforms=android build_app
cp pubspec.yaml build_app/pubspec.yaml
rm -rf build_app/lib build_app/test
cp -r lib build_app/lib
cp -r assets build_app/assets

# Clé de signature fixe : garde la même empreinte SHA-1 à chaque build (obligatoire pour Google Sign-In)
mkdir -p ~/.android
cp debug.keystore ~/.android/debug.keystore

M=build_app/android/app/src/main/AndroidManifest.xml
sed -i 's|android:label="[^"]*"|android:label="AeroSimAPP"|' "$M"
sed -i 's|<application|<uses-permission android:name="android.permission.INTERNET"/>\n    <application|' "$M"

# Firebase demande Android 6.0 (API 23) minimum
sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 23/' build_app/android/app/build.gradle.kts 2>/dev/null || true
sed -i 's/minSdkVersion flutter.minSdkVersion/minSdkVersion 23/' build_app/android/app/build.gradle 2>/dev/null || true

cd build_app
flutter pub get
dart run flutter_launcher_icons
flutter analyze --no-fatal-infos --no-fatal-warnings > analyze.log 2>&1 || true
if ! flutter build apk --release > build.log 2>&1; then
  echo "=========== ERREURS D'ANALYSE ==========="
  grep -E " error " analyze.log | head -30 || true
  echo "=========== ERREURS DE BUILD ==========="
  grep -E -B3 -A8 "Error:|error:|What went wrong" build.log | head -100 || true
  echo "=========== FIN : copie tout ce qui est au-dessus ==========="
  exit 1
fi
tail -5 build.log
