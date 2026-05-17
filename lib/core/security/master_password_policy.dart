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
    '123456789012',
    'qwerty123456',
    'qwertyuiop12',
    'admin123456',
    'letmein123456',
    'iloveyou123456',
  };

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

    final normalized = trimmed.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (_commonPasswords.contains(normalized)) {
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

    final score = _score(trimmed);
    final isPassphrase = _isPassphrase(trimmed);
    final hasAllCharacterClasses = _classCount(trimmed) >= 4;
    final isAcceptable = isPassphrase || score >= 3;
    if (!isAcceptable) {
      return MasterPasswordPolicyResult(
        isAcceptable: false,
        label: MasterPasswordStrengthLabel.weak,
        score: score,
        message: '请使用更长的密码短语，或混合大小写、数字和符号',
      );
    }

    final isStrong = score >= 4 || isPassphrase || hasAllCharacterClasses;
    if (isPassphrase) {
      return MasterPasswordPolicyResult(
        isAcceptable: true,
        label: isStrong
            ? MasterPasswordStrengthLabel.strong
            : MasterPasswordStrengthLabel.fair,
        score: score,
        message: '强：密码短语更容易记忆且更难猜',
      );
    }

    return MasterPasswordPolicyResult(
      isAcceptable: true,
      label: isStrong
          ? MasterPasswordStrengthLabel.strong
          : MasterPasswordStrengthLabel.fair,
      score: score,
      message: isStrong ? '强：长度和字符组合较好' : '中：建议继续增强主密码',
    );
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
    if (classCount >= 3) {
      score += 1;
    }
    if (classCount >= 4) {
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
