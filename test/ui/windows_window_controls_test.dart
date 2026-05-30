import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/app/app.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/shared/widgets/windows_window_controls.dart';

void main() {
  const channel = MethodChannel('lockly/window');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('Windows shell shows minimize-to-tray and exit controls', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });

    try {
      await tester.pumpWidget(
        SecureBoxApp(services: AppServices.fake(hasVault: false)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('windows-window-frame')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('windows-window-content')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('windows-window-controls')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('windows-window-minimize')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('windows-window-close')),
        findsOneWidget,
      );
      expect(find.byTooltip('最小化到托盘'), findsOneWidget);
      expect(find.byTooltip('退出'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('windows-window-minimize')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('windows-window-close')));
      await tester.pump();

      expect(calls, equals(['minimize', 'close']));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('non-Windows shell does not add desktop chrome controls', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    try {
      await tester.pumpWidget(
        SecureBoxApp(services: AppServices.fake(hasVault: false)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('windows-window-frame')), findsNothing);
      expect(
        find.byKey(const ValueKey('windows-window-controls')),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Windows frame updates content when parent rebuilds', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    try {
      await tester.pumpWidget(
        const MaterialApp(home: WindowsWindowFrame(child: Text('first'))),
      );
      await tester.pump();

      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(home: WindowsWindowFrame(child: Text('second'))),
      );
      await tester.pump();

      expect(find.text('first'), findsNothing);
      expect(find.text('second'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
