import 'package:secure_box/data/db/app_database.dart';

class VaultManifest {
  const VaultManifest({
    required this.version,
    required this.epoch,
    required this.counter,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    required this.updatedAt,
  });

  final int version;
  final int epoch;
  final int counter;
  final String nonce;
  final String ciphertext;
  final String mac;
  final int updatedAt;

  Map<String, Object?> toDb() {
    return {
      'singleton_key': AppDatabase.vaultManifestSingletonKey,
      'version': version,
      'epoch': epoch,
      'counter': counter,
      'nonce': nonce,
      'ciphertext': ciphertext,
      'mac': mac,
      'updated_at': updatedAt,
    };
  }

  factory VaultManifest.fromDb(Map<String, Object?> row) {
    return VaultManifest(
      version: _readRequiredInt(row, 'version'),
      epoch: _readRequiredInt(row, 'epoch'),
      counter: _readRequiredInt(row, 'counter'),
      nonce: _readRequiredString(row, 'nonce'),
      ciphertext: _readRequiredString(row, 'ciphertext'),
      mac: _readRequiredString(row, 'mac'),
      updatedAt: _readRequiredInt(row, 'updated_at'),
    );
  }

  VaultManifest copyWith({
    int? version,
    int? epoch,
    int? counter,
    String? nonce,
    String? ciphertext,
    String? mac,
    int? updatedAt,
  }) {
    return VaultManifest(
      version: version ?? this.version,
      epoch: epoch ?? this.epoch,
      counter: counter ?? this.counter,
      nonce: nonce ?? this.nonce,
      ciphertext: ciphertext ?? this.ciphertext,
      mac: mac ?? this.mac,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static int _readRequiredInt(Map<String, Object?> row, String field) {
    final value = row[field];
    if (value is! int) {
      throw FormatException('Invalid "$field": expected an int');
    }

    return value;
  }

  static String _readRequiredString(Map<String, Object?> row, String field) {
    final value = row[field];
    if (value is! String) {
      throw FormatException('Invalid "$field": expected a string');
    }

    return value;
  }
}
