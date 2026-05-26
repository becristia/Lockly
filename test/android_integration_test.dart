import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android integration hardening', () {
    test('manifest declares biometric and LAN QR sync permissions', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, contains('android.permission.USE_BIOMETRIC'));
      expect(manifest, contains('android.permission.INTERNET'));
      expect(manifest, contains('android.permission.CAMERA'));
    });

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
      expect(mainActivity, contains('MethodChannel'));
      expect(mainActivity, contains('lockly/autofill'));
    });

    test('manifest declares a zero-knowledge Android Autofill service', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final autofillMetadata = File(
        'android/app/src/main/res/xml/autofill_service.xml',
      ).readAsStringSync();

      expect(manifest, contains('android.permission.BIND_AUTOFILL_SERVICE'));
      expect(manifest, contains('android.service.autofill.AutofillService'));
      expect(manifest, contains('android:name="android.autofill"'));
      expect(manifest, contains('@xml/autofill_service'));
      expect(
        manifest,
        isNot(contains('android.permission.READ_EXTERNAL_STORAGE')),
      );
      expect(autofillMetadata, contains('<autofill-service'));
      expect(autofillMetadata, contains('settingsActivity'));
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

      expect(buildFile, contains('signingConfigs'));
      expect(buildFile, contains('create("release")'));
      expect(buildFile, contains('signingConfig = signingConfigs'));
      expect(buildFile, contains('requireReleaseSigningValue'));
      expect(buildFile, contains('release {'));
      expect(buildFile, contains('isMinifyEnabled = true'));
      expect(buildFile, contains('isShrinkResources = true'));
      expect(
        buildFile,
        contains('getDefaultProguardFile("proguard-android-optimize.txt")'),
      );
      expect(buildFile, contains('"proguard-rules.pro"'));
    });

    test(
      'release merged manifest keeps local-only hardening',
      () async {
        final result = await Process.run(
          _gradlewPath(),
          const [':app:processReleaseMainManifest', '--quiet'],
          workingDirectory: 'android',
          runInShell: Platform.isWindows,
          environment: _gradleEnvironment(),
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final manifest = _releaseMergedManifest().readAsStringSync();

        expect(manifest, contains('android.permission.USE_BIOMETRIC'));
        expect(manifest, contains('android.permission.INTERNET'));
        expect(manifest, contains('android.permission.CAMERA'));
        expect(manifest, contains('android:allowBackup="false"'));
        expect(manifest, contains('android:fullBackupContent="false"'));
        expect(manifest, isNot(contains('android:debuggable="true"')));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'release signing validation fails clearly without keystore',
      () async {
        final result = await Process.run(
          _gradlewPath(),
          const [':app:validateReleaseSigning', '--quiet'],
          workingDirectory: 'android',
          runInShell: Platform.isWindows,
          environment: _gradleEnvironment(),
        );

        expect(result.exitCode, isNot(0));
        expect(
          '${result.stdout}\n${result.stderr}',
          contains('Missing release signing value: LOCKLY_RELEASE_STORE_FILE'),
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'release APK keeps local-only hardening',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'lockly-release-signing-',
        );
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
        final keystore = File(
          '${tempDir.path}${Platform.pathSeparator}key.jks',
        );
        const password = 'changeit123';
        const alias = 'lockly';

        final keytoolResult = await Process.run(
          _keytoolPath(),
          [
            '-genkeypair',
            '-keystore',
            keystore.path,
            '-storepass',
            password,
            '-keypass',
            password,
            '-keyalg',
            'RSA',
            '-keysize',
            '2048',
            '-validity',
            '1',
            '-alias',
            alias,
            '-dname',
            'CN=Lockly,O=Local,C=US',
          ],
          runInShell: Platform.isWindows,
          environment: _gradleEnvironment(),
        );
        expect(
          keytoolResult.exitCode,
          0,
          reason: '${keytoolResult.stdout}\n${keytoolResult.stderr}',
        );

        final environment = _gradleEnvironment()
          ..addAll({
            'LOCKLY_RELEASE_STORE_FILE': keystore.path,
            'LOCKLY_RELEASE_STORE_PASSWORD': password,
            'LOCKLY_RELEASE_KEY_ALIAS': alias,
            'LOCKLY_RELEASE_KEY_PASSWORD': password,
          });
        final assembleResult = await Process.run(
          _gradlewPath(),
          const [':app:assembleRelease', '--quiet'],
          workingDirectory: 'android',
          runInShell: Platform.isWindows,
          environment: environment,
        );
        expect(
          assembleResult.exitCode,
          0,
          reason: '${assembleResult.stdout}\n${assembleResult.stderr}',
        );

        final apk = _releaseApk();
        final permissions = await Process.run(_aaptPath(), [
          'dump',
          'permissions',
          apk.path,
        ], runInShell: Platform.isWindows);
        expect(
          permissions.exitCode,
          0,
          reason: '${permissions.stdout}\n${permissions.stderr}',
        );
        expect(
          permissions.stdout,
          contains('android.permission.USE_BIOMETRIC'),
        );
        expect(permissions.stdout, contains('android.permission.INTERNET'));
        expect(permissions.stdout, contains('android.permission.CAMERA'));

        final manifest = await Process.run(_aaptPath(), [
          'dump',
          'xmltree',
          apk.path,
          'AndroidManifest.xml',
        ], runInShell: Platform.isWindows);
        expect(
          manifest.exitCode,
          0,
          reason: '${manifest.stdout}\n${manifest.stderr}',
        );
        expect(
          manifest.stdout,
          contains('android:allowBackup(0x01010280)=(type 0x12)0x0'),
        );
        expect(
          manifest.stdout,
          contains('android:fullBackupContent(0x010104eb)=(type 0x12)0x0'),
        );
        expect(manifest.stdout, isNot(contains('debuggable(0x0101000f)=true')));
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );
  });
}

