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
      expect(lightStyles, contains('Theme.AppCompat.DayNight.NoActionBar'));
      expect(darkStyles, contains('Theme.AppCompat.DayNight.NoActionBar'));
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
