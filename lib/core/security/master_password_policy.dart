enum MasterPasswordStrengthLabel { weak, fair, strong }

enum PasswordPolicyMessageCode {
  masterMinLength,
  masterCommonWeak,
  masterRepeated,
  masterKeyboardWalk,
  masterUseLongerPassphrase,
  masterStrongPassphrase,
  masterStrongMixed,
  masterFairImprove,
  entryEmpty,
  entryMinLength,
  entryCommonWeak,
  entryStrong,
  entryFair,
  entryWeak,
}

class MasterPasswordPolicyResult {
  const MasterPasswordPolicyResult({
    required this.isAcceptable,
    required this.label,
    required this.score,
    required this.messageCode,
  });

  final bool isAcceptable;
  final MasterPasswordStrengthLabel label;
  final int score;
  final PasswordPolicyMessageCode messageCode;

  String get message => _messageForCode(messageCode);
}

String _messageForCode(PasswordPolicyMessageCode code) {
  return switch (code) {
    PasswordPolicyMessageCode.masterMinLength => 'masterMinLength',
    PasswordPolicyMessageCode.masterCommonWeak => 'masterCommonWeak',
    PasswordPolicyMessageCode.masterRepeated => 'masterRepeated',
    PasswordPolicyMessageCode.masterKeyboardWalk => 'masterKeyboardWalk',
    PasswordPolicyMessageCode.masterUseLongerPassphrase =>
      'masterUseLongerPassphrase',
    PasswordPolicyMessageCode.masterStrongPassphrase =>
      'masterStrongPassphrase',
    PasswordPolicyMessageCode.masterStrongMixed => 'masterStrongMixed',
    PasswordPolicyMessageCode.masterFairImprove => 'masterFairImprove',
    PasswordPolicyMessageCode.entryEmpty => 'entryEmpty',
    PasswordPolicyMessageCode.entryMinLength => 'entryMinLength',
    PasswordPolicyMessageCode.entryCommonWeak => 'entryCommonWeak',
    PasswordPolicyMessageCode.entryStrong => 'entryStrong',
    PasswordPolicyMessageCode.entryFair => 'entryFair',
    PasswordPolicyMessageCode.entryWeak => 'entryWeak',
  };
}

class MasterPasswordPolicy {
  static const minLength = 12;

  static const _commonPasswords = <String>{
    'password',
    'password1',
    'password12',
    'password123',
    'password1234',
    'password12345',
    'password123456',
    'password1234567',
    'password12345678',
    'password123456789',
    '123456789012',
    '1234567890',
    '123456789',
    'qwerty123456',
    'qwertyuiop12',
    'qwertyuiop',
    'qwerty123',
    'admin123456',
    'admin123',
    'administrator',
    'letmein123456',
    'iloveyou123456',
    'monkey123456',
    'dragon123456',
    'master123456',
    'abc123456789',
    'trustno1123',
    'welcome1234',
    'login123456',
    'princess1234',
    'sunshine123',
    'football123',
    'baseball123',
    'hunter12345',
    'michael1234',
    'shadow12345',
    '654321',
    '123321',
    '111111111111',
    '000000000000',
    '121212121212',
    'qazwsx123456',
    '1q2w3e4r5t6y',
    'zxcvbn123456',
    'asdfgh123456',
    'zaq12wsxcde',
    '!qaz2wsx3edc',
    '#edc4rfv5tgb',
    'passw0rd12345',
    'p@ssword123',
    'P@ssw0rd12345',
    'Pa\$\$word1234',
    'changeme1234',
    'secret123456',
    'access123456',
    'abc123!@#',
    'test12345678',
  };

