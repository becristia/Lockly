enum MasterPasswordStrengthLabel { weak, fair, strong }

class MasterPasswordPolicyResult {
  const MasterPasswordPolicyResult({
    required this.isAcceptable,
    required this.label,
    required this.score,
    required this.message,
  });

  final bool isAcceptable;
  final MasterPasswordStrengthLabel label;
  final int score;
  final String message;
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
        message: '主密码至少需要 12 个字符',
      );
    }

    final forMatch = trimmed.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (_commonPasswords.contains(forMatch)) {
      return const MasterPasswordPolicyResult(
        isAcceptable: false,
        label: MasterPasswordStrengthLabel.weak,
        score: 1,
        message: '主密码不能是常见弱密码',
      );
    }

    if (_isRepeated(trimmed)) {
      return const MasterPasswordPolicyResult(
        isAcceptable: false,
        label: MasterPasswordStrengthLabel.weak,
        score: 1,
        message: '主密码不能由重复字符组成',
      );
    }

    if (_isKeyboardWalk(trimmed)) {
      return const MasterPasswordPolicyResult(
        isAcceptable: false,
        label: MasterPasswordStrengthLabel.weak,
        score: 1,
        message: '主密码不能是键盘序列',
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
        message: '请使用更长的密码短语，或混合大小写、数字和符号',
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
        message: '强：密码短语更容易记忆且更难猜',
      );
    }

    return MasterPasswordPolicyResult(
      isAcceptable: true,
      label: isStrong
          ? MasterPasswordStrengthLabel.strong
          : MasterPasswordStrengthLabel.fair,
      score: displayScore,
      message: isStrong ? '强：长度和字符组合较好' : '中：建议继续增强主密码',
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
        message: '密码不能为空',
      );
    }
    if (trimmed.length < minLength) {
      return const MasterPasswordPolicyResult(
        isAcceptable: false,
        label: MasterPasswordStrengthLabel.weak,
        score: 1,
        message: '建议至少 8 个字符',
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
        message: '密码过于常见或容易猜测',
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
      message: switch (label) {
        MasterPasswordStrengthLabel.strong => '强：适合作为保存的条目密码',
        MasterPasswordStrengthLabel.fair => '中：可用，但建议继续增强',
        MasterPasswordStrengthLabel.weak => '弱：建议生成更强密码',
      },
    );
  }
}
