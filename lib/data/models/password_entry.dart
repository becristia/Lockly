class PasswordEntry {
  const PasswordEntry({
    required this.title,
    required this.website,
    required this.username,
    required this.password,
    required this.notes,
    required this.tags,
  });

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
    'tags': tags,
  };

  factory PasswordEntry.fromJson(Map<String, Object?> json) {
    return PasswordEntry(
      title: json['title'] as String? ?? '',
      website: json['website'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .toList(growable: false),
    );
  }
}