  // Note: Unicode NFC normalization is not applied.
  // Dart lacks built-in NFC; would require a package like `unicode_normalization`.
  static MasterPasswordPolicyResult evaluate(String password) {
    final trimmed = password.trim();
    if (trimmed.length < minLength) {
      return const MasterPasswordPolicyResult(
        isAcceptable: false,
        label: MasterPasswordStrengthLabel.weak,
        score: 0,
        messageCode: PasswordPolicyMessageCode.masterMinLength,
      );
    }

    final forMatch = trimmed.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (_commonPasswords.contains(forMatch)) {
      return const MasterPasswordPolicyResult(
        isAcceptable: false,
        label: MasterPasswordStrengthLabel.weak,
        score: 1,
        messageCode: PasswordPolicyMessageCode.masterCommonWeak,
      );
    }

    if (_isRepeated(trimmed)) {
      return const MasterPasswordPolicyResult(
        isAcceptable: false,
        label: MasterPasswordStrengthLabel.weak,
        score: 1,
        messageCode: PasswordPolicyMessageCode.masterRepeated,
      );
    }

    if (_isKeyboardWalk(trimmed)) {
      return const MasterPasswordPolicyResult(
        isAcceptable: false,
        label: MasterPasswordStrengthLabel.weak,
        score: 1,
        messageCode: PasswordPolicyMessageCode.masterKeyboardWalk,
      );
    }

    final score = _score(trimmed);
    final isPassphrase = _isPassphrase(trimmed);
    final hasAllCharacterClasses = _classCount(trimmed) >= 4;
    final hasDictionaryWeakness = _hasDictionaryPattern(trimmed);
    final adjustedScore = hasDictionaryWeakness
        ? (score - 1).clamp(0, 5)
        : score;

    final isAcceptable = isPassphrase || adjustedScore >= 3;
    if (!isAcceptable) {
      return MasterPasswordPolicyResult(
        isAcceptable: false,
        label: MasterPasswordStrengthLabel.weak,
        score: adjustedScore,
        messageCode: PasswordPolicyMessageCode.masterUseLongerPassphrase,
      );
    }

    final isStrong =
        (adjustedScore >= 4 && !hasDictionaryWeakness) ||
        isPassphrase ||
        (hasAllCharacterClasses &&
            trimmed.length >= 14 &&
            !hasDictionaryWeakness);
    final displayScore = isStrong ? adjustedScore.clamp(4, 5) : adjustedScore;
    if (isPassphrase) {
      return MasterPasswordPolicyResult(
        isAcceptable: true,
        label: isStrong
            ? MasterPasswordStrengthLabel.strong
            : MasterPasswordStrengthLabel.fair,
        score: displayScore,
        messageCode: PasswordPolicyMessageCode.masterStrongPassphrase,
      );
    }

    return MasterPasswordPolicyResult(
      isAcceptable: true,
      label: isStrong
          ? MasterPasswordStrengthLabel.strong
          : MasterPasswordStrengthLabel.fair,
      score: displayScore,
      messageCode: isStrong
          ? PasswordPolicyMessageCode.masterStrongMixed
          : PasswordPolicyMessageCode.masterFairImprove,
    );
  }

