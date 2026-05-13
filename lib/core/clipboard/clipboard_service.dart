import 'dart:async';

import 'package:flutter/services.dart';

class ClipboardService {
  ClipboardService({this.clearPasswordAfter = const Duration(seconds: 30)});

  static const _clipboardFormat = 'text/plain';

  final Duration clearPasswordAfter;
  Timer? _clearTimer;

  Future<void> copyUsername(String username) async {
    _cancelPendingClear();
    await Clipboard.setData(ClipboardData(text: username));
  }

  Future<void> copyPassword(String password) async {
    _cancelPendingClear();
    await Clipboard.setData(ClipboardData(text: password));
    _clearTimer = Timer(clearPasswordAfter, () {
      unawaited(_clearPasswordIfStillPresent(password));
    });
  }

  void dispose() {
    _cancelPendingClear();
  }

  Future<void> _clearPasswordIfStillPresent(String password) async {
    final current = await Clipboard.getData(_clipboardFormat);
    if (current?.text != password) {
      return;
    }
    await Clipboard.setData(const ClipboardData(text: ''));
  }

  void _cancelPendingClear() {
    _clearTimer?.cancel();
    _clearTimer = null;
  }
}
