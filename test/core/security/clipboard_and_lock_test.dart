import 'dart:async';

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
  var failNextSetData = false;
  var failNextGetData = false;

  setUp(() {
    clipboardText = null;
    failNextSetData = false;
    failNextGetData = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
          switch (methodCall.method) {
            case 'Clipboard.setData':
              if (failNextSetData) {
                failNextSetData = false;
                throw PlatformException(code: 'set_data_failed');
              }
              final arguments = Map<String, dynamic>.from(
                methodCall.arguments as Map,
              );
              clipboardText = arguments['text'] as String?;
              return null;
            case 'Clipboard.getData':
              if (failNextGetData) {
                failNextGetData = false;
                throw PlatformException(code: 'get_data_failed');
              }
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
    'temporary sensitive clipboard clears after requested timeout',
    () async {
      fakeAsync((async) {
        final service = ClipboardService(
          clearPasswordAfter: const Duration(seconds: 30),
        );
        service.copySensitiveTemporary(
          'encrypted-backup-json',
          clearAfter: const Duration(seconds: 5),
        );
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        Clipboard.getData(clipboardFormat).then((data) {
          expect(data?.text, '');
        });
        async.flushMicrotasks();
      });
    },
  );

  test(
    'pending clipboard cleanup does not retain plaintext in service state',
    () {
      fakeAsync((async) {
        final service = ClipboardService(
          clearPasswordAfter: const Duration(seconds: 30),
        );

        service.copyPassword('secret-password');
        async.flushMicrotasks();

        expect(service.debugPendingClearValueForTest, isNull);
        expect(service.debugPendingClearDigestForTest, isNotNull);
      });
    },
  );

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

  test('updating clipboard timeout preserves pending password cleanup', () {
    fakeAsync((async) {
      final service = ClipboardService(
        clearPasswordAfter: const Duration(seconds: 30),
      );
      service.copyPassword('secret-password');
      async.flushMicrotasks();

      service.updateClearPasswordAfter(const Duration(seconds: 10));

      async.elapse(const Duration(seconds: 9));
      async.flushMicrotasks();
      Clipboard.getData(clipboardFormat).then((data) {
        expect(data?.text, 'secret-password');
      });
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      Clipboard.getData(clipboardFormat).then((data) {
        expect(data?.text, '');
      });
      async.flushMicrotasks();
    });
  });

  test(
    'updating clipboard timeout with same value does not extend cleanup',
    () {
      fakeAsync((async) {
        final service = ClipboardService(
          clearPasswordAfter: const Duration(seconds: 30),
        );
        service.copyPassword('secret-password');
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 29));
        service.updateClearPasswordAfter(const Duration(seconds: 30));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        Clipboard.getData(clipboardFormat).then((data) {
          expect(data?.text, '');
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

  test(
    'copyUsername returns false on Clipboard.setData failure and keeps pending password cleanup',
    () {
      fakeAsync((async) {
        final service = ClipboardService(
          clearPasswordAfter: const Duration(seconds: 30),
        );
        service.copyPassword('secret-password');
        async.flushMicrotasks();

        failNextSetData = true;
        Object? copyResult;
        (service.copyUsername('user@example.com') as dynamic).then((value) {
          copyResult = value;
        });
        async.flushMicrotasks();

        expect(copyResult, isFalse);

        Clipboard.getData(clipboardFormat).then((data) {
          expect(data?.text, 'secret-password');
        });
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();

        Clipboard.getData(clipboardFormat).then((data) {
          expect(data?.text, '');
        });
        async.flushMicrotasks();
      });
    },
  );

  test('copyPassword returns false on Clipboard.setData failure', () {
    fakeAsync((async) {
      final service = ClipboardService(
        clearPasswordAfter: const Duration(seconds: 30),
      );
      failNextSetData = true;

      Object? copyResult;
      (service.copyPassword('secret-password') as dynamic).then((value) {
        copyResult = value;
      });
      async.flushMicrotasks();

      expect(copyResult, isFalse);

      Clipboard.getData(clipboardFormat).then((data) {
        expect(data?.text, isNull);
      });
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();

      Clipboard.getData(clipboardFormat).then((data) {
        expect(data?.text, isNull);
      });
      async.flushMicrotasks();
    });
  });

  test('password cleanup swallows Clipboard.getData failures', () {
    Object? uncaughtError;

    runZonedGuarded(
      () {
        fakeAsync((async) {
          final service = ClipboardService(
            clearPasswordAfter: const Duration(seconds: 30),
          );
          service.copyPassword('secret-password');
          async.flushMicrotasks();

          failNextGetData = true;
          async.elapse(const Duration(seconds: 30));
          async.flushMicrotasks();

          Clipboard.getData(clipboardFormat).then((data) {
            expect(data?.text, 'secret-password');
          });
          async.flushMicrotasks();
        });
      },
      (error, stackTrace) {
        uncaughtError = error;
      },
    );

    expect(uncaughtError, isNull);
  });

  test('clearPendingPasswordNow clears only the pending password', () {
    fakeAsync((async) {
      final service = ClipboardService(
        clearPasswordAfter: const Duration(seconds: 30),
      );
      service.copyPassword('secret-password');
      async.flushMicrotasks();

      Object? clearResult;
      (service.clearPendingPasswordNow() as dynamic).then((value) {
        clearResult = value;
      });
      async.flushMicrotasks();

      expect(clearResult, isTrue);
      Clipboard.getData(clipboardFormat).then((data) {
        expect(data?.text, '');
      });
      async.flushMicrotasks();
    });
  });

  test('clearPendingPasswordNow does not overwrite newer clipboard data', () {
    fakeAsync((async) {
      final service = ClipboardService(
        clearPasswordAfter: const Duration(seconds: 30),
      );
      service.copyPassword('secret-password');
      async.flushMicrotasks();
      Clipboard.setData(const ClipboardData(text: 'newer-value'));
      async.flushMicrotasks();

      Object? clearResult;
      (service.clearPendingPasswordNow() as dynamic).then((value) {
        clearResult = value;
      });
      async.flushMicrotasks();

      expect(clearResult, isFalse);
      Clipboard.getData(clipboardFormat).then((data) {
        expect(data?.text, 'newer-value');
      });
      async.flushMicrotasks();
    });
  });

  test('app lifecycle guard clears password clipboard on background', () {
    fakeAsync((async) {
      final clipboardService = ClipboardService(
        clearPasswordAfter: const Duration(seconds: 30),
      );
      clipboardService.copyPassword('secret-password');
      async.flushMicrotasks();
      var lockCount = 0;
      final service = AutoLockService(
        timeout: const Duration(minutes: 5),
        onLock: () => lockCount++,
      );
      final guard = AppLifecycleGuard(
        autoLockService: service,
        clipboardService: clipboardService,
      );

      guard.didChangeAppLifecycleState(AppLifecycleState.paused);
      async.flushMicrotasks();

      expect(lockCount, 1);
      Clipboard.getData(clipboardFormat).then((data) {
        expect(data?.text, '');
      });
      async.flushMicrotasks();
    });
  });

  test('dispose cancels a pending password clipboard clear', () {
    fakeAsync((async) {
      final service = ClipboardService(
        clearPasswordAfter: const Duration(seconds: 30),
      );
      service.copyPassword('secret-password');
      async.flushMicrotasks();

      service.dispose();

      async.elapse(const Duration(seconds: 30));
      async.flushMicrotasks();

      Clipboard.getData(clipboardFormat).then((data) {
        expect(data?.text, 'secret-password');
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

  test(
    'app lifecycle guard locks once per background cycle and resets on resumed',
    () {
      var lockCount = 0;
      final service = AutoLockService(
        timeout: const Duration(minutes: 5),
        onLock: () => lockCount++,
      );
      final guard = AppLifecycleGuard(autoLockService: service);

      guard.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(lockCount, 0);

      for (final state in const [
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]) {
        guard.didChangeAppLifecycleState(state);
      }

      expect(lockCount, 1);

      guard.didChangeAppLifecycleState(AppLifecycleState.resumed);
      guard.didChangeAppLifecycleState(AppLifecycleState.paused);

      expect(lockCount, 2);
    },
  );

  test('app lifecycle guard does not lock on inactive before resumed', () {
    var lockCount = 0;
    final service = AutoLockService(
      timeout: const Duration(minutes: 5),
      onLock: () => lockCount++,
    );
    final guard = AppLifecycleGuard(autoLockService: service);

    guard.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(lockCount, 0);

    guard.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(lockCount, 0);

    guard.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(lockCount, 1);
  });
}