  static bool _isKeyboardWalk(String password) {
    final lower = password.toLowerCase();
    const rows = <String>[
      '`1234567890-=',
      'qwertyuiop[]\\',
      'asdfghjkl;\'',
      'zxcvbnm,./',
    ];
    for (final row in rows) {
      for (var i = 0; i <= row.length - 3; i++) {
        final forward = row.substring(i, i + 3);
        final backward = String.fromCharCodes(forward.runes.toList().reversed);
        if (lower.contains(forward) || lower.contains(backward)) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _hasDictionaryPattern(String password) {
    final lower = password.toLowerCase();
    final dictionaryWords = <String>[
      'password',
      'admin',
      'login',
      'welcome',
      'letmein',
      'monkey',
      'dragon',
      'master',
      'sunshine',
      'princess',
      'football',
      'baseball',
      'hunter',
      'shadow',
      'trustno',
      'secret',
      'access',
      'changeme',
      'abc123',
      'qwerty',
      'asdfgh',
      'zxcvbn',
      'iloveyou',
    ];
    for (final word in dictionaryWords) {
      if (lower.contains(word)) {
        return true;
      }
    }
    return false;
  }

  static bool _isRepeated(String password) {
    if (RegExp(r'^(.)\1+$').hasMatch(password)) {
      return true;
    }
    for (var unitLength = 1; unitLength <= password.length ~/ 2; unitLength++) {
      if (password.length % unitLength != 0) {
        continue;
      }
      final unit = password.substring(0, unitLength);
      if (unit * (password.length ~/ unitLength) == password) {
        return true;
      }
    }
    return false;
  }

  static int _score(String password) {
    var score = 0;
    if (password.length >= minLength) {
      score += 1;
    }
    if (password.length >= 16) {
      score += 1;
    }
    if (password.length >= 20) {
      score += 1;
    }
    final classCount = _classCount(password);
    if (classCount >= 4) {
      score += 1;
    }
    if (classCount == 4 && password.length >= 14) {
      score += 1;
    }
    if (classCount == 4 && password.length >= 16) {
      score += 1;
    }
    if (_isPassphrase(password)) {
      score += 2;
    }
    return score.clamp(0, 5);
  }

  static int _classCount(String password) {
    var count = 0;
    if (RegExp(r'[a-z]').hasMatch(password)) {
      count += 1;
    }
    if (RegExp(r'[A-Z]').hasMatch(password)) {
      count += 1;
    }
    if (RegExp(r'\d').hasMatch(password)) {
      count += 1;
    }
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      count += 1;
    }
    return count;
  }

  static bool _isPassphrase(String password) {
    final words = password
        .trim()
        .split(RegExp(r'[\s\-_]+'))
        .where((part) => part.length >= 3)
        .length;
    return password.length >= 20 && words >= 3;
  }
}

class EntryPasswordPolicy {
  static const minLength = 8;

  static MasterPasswordPolicyResult evaluate(String password) {
    final trimmed = password.trim();
    if (trimmed.isEmpty) {
      return const MasterPasswordPolicyResult(
        isAcceptable: false,
        label: MasterPasswordStrengthLabel.weak,
        score: 0,
        messageCode: PasswordPolicyMessageCode.entryEmpty,
      );
    }
    if (trimmed.length < minLength) {
      return const MasterPasswordPolicyResult(
        isAcceptable: false,
        label: MasterPasswordStrengthLabel.weak,
        score: 1,
        messageCode: PasswordPolicyMessageCode.entryMinLength,
      );
    }

    final forMatch = trimmed.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (MasterPasswordPolicy._commonPasswords.contains(forMatch) ||
        MasterPasswordPolicy._isRepeated(trimmed) ||
        MasterPasswordPolicy._isKeyboardWalk(trimmed)) {
      return const MasterPasswordPolicyResult(
        isAcceptable: false,
        label: MasterPasswordStrengthLabel.weak,
        score: 1,
        messageCode: PasswordPolicyMessageCode.entryCommonWeak,
      );
    }

    var score = 0;
    if (trimmed.length >= minLength) {
      score += 1;
    }
    if (trimmed.length >= 12) {
      score += 1;
    }
    if (trimmed.length >= 16) {
      score += 1;
    }
    final classCount = MasterPasswordPolicy._classCount(trimmed);
    if (classCount >= 3) {
      score += 1;
    }
    if (classCount == 4) {
      score += 1;
    }
    if (MasterPasswordPolicy._isPassphrase(trimmed)) {
      score += 2;
    }
    if (MasterPasswordPolicy._hasDictionaryPattern(trimmed)) {
      score -= 1;
    }

    final adjustedScore = score.clamp(0, 5);
    final label = switch (adjustedScore) {
      >= 4 => MasterPasswordStrengthLabel.strong,
      >= 3 => MasterPasswordStrengthLabel.fair,
      _ => MasterPasswordStrengthLabel.weak,
    };
    return MasterPasswordPolicyResult(
      isAcceptable: adjustedScore >= 3,
      label: label,
      score: adjustedScore,
      messageCode: switch (label) {
        MasterPasswordStrengthLabel.strong =>
          PasswordPolicyMessageCode.entryStrong,
        MasterPasswordStrengthLabel.fair => PasswordPolicyMessageCode.entryFair,
        MasterPasswordStrengthLabel.weak => PasswordPolicyMessageCode.entryWeak,
      },
    );
  }
}
