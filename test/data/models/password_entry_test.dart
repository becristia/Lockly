import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/data/models/password_entry.dart';

void main() {
  test(
    'password entry serializes all sensitive fields inside one JSON payload',
    () {
      final entry = PasswordEntry(
        title: 'GitHub',
        website: 'https://github.com',
        username: 'user@example.com',
        password: 'secret-password',
        notes: 'recovery codes stored offline',
        tags: const ['dev', 'important'],
      );

      final encoded = jsonEncode(entry.toJson());
      final decoded = PasswordEntry.fromJson(
        jsonDecode(encoded) as Map<String, Object?>,
      );

      expect(decoded.title, 'GitHub');
      expect(decoded.website, 'https://github.com');
      expect(decoded.username, 'user@example.com');
      expect(decoded.password, 'secret-password');
      expect(decoded.notes, 'recovery codes stored offline');
      expect(decoded.tags, ['dev', 'important']);
    },
  );
}
