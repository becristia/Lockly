import 'dart:async';

import 'package:flutter/services.dart';

class ClipboardService {
  ClipboardService({this.clearPasswordAfter = const Duration(seconds: 30)});

  static const _clipboardFormat = 'text/plain';

  Duration clearPasswordAfter;
  Timer? _clearTimer;
  String? _pendingPasswordClear;

  Future<bool> copyUsername(String username) async {
    final didWrite = await _trySetClipboardData(ClipboardData(text: username));
    if (!didWrite) {
      return false;
    }

    _cancelPendingClear();
    return true;
  }

  Future<bool> copyPassword(String password) async {
    final didWrite = await _trySetClipboardData(ClipboardData(text: password));
    if (!didWrite) {
      return false;
    }

    _cancelPendingClear();
    _schedulePasswordClear(password);
    return true;
  }

  void updateClearPasswordAfter(Duration value) {
    if (value == clearPasswordAfter) {
      return;
    }

    clearPasswordAfter = value;
    final pendingPassword = _pendingPasswordClear;
    if (pendingPassword == null) {
      return;
    }

    _clearTimer?.cancel();
    _schedulePasswordClear(pendingPassword);
  }

  void dispose() {
    _cancelPendingClear();
  }

  Future<void> _clearPasswordIfStillPresent(String password) async {
    _pendingPasswordClear = null;
    _clearTimer = null;
    final current = await _tryGetClipboardData();
    if (current?.text != password) {
      return;
    }

    await _trySetClipboardData(const ClipboardData(text: ''));
  }

  void _cancelPendingClear() {
    _clearTimer?.cancel();
    _clearTimer = null;
    _pendingPasswordClear = null;
  }

  void _schedulePasswordClear(String password) {
    _pendingPasswordClear = password;
    _clearTimer = Timer(clearPasswordAfter, () {
      unawaited(_clearPasswordIfStillPresent(password));
    });
  }

  Future<ClipboardData?> _tryGetClipboardData() async {
    try {
      return await Clipboard.getData(_clipboardFormat);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> _trySetClipboardData(ClipboardData data) async {
    try {
      await Clipboard.setData(data);
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
