import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ClipboardService {
  ClipboardService({this.clearPasswordAfter = const Duration(seconds: 30)});

  static const _clipboardFormat = 'text/plain';

  Duration clearPasswordAfter;
  final Sha256 _sha256 = Sha256();
  Timer? _clearTimer;
  String? _pendingPasswordClearDigest;

  @visibleForTesting
  String? get debugPendingClearValueForTest => null;

  @visibleForTesting
  String? get debugPendingClearDigestForTest => _pendingPasswordClearDigest;

  Future<bool> copyUsername(String username) async {
    final didWrite = await _trySetClipboardData(ClipboardData(text: username));
    if (!didWrite) {
      return false;
    }

    _cancelPendingClear();
    return true;
  }

  Future<bool> copyPassword(String password) async {
    return copySensitiveTemporary(password, clearAfter: clearPasswordAfter);
  }

  Future<bool> copySensitiveTemporary(
    String value, {
    required Duration clearAfter,
  }) async {
    final didWrite = await _trySetClipboardData(ClipboardData(text: value));
    if (!didWrite) {
      return false;
    }

    _cancelPendingClear();
    _schedulePasswordClear(await _digestText(value), clearAfter: clearAfter);
    return true;
  }

  void updateClearPasswordAfter(Duration value) {
    if (value == clearPasswordAfter) {
      return;
    }

    clearPasswordAfter = value;
    final pendingDigest = _pendingPasswordClearDigest;
    if (pendingDigest == null) {
      return;
    }

    _clearTimer?.cancel();
    _schedulePasswordClear(pendingDigest, clearAfter: clearPasswordAfter);
  }

  void dispose() {
    _cancelPendingClear();
  }

  Future<bool> clearPendingPasswordNow() async {
    final pendingDigest = _pendingPasswordClearDigest;
    if (pendingDigest == null) {
      return false;
    }

    _clearTimer?.cancel();
    return _clearPasswordIfStillPresent(pendingDigest);
  }

  Future<bool> _clearPasswordIfStillPresent(String expectedDigest) async {
    _pendingPasswordClearDigest = null;
    _clearTimer = null;
    final current = await _tryGetClipboardData();
    final currentText = current?.text;
    if (currentText == null ||
        await _digestText(currentText) != expectedDigest) {
      return false;
    }

    return _trySetClipboardData(const ClipboardData(text: ''));
  }

  void _cancelPendingClear() {
    _clearTimer?.cancel();
    _clearTimer = null;
    _pendingPasswordClearDigest = null;
  }

  void _schedulePasswordClear(String digest, {required Duration clearAfter}) {
    _pendingPasswordClearDigest = digest;
    _clearTimer = Timer(clearAfter, () {
      unawaited(_clearPasswordIfStillPresent(digest));
    });
  }

  Future<String> _digestText(String value) async {
    final digest = await _sha256.hash(utf8.encode(value));
    return base64Encode(digest.bytes);
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
