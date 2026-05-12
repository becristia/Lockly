class PasswordEntry {
  PasswordEntry({
    required this.title,
    required this.website,
    required this.username,
    required this.password,
    required this.notes,
    required List<String> tags,
  }) : tags = List.unmodifiable(tags);

  final String title;
  final String website;
  final String username;
  final String password;
  final String notes;
  final List<String> tags;

  Map<String, Object?> toJson() => {
    'title': title,
    'website': website,
    'username': username,
    'password': password,
    'notes': notes,
    'tags': List<String>.from(tags, growable: false),
  };

  factory PasswordEntry.fromJson(Map<String, Object?> json) {
    return PasswordEntry(
      title: _readRequiredString(json, 'title'),
      website: _readRequiredString(json, 'website'),
      username: _readRequiredString(json, 'username'),
      password: _readRequiredString(json, 'password'),
      notes: _readRequiredString(json, 'notes'),
      tags: _readRequiredStringList(json, 'tags'),
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
}
