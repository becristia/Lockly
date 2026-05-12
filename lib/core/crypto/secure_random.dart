import 'dart:math';
import 'dart:typed_data';

class SecureRandom {
  final Random _random = Random.secure();

  Uint8List bytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }

  Uint8List nonce12() => bytes(12);
}
