class EncryptedVaultItem {
  const EncryptedVaultItem({
    required this.id,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String nonce;
  final String ciphertext;
  final String mac;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  Map<String, Object?> toDb() => {
    'id': id,
    'nonce': nonce,
    'ciphertext': ciphertext,
    'mac': mac,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
  };

  factory EncryptedVaultItem.fromDb(Map<String, Object?> row) {
    return EncryptedVaultItem(
      id: _readRequiredString(row, 'id'),
      nonce: _readRequiredString(row, 'nonce'),
      ciphertext: _readRequiredString(row, 'ciphertext'),
      mac: _readRequiredString(row, 'mac'),
      createdAt: _readRequiredInt(row, 'created_at'),
      updatedAt: _readRequiredInt(row, 'updated_at'),
      deletedAt: _readNullableInt(row, 'deleted_at'),
    );
  }

  static String _readRequiredString(Map<String, Object?> row, String field) {
    final value = row[field];
    if (value is! String) {
      throw FormatException('Invalid "$field": expected a string');
    }

    return value;
  }

  static int _readRequiredInt(Map<String, Object?> row, String field) {
    final value = row[field];
    if (value is! int) {
      throw FormatException('Invalid "$field": expected an int');
    }

    return value;
  }

  static int? _readNullableInt(Map<String, Object?> row, String field) {
    final value = row[field];
    if (value == null) {
      return null;
    }
    if (value is! int) {
      throw FormatException('Invalid "$field": expected an int or null');
    }

    return value;
  }
}
