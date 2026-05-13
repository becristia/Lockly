import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/clipboard/clipboard_service.dart';
import 'package:secure_box/core/security/app_lifecycle_guard.dart';
import 'package:secure_box/core/security/auto_lock_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const clipboardFormat = 'text/plain';
  String? clipboardText;

  setUp(() {
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
          switch (methodCall.method) {
            case 'Clipboard.setData':
              final arguments = Map<String, dynamic>.from(
                methodCall.arguments as Map,
              );
              clipboardText = arguments['text'] as String?;
              return null;
            case 'Clipboard.getData':
              if (clipboardText == null) {
                return null;
              }
              return <String, dynamic>{'text': clipboardText};
          }

          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('password clipboard clears after timeout', () async {
    fakeAsync((async) {
      final service = ClipboardService(
        clearPasswordAfter: const Duration(seconds: 30),
      );
      service.copyPassword('secret-password');
      async.flushMicrotasks();

      Clipboard.getData(clipboardFormat).then((data) {
        expect(data?.text, 'secret-password');
      });
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();

      Clipboard.getData(clipboardFormat).then((data) {
        expect(data?.text ?? '', isNot('secret-password'));
      });
      async.flushMicrotasks();
    });
  });

  test(
    'password clipboard cleanup does not overwrite newer clipboard data',
    () {
      fakeAsync((async) {
        final service = ClipboardService(
          clearPasswordAfter: const Duration(seconds: 30),
        );
        service.copyPassword('secret-password');
        async.flushMicrotasks();

        Clipboard.setData(const ClipboardData(text: 'newer-value'));
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();

        Clipboard.getData(clipboardFormat).then((data) {
          expect(data?.text, 'newer-value');
        });
        async.flushMicrotasks();
      });
    },
  );

  test('username clipboard does not clear after password timeout', () {
    fakeAsync((async) {
      final service = ClipboardService(
        clearPasswordAfter: const Duration(seconds: 30),
      );
      service.copyUsername('user@example.com');
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();

      Clipboard.getData(clipboardFormat).then((data) {
        expect(data?.text, 'user@example.com');
      });
      async.flushMicrotasks();
    });
  });

  test('auto lock calls lock after inactivity timeout', () {
    fakeAsync((async) {
      var locked = false;
      final service = AutoLockService(
        timeout: const Duration(minutes: 5),
        onLock: () => locked = true,
      );

      service.recordActivity();
      async.elapse(const Duration(minutes: 4));
      expect(locked, isFalse);
      async.elapse(const Duration(minutes: 1));
      expect(locked, isTrue);
    });
  });

  test('auto lock resets timeout on later activity', () {
    fakeAsync((async) {
      var lockCount = 0;
      final service = AutoLockService(
        timeout: const Duration(minutes: 5),
        onLock: () => lockCount++,
      );

      service.recordActivity();
      async.elapse(const Duration(minutes: 4));
      service.recordActivity();
      async.elapse(const Duration(minutes: 4));
      expect(lockCount, 0);

      async.elapse(const Duration(minutes: 1));
      expect(lockCount, 1);
    });
  });

  test('lockNow locks immediately and dispose cancels pending timeout', () {
    fakeAsync((async) {
      var lockCount = 0;
      final service = AutoLockService(
        timeout: const Duration(minutes: 5),
        onLock: () => lockCount++,
      );

      service.recordActivity();
      service.lockNow();
      expect(lockCount, 1);

      service.recordActivity();
      service.dispose();
      async.elapse(const Duration(minutes: 5));
      expect(lockCount, 1);
    });
  });

  test('app lifecycle guard locks on non-resumed states', () {
    var lockCount = 0;
    final service = AutoLockService(
      timeout: const Duration(minutes: 5),
      onLock: () => lockCount++,
    );
    final guard = AppLifecycleGuard(autoLockService: service);

    guard.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(lockCount, 0);

    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      guard.didChangeAppLifecycleState(state);
    }

    expect(lockCount, 4);
  });
}
