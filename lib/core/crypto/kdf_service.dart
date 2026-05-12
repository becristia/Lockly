import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const int _minimumPbkdf2Iterations = 100000;
const int _requiredDerivedKeyBits = 256;
const int _minimumSaltLength = 16;

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
    if (params.iterations <= 0) {
      throw ArgumentError.value(
        params.iterations,
        'params.iterations',
        'PBKDF2 iterations must be greater than zero',
      );
    }
    if (params.iterations < _minimumPbkdf2Iterations) {
      throw ArgumentError.value(
        params.iterations,
        'params.iterations',
        'PBKDF2 iterations must be at least $_minimumPbkdf2Iterations for this MVP',
      );
    }
    if (salt.length < _minimumSaltLength) {
      throw ArgumentError.value(
        salt.length,
        'salt',
        'Salt must be at least $_minimumSaltLength bytes',
      );
    }
    if (params.bits != _requiredDerivedKeyBits) {
      throw ArgumentError.value(
        params.bits,
        'params.bits',
        'Only $_requiredDerivedKeyBits-bit PBKDF2 output is supported',
      );
    }
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: params.iterations,
      bits: params.bits,
    );
    final secretKey = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return Uint8List.fromList(await secretKey.extractBytes());
  }
}
