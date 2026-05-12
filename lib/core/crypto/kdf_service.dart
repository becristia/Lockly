import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class KdfParams {
  const KdfParams({
    required this.name,
    required this.iterations,
    required this.bits,
  });

  factory KdfParams.pbkdf2({int iterations = 120000, int bits = 256}) {
    return KdfParams(
      name: 'pbkdf2-hmac-sha256',
      iterations: iterations,
      bits: bits,
    );
  }

  final String name;
  final int iterations;
  final int bits;

  Map<String, Object> toJson() => {
    'name': name,
    'iterations': iterations,
    'bits': bits,
  };

  factory KdfParams.fromJson(Map<String, Object?> json) {
    return KdfParams(
      name: json['name'] as String,
      iterations: json['iterations'] as int,
      bits: json['bits'] as int,
    );
  }
}

class KdfService {
  Future<Uint8List> deriveKey({
    required String password,
    required Uint8List salt,
    required KdfParams params,
  }) async {
    if (params.name != 'pbkdf2-hmac-sha256') {
      throw ArgumentError.value(params.name, 'params.name', 'Unsupported KDF');
    }
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: params.iterations,
      bits: params.bits,
    );
    final secretKey = await algorithm.deriveKey(
      secretKey: SecretKey(password.codeUnits),
      nonce: salt,
    );
    return Uint8List.fromList(await secretKey.extractBytes());
  }
}
