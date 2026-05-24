import 'package:flutter/services.dart';

class AndroidAutofillStatus {
  const AndroidAutofillStatus({required this.supported, required this.enabled});

  const AndroidAutofillStatus.unavailable()
    : supported = false,
      enabled = false;

  final bool supported;
  final bool enabled;
}

class AndroidAutofillService {
  const AndroidAutofillService({
    MethodChannel channel = const MethodChannel('lockly/autofill'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<AndroidAutofillStatus> status() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'getAutofillStatus',
      );
      return AndroidAutofillStatus(
        supported: result?['supported'] == true,
        enabled: result?['enabled'] == true,
      );
    } on MissingPluginException {
      return const AndroidAutofillStatus.unavailable();
    } on PlatformException {
      return const AndroidAutofillStatus.unavailable();
    }
  }

  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openAutofillSettings');
    } on MissingPluginException {
      return;
    }
  }
}
