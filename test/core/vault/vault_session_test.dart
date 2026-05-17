import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/vault/vault_session.dart';

void main() {
  test('unlock copies caller DEK and lock zeroes session-owned bytes', () {
    final session = VaultSession();
    final callerDek = Uint8List.fromList(List<int>.filled(32, 7));

    session.unlock(callerDek);
    callerDek.fillRange(0, callerDek.length, 9);
    final sessionCopyBeforeLock = session.debugCopyDekForTest();
    expect(sessionCopyBeforeLock, List<int>.filled(32, 7));

    session.lock();

    expect(session.debugLastZeroedDekForTest, List<int>.filled(32, 0));
    expect(session.isUnlocked, isFalse);
  });

  test('withDekCopy zeroes temporary copy after action completes', () async {
    final session = VaultSession();
    session.unlock(Uint8List.fromList(List<int>.filled(32, 3)));
    Uint8List? actionCopy;

    await session.withDekCopy((dek) async {
      actionCopy = dek;
    });

    expect(actionCopy, List<int>.filled(32, 0));
  });
}
