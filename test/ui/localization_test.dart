import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/shared/i18n/app_language.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/i18n/app_strings_en.dart';
import 'package:secure_box/shared/i18n/app_strings_zh.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('app language parser falls back to Chinese', () {
    expect(AppLanguageX.parse('en'), AppLanguage.en);
    expect(AppLanguageX.parse('zh'), AppLanguage.zh);
    expect(AppLanguageX.parse('bad-value'), AppLanguage.zh);
  });

  testWidgets('language preference survives app service recreation', (
    tester,
  ) async {
    final firstServices = AppServices.fake(
      hasVault: true,
      unlocked: true,
      persistLanguagePreference: true,
    );
    firstServices.language = AppLanguage.en;
    await tester.pump();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('lockly.language'), 'en');
    firstServices.dispose();

    final restoredServices = AppServices.fake(
      hasVault: true,
      unlocked: true,
      persistLanguagePreference: true,
    );
    await tester.pump();

    expect(restoredServices.language, AppLanguage.en);
    restoredServices.dispose();
  });

  test('setting language after dispose does not touch disposed notifier', () {
    final services = AppServices.fake(
      hasVault: true,
      unlocked: true,
      persistLanguagePreference: true,
    );
    services.dispose();

    expect(() => services.language = AppLanguage.en, returnsNormally);
  });

  testWidgets('settings switches between Chinese and English', (tester) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);
    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('vault-shell-settings-tab')));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsWidgets);
    expect(find.text('语言'), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(services.language, AppLanguage.en);
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Vault'), findsOneWidget);

    await tester.tap(find.text('中文'));
    await tester.pumpAndSettle();
    expect(services.language, AppLanguage.zh);
    expect(find.text('设置'), findsWidgets);
  });

  testWidgets('app strings scope exposes selected language', (tester) async {
    final services = AppServices.fake(hasVault: true, unlocked: true);
    services.language = AppLanguage.en;

    await tester.pumpWidget(SecureBoxApp(services: services));
    await tester.pumpAndSettle();

    final context = tester.element(
      find.byKey(const ValueKey('vault-shell-settings-tab')),
    );
    expect(AppStrings.of(context).settingsTitle, 'Settings');
  });

  test('Chinese passkey strings avoid English UI labels', () {
    const strings = AppStringsZh();
    final passkeyText = [
      'cameraPermissionRequired',
      'androidAutofill',
      'openAutofillSettings',
      'email',
      'advancedInfo',
      'advancedInfoSubtitle',
      'passkeys',
      'passkeyMetadata',
      'addPasskeyMetadata',
      'relyingPartyId',
      'rpId',
      'algorithm',
      'readiness',
      'credentialId',
      'credentialIdHint',
      'userHandle',
      'publicKeyAlgorithm',
      'platform',
      'platformHint',
      'roadmapPasskeysDetail',
    ].map(strings.text).join('\n');

    for (final phrase in [
      'Passkey',
      'Android Autofill',
      'Email',
      'camera permission',
      'Relying party ID',
      'Algorithm',
      'Readiness',
      'Credential ID',
      'base64url credential id',
      'User handle',
      'Public key algorithm',
      'Platform',
    ]) {
      expect(passkeyText.contains(phrase), isFalse, reason: phrase);
    }
    expect(strings.text('androidAutofill'), 'Android 自动填充');
    expect(strings.text('email'), '邮箱');
    expect(strings.text('passkeys'), '通行密钥');
    expect(strings.text('advancedInfo'), '高级信息');
    expect(strings.text('passkeyMetadata'), '通行密钥信息（可选）');
    expect(strings.text('relyingPartyId'), '网站域名 ID');
    expect(strings.text('credentialIdHint'), 'base64url 格式的凭据 ID');
  });

  test('Chinese biometric prompts are fingerprint-focused and localized', () {
    const strings = AppStringsZh();
    final promptText = [
      'useBiometric',
      'biometricAuthTitle',
      'biometricAuthSubtitle',
      'biometricAuthReason',
      'biometricPromptSubtitle',
    ].map(strings.text).join('\n');

    expect(promptText, contains('指纹'));
    expect(promptText, contains('面容'));
    expect(promptText, isNot(contains('Authenticate')));
    expect(promptText, isNot(contains('Unlock Lockly')));
    expect(strings.text('useBiometric'), '使用指纹/面容解锁');
    expect(strings.text('biometricAuthTitle'), '指纹/面容解锁 Lockly');
    expect(strings.text('biometricAuthSubtitle'), '使用系统生物识别解锁本地密码库');
    expect(strings.text('biometricAuthReason'), '使用指纹或面容解锁 Lockly');
  });

  test('LAN import result count strings keep placeholder contract', () {
    const english = AppStringsEn();
    const chinese = AppStringsZh();

    for (final key in ['lanImportedCount', 'lanSkippedCount']) {
      expect(english.text(key), contains('{count}'), reason: 'en $key');
      expect(chinese.text(key), contains('{count}'), reason: 'zh $key');
    }

    expect(
      chinese.text('lanImportedCount').replaceAll('{count}', '3'),
      contains('已导入 3 条'),
    );
    expect(
      chinese.text('lanSkippedCount').replaceAll('{count}', '2'),
      contains('已跳过 2 条'),
    );
  });

  test('app-owned visible strings are centralized', () {
    final targetDirectories = [
      Directory('lib/features'),
      Directory('lib/app'),
      Directory('lib/shared/widgets'),
    ];
    final visibleLiteralPattern = RegExp(
      r'''(?:Text|SelectableText)\(\s*(?:const\s+)?['"]|'''
      r'''(?:_showSnack|showSnackBar)\(\s*(?:const\s+)?['"]|'''
      r'''(?:labelText|hintText|helperText|errorText|tooltip|semanticLabel|'''
      r'''title|subtitle|message|label|actionLabel|confirmLabel|'''
      r'''submitLabel|failureMessage)\s*:\s*(?:const\s+)?['"]''',
    );
    final offenders = <String>[];

    for (final directory in targetDirectories) {
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final lines = entity.readAsLinesSync();
        for (var index = 0; index < lines.length; index += 1) {
          final line = lines[index];
          if (visibleLiteralPattern.hasMatch(line)) {
            offenders.add('${entity.path}:${index + 1}: ${line.trim()}');
          }
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
