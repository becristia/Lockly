import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android integration hardening', () {
    test(
      'manifest declares biometric permission and no internet permission',
      () {
        final manifest = File(
          'android/app/src/main/AndroidManifest.xml',
        ).readAsStringSync();

        expect(manifest, contains('android.permission.USE_BIOMETRIC'));
        expect(
          _androidFilesText(),
          isNot(contains('android.permission.INTERNET')),
        );
      },
    );

    test('manifest disables Android cloud backup for local vault data', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:fullBackupContent="false"'));
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
    });

    test('MainActivity supports local_auth and blocks screenshots', () {
      final mainActivity = File(
        'android/app/src/main/kotlin/com/lockly/securebox/MainActivity.kt',
      ).readAsStringSync();

      expect(mainActivity, contains('FlutterFragmentActivity'));
      expect(mainActivity, contains('WindowManager.LayoutParams.FLAG_SECURE'));
      expect(mainActivity, contains('window.setFlags('));
    });

    test('Android settings meet local_auth requirements', () {
      final buildFile = File('android/app/build.gradle.kts').readAsStringSync();
      final lightStyles = File(
        'android/app/src/main/res/values/styles.xml',
      ).readAsStringSync();
      final darkStyles = File(
        'android/app/src/main/res/values-night/styles.xml',
      ).readAsStringSync();

      expect(buildFile, contains('minSdk = 24'));
      expect(buildFile, contains('applicationId = "com.lockly.securebox"'));
      expect(lightStyles, contains('Theme.AppCompat.DayNight.NoActionBar'));
      expect(darkStyles, contains('Theme.AppCompat.DayNight.NoActionBar'));
    });

    test('release build enables shrinking and obfuscation rules', () {
      final buildFile = File('android/app/build.gradle.kts').readAsStringSync();

      expect(buildFile, contains('release {'));
      expect(buildFile, contains('isMinifyEnabled = true'));
      expect(buildFile, contains('isShrinkResources = true'));
      expect(
        buildFile,
        contains('getDefaultProguardFile("proguard-android-optimize.txt")'),
      );
      expect(buildFile, contains('"proguard-rules.pro"'));
    });
  });
}

String _androidFilesText() {
  return Directory('android')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.xml') || file.path.endsWith('.kt'))
      .map((file) => file.readAsStringSync())
      .join('\n');
}
