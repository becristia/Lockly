import 'package:secure_box/data/models/passkey_record.dart';

class PasswordEntry {
  PasswordEntry({
    required this.title,
    required this.website,
    required this.username,
    required this.password,
    required this.notes,
    required List<String> tags,
    this.totpSecret,
    this.passkey,
    this.isStandaloneTotp = false,
  }) : tags = List.unmodifiable(tags);

  final String title;
  final String website;
  final String username;
  final String password;
  final String notes;
  final List<String> tags;
  final String? totpSecret; // Base32 encoded TOTP key, null if not set
  final PasskeyRecord? passkey;
  final bool isStandaloneTotp;

  Map<String, Object?> toJson() => {
    'title': title,
    'website': website,
    'username': username,
    'password': password,
    'notes': notes,
    'tags': List<String>.unmodifiable(tags),
    if (totpSecret != null) 'totpSecret': totpSecret,
    if (passkey != null) 'passkey': passkey!.toJson(),
    if (isStandaloneTotp) 'isStandaloneTotp': true,
  };

  factory PasswordEntry.fromJson(Map<String, Object?> json) {
    final passkeyJson = json['passkey'];
    return PasswordEntry(
      title: _readRequiredString(json, 'title'),
      website: _readRequiredString(json, 'website'),
      username: _readRequiredString(json, 'username'),
      password: _readRequiredString(json, 'password'),
      notes: _readRequiredString(json, 'notes'),
      tags: _readRequiredStringList(json, 'tags'),
      totpSecret: json['totpSecret'] as String?,
      passkey: passkeyJson == null
          ? null
          : PasskeyRecord.fromJson(_readRequiredObject(json, 'passkey')),
      isStandaloneTotp:
          _readOptionalBool(json, 'isStandaloneTotp') ||
          _readOptionalBool(json, 'standaloneTotp'),
    );
  }

  static String _readRequiredString(Map<String, Object?> json, String field) {
    if (!json.containsKey(field)) {
      throw FormatException('Missing required field: $field');
    }

    final value = json[field];
    if (value is! String) {
      throw FormatException('Invalid "$field": expected a string');
    }

    return value;
  }

  static List<String> _readRequiredStringList(
    Map<String, Object?> json,
    String field,
  ) {
    if (!json.containsKey(field)) {
      throw FormatException('Missing required field: $field');
    }

    final value = json[field];
    if (value is! List<Object?>) {
      throw FormatException('Invalid "$field": expected a list of strings');
    }

    return value
        .asMap()
        .entries
        .map((entry) {
          final tag = entry.value;
          if (tag is! String) {
            throw FormatException(
              'Invalid "$field" entry at index ${entry.key}: expected a string',
            );
          }
          return tag;
        })
        .toList(growable: false);
  }

  static Map<String, Object?> _readRequiredObject(
    Map<String, Object?> json,
    String field,
  ) {
    final value = json[field];
    if (value is! Map<String, Object?>) {
      throw FormatException('Invalid "$field": expected an object');
    }
    return value;
  }

  static bool _readOptionalBool(Map<String, Object?> json, String field) {
    if (!json.containsKey(field)) {
      return false;
    }

    final value = json[field];
    if (value is! bool) {
      throw FormatException('Invalid "$field": expected a boolean');
    }
    return value;
  }
}
