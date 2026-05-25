enum AppLanguage { zh, en }

extension AppLanguageX on AppLanguage {
  static AppLanguage parse(String? value) {
    return switch (value) {
      'en' => AppLanguage.en,
      'zh' => AppLanguage.zh,
      _ => AppLanguage.zh,
    };
  }

  String get code => switch (this) {
    AppLanguage.zh => 'zh',
    AppLanguage.en => 'en',
  };

  String get displayName => switch (this) {
    AppLanguage.zh => '中文',
    AppLanguage.en => 'English',
  };
}