String _gradlewPath() {
  return Platform.isWindows ? r'.\gradlew.bat' : './gradlew';
}

Map<String, String> _gradleEnvironment() {
  final environment = Map<String, String>.from(Platform.environment);
  if (Platform.isWindows) {
    for (final path in const [
      r'D:\Program Files\Android\Android Studio\jbr',
      r'C:\Program Files\Android\Android Studio\jbr',
    ]) {
      if (Directory(path).existsSync()) {
        environment['JAVA_HOME'] = path;
        break;
      }
    }
  }
  return environment;
}

File _releaseMergedManifest() {
  final candidates = [
    File(
      'android/app/build/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml',
    ),
    File(
      'build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml',
    ),
  ];
  return candidates.firstWhere(
    (file) => file.existsSync(),
    orElse: () => throw StateError(
      'Release merged manifest was not generated in expected locations.',
    ),
  );
}

File _releaseApk() {
  final candidates = [
    File('build/app/outputs/flutter-apk/app-release.apk'),
    File('android/app/build/outputs/apk/release/app-release.apk'),
  ];
  return candidates.firstWhere(
    (file) => file.existsSync(),
    orElse: () => throw StateError(
      'Release APK was not generated in expected locations.',
    ),
  );
}

String _keytoolPath() {
  final javaHome = _gradleEnvironment()['JAVA_HOME'];
  if (javaHome != null) {
    final candidate = File(
      '$javaHome${Platform.pathSeparator}bin${Platform.pathSeparator}'
      'keytool${Platform.isWindows ? '.exe' : ''}',
    );
    if (candidate.existsSync()) {
      return candidate.path;
    }
  }
  return Platform.isWindows ? 'keytool.exe' : 'keytool';
}

String _aaptPath() {
  final androidHome =
      Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'];
  if (androidHome == null) {
    return Platform.isWindows ? 'aapt.exe' : 'aapt';
  }
  final buildTools = Directory(
    '$androidHome${Platform.pathSeparator}build-tools',
  );
  if (!buildTools.existsSync()) {
    return Platform.isWindows ? 'aapt.exe' : 'aapt';
  }
  final candidates =
      buildTools
          .listSync()
          .whereType<Directory>()
          .map(
            (dir) => File(
              '${dir.path}${Platform.pathSeparator}'
              'aapt${Platform.isWindows ? '.exe' : ''}',
            ),
          )
          .where((file) => file.existsSync())
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
  return candidates.isEmpty
      ? (Platform.isWindows ? 'aapt.exe' : 'aapt')
      : candidates.first.path;
}
