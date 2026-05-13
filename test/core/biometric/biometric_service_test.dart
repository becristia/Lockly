import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/biometric/biometric_service.dart';

void main() {
  test('enable stores 32-byte DEK copy and disable removes it', () async {
    final auth = FakeBiometricAuthenticator(
      canAuthenticate: true,
      succeeds: true,
    );
    final store = MemorySecureDekStore();
    final service = BiometricService(authenticator: auth, store: store);
    final dek = Uint8List.fromList(List<int>.generate(32, (index) => index));

    await service.enable(dek);
    expect(await store.readDek(), orderedEquals(dek));

    await service.disable();
    expect(await store.readDek(), isNull);
  });

  test('enable rejects DEKs that are not 32 bytes', () async {
    final service = BiometricService(
      authenticator: FakeBiometricAuthenticator(
        canAuthenticate: true,
        succeeds: true,
      ),
      store: MemorySecureDekStore(),
    );

    expect(
      () => service.enable(Uint8List.fromList([1, 2, 3, 4])),
      throwsArgumentError,
    );
  });

  test('failed biometric returns fallback result with no DEK', () async {
    final service = BiometricService(
      authenticator: FakeBiometricAuthenticator(
        canAuthenticate: true,
        succeeds: false,
      ),
      store: MemorySecureDekStore()
        ..writeDek(Uint8List.fromList(List<int>.filled(32, 9))),
    );

    final result = await service.unlock();
    expect(result.status, BiometricUnlockStatus.fallbackToMasterPassword);
    expect(result.dek, isNull);
  });

  test('missing stored DEK returns fallback result', () async {
    final service = BiometricService(
      authenticator: FakeBiometricAuthenticator(
        canAuthenticate: true,
        succeeds: true,
      ),
      store: MemorySecureDekStore(),
    );

    final result = await service.unlock();
    expect(result.status, BiometricUnlockStatus.fallbackToMasterPassword);
    expect(result.dek, isNull);
  });

  test('invalid stored DEK length returns fallback result', () async {
    final service = BiometricService(
      authenticator: FakeBiometricAuthenticator(
        canAuthenticate: true,
        succeeds: true,
      ),
      store: MemorySecureDekStore()
        ..writeDek(Uint8List.fromList(List<int>.filled(31, 7))),
    );

    final result = await service.unlock();
    expect(result.status, BiometricUnlockStatus.fallbackToMasterPassword);
    expect(result.dek, isNull);
  });

  test('successful biometric returns unlocked result with DEK', () async {
    final dek = Uint8List.fromList(List<int>.generate(32, (index) => index));
    final service = BiometricService(
      authenticator: FakeBiometricAuthenticator(
        canAuthenticate: true,
        succeeds: true,
      ),
      store: MemorySecureDekStore()..writeDek(dek),
    );

    final result = await service.unlock();
    expect(result.status, BiometricUnlockStatus.unlocked);
    expect(result.dek, orderedEquals(dek));
  });
}
