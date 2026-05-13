import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/biometric/biometric_service.dart';

void main() {
  test('enable stores DEK copy and disable removes it', () async {
    final auth = FakeBiometricAuthenticator(
      canAuthenticate: true,
      succeeds: true,
    );
    final store = MemorySecureDekStore();
    final service = BiometricService(authenticator: auth, store: store);

    await service.enable(Uint8List.fromList([1, 2, 3, 4]));
    expect(await store.readDek(), [1, 2, 3, 4]);

    await service.disable();
    expect(await store.readDek(), isNull);
  });

  test('failed biometric returns fallback result', () async {
    final service = BiometricService(
      authenticator: FakeBiometricAuthenticator(
        canAuthenticate: true,
        succeeds: false,
      ),
      store: MemorySecureDekStore()..writeDek(Uint8List.fromList([9, 9])),
    );

    final result = await service.unlock();
    expect(result, BiometricUnlockResult.fallbackToMasterPassword);
  });

  test('successful biometric returns unlocked result', () async {
    final service = BiometricService(
      authenticator: FakeBiometricAuthenticator(
        canAuthenticate: true,
        succeeds: true,
      ),
      store: MemorySecureDekStore()..writeDek(Uint8List.fromList([9, 9])),
    );

    final result = await service.unlock();
    expect(result, BiometricUnlockResult.unlocked);
  });
}
