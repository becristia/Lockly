import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:hashlib/hashlib.dart' as hashlib;

const int _minimumPbkdf2Iterations = 100000;
const int _minimumArgon2MemoryKiB = 1024;
const int _minimumArgon2Iterations = 1;
const int _minimumArgon2Parallelism = 1;
const int _requiredDerivedKeyBits = 256;
const int _minimumSaltLength = 16;

class KdfParams {
  const KdfParams({
    required this.name,
    required this.iterations,
    required this.bits,
    this.memoryKiB,
    this.parallelism,
  });

  factory KdfParams.pbkdf2({int iterations = 120000, int bits = 256}) {
    return KdfParams(
      name: 'pbkdf2-hmac-sha256',
      iterations: iterations,
      bits: bits,
    );
  }

  factory KdfParams.argon2id({
    int memoryKiB = 65536,
    int iterations = 3,
    int parallelism = 1,
    int bits = 256,
  }) {
    return KdfParams(
      name: 'argon2id',
      iterations: iterations,
      bits: bits,
      memoryKiB: memoryKiB,
      parallelism: parallelism,
    );
  }

  final String name;
  final int iterations;
  final int bits;
  final int? memoryKiB;
  final int? parallelism;

  Map<String, Object> toJson() {
    final json = <String, Object>{
      'name': name,
      'iterations': iterations,
      'bits': bits,
    };
    if (name == 'argon2id') {
      json['memoryKiB'] = memoryKiB ?? 65536;
      json['parallelism'] = parallelism ?? 1;
    }
    return json;
  }

  factory KdfParams.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final iterations = json['iterations'];
    final bits = json['bits'];
    if (name is! String || iterations is! int || bits is! int) {
      throw const FormatException(
        'Invalid kdf_params JSON object: expected string name and integer iterations/bits',
      );
    }
    if (name == 'pbkdf2-hmac-sha256') {
      return KdfParams.pbkdf2(iterations: iterations, bits: bits);
    }
    if (name == 'argon2id') {
      final memoryKiB = json['memoryKiB'];
      final parallelism = json['parallelism'];
      if (memoryKiB is! int || parallelism is! int) {
        throw const FormatException(
          'Invalid argon2id kdf_params JSON object: expected integer memoryKiB/parallelism',
        );
      }
      return KdfParams.argon2id(
        memoryKiB: memoryKiB,
        iterations: iterations,
        parallelism: parallelism,
        bits: bits,
      );
    }
    throw FormatException('Unsupported KDF: $name');
  }
}

class KdfService {
  Future<Uint8List> deriveKey({
    required String password,
    required Uint8List salt,
    required KdfParams params,
  }) async {
    if (params.name == 'pbkdf2-hmac-sha256') {
      return _derivePbkdf2(password: password, salt: salt, params: params);
    }
    if (params.name == 'argon2id') {
      return _deriveArgon2id(password: password, salt: salt, params: params);
    }
    throw ArgumentError.value(params.name, 'params.name', 'Unsupported KDF');
  }

  Future<Uint8List> _derivePbkdf2({
    required String password,
    required Uint8List salt,
    required KdfParams params,
  }) async {
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
    _validateCommonSaltAndBits(salt: salt, bits: params.bits);
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

  Future<Uint8List> _deriveArgon2id({
    required String password,
    required Uint8List salt,
    required KdfParams params,
  }) async {
    _validateCommonSaltAndBits(salt: salt, bits: params.bits);
    final memoryKiB = params.memoryKiB;
    final parallelism = params.parallelism;
    if (memoryKiB == null || memoryKiB < _minimumArgon2MemoryKiB) {
      throw ArgumentError.value(
        memoryKiB,
        'params.memoryKiB',
        'Argon2id memoryKiB must be at least $_minimumArgon2MemoryKiB',
      );
    }
    if (params.iterations < _minimumArgon2Iterations) {
      throw ArgumentError.value(
        params.iterations,
        'params.iterations',
        'Argon2id iterations must be at least $_minimumArgon2Iterations',
      );
    }
    if (parallelism == null || parallelism < _minimumArgon2Parallelism) {
      throw ArgumentError.value(
        parallelism,
        'params.parallelism',
        'Argon2id parallelism must be at least $_minimumArgon2Parallelism',
      );
    }

    final algorithm = hashlib.Argon2(
      type: hashlib.Argon2Type.argon2id,
      version: hashlib.Argon2Version.v13,
      parallelism: parallelism,
      memorySizeKB: memoryKiB,
      iterations: params.iterations,
      hashLength: params.bits ~/ 8,
      salt: salt,
    );
    final digest = algorithm.convert(utf8.encode(password));
    return Uint8List.fromList(digest.bytes);
  }

  void _validateCommonSaltAndBits({
    required Uint8List salt,
    required int bits,
  }) {
    if (salt.length < _minimumSaltLength) {
      throw ArgumentError.value(
        salt.length,
        'salt',
        'Salt must be at least $_minimumSaltLength bytes',
      );
    }
    if (bits != _requiredDerivedKeyBits) {
      throw ArgumentError.value(
        bits,
        'params.bits',
        'Only $_requiredDerivedKeyBits-bit KDF output is supported',
      );
    }
  }
}
