import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/autofill/android_autofill_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AndroidAutofillService', () {
    const channel = MethodChannel('lockly/autofill');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'reads supported and enabled status from the platform channel',
      () async {
        final calls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call.method);
              return <String, Object?>{'supported': true, 'enabled': true};
            });

        final status = await const AndroidAutofillService().status();

        expect(status.supported, isTrue);
        expect(status.enabled, isTrue);
        expect(calls, ['getAutofillStatus']);
      },
    );

    test(
      'opens Android Autofill settings through the platform channel',
      () async {
        final calls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call.method);
              return null;
            });

        await const AndroidAutofillService().openSettings();

        expect(calls, ['openAutofillSettings']);
      },
    );

    test('fails closed when the platform plugin is unavailable', () async {
      final status = await const AndroidAutofillService().status();

      expect(status.supported, isFalse);
      expect(status.enabled, isFalse);
    });
  });
}
