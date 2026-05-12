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
      id: row['id'] as String,
      nonce: row['nonce'] as String,
      ciphertext: row['ciphertext'] as String,
      mac: row['mac'] as String,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
      deletedAt: row['deleted_at'] as int?,
    );
  }
}
