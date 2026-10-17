set -e
flutter create --org com.tgrd76 --project-name aerosim_app --platforms=android build_app
cp pubspec.yaml build_app/pubspec.yaml
rm -rf build_app/lib build_app/test
cp -r lib build_app/lib
cp -r assets build_app/assets
M=build_app/android/app/src/main/AndroidManifest.xml
sed -i 's|android:label="[^"]*"|android:label="AeroSimAPP"|' "$M"
sed -i 's|<application|<uses-permission android:name="android.permission.INTERNET"/>\n    <application|' "$M"
cd build_app
flutter pub get
dart run flutter_launcher_icons
flutter build apk --release
