import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/security/master_password_policy.dart';

void main() {
  group('MasterPasswordPolicy', () {
    test('rejects short passwords', () {
      final result = MasterPasswordPolicy.evaluate('short-7');

      expect(result.isAcceptable, isFalse);
      expect(result.label, MasterPasswordStrengthLabel.weak);
      expect(result.messageCode, PasswordPolicyMessageCode.masterMinLength);
    });

    test('rejects common weak passwords even when length is long enough', () {
      final result = MasterPasswordPolicy.evaluate('password123456');

      expect(result.isAcceptable, isFalse);
      expect(result.messageCode, PasswordPolicyMessageCode.masterCommonWeak);
    });

    test('rejects repeated single-character passwords', () {
      final result = MasterPasswordPolicy.evaluate('aaaaaaaaaaaa');

      expect(result.isAcceptable, isFalse);
      expect(result.messageCode, PasswordPolicyMessageCode.masterRepeated);
    });

    test('accepts long passphrases', () {
      final result = MasterPasswordPolicy.evaluate(
        'correct horse battery staple',
      );

      expect(result.isAcceptable, isTrue);
      expect(result.label, MasterPasswordStrengthLabel.strong);
      expect(
        result.messageCode,
        PasswordPolicyMessageCode.masterStrongPassphrase,
      );
    });

    test('accepts mixed random-looking passwords', () {
      final result = MasterPasswordPolicy.evaluate('R9!vK2#pL8@qZ4');

      expect(result.isAcceptable, isTrue);
      expect(result.label, MasterPasswordStrengthLabel.strong);
      expect(result.score, greaterThanOrEqualTo(4));
    });

    test('uses entry password strength for saved vault passwords', () {
      final result = EntryPasswordPolicy.evaluate('8aB!2cD#');

      expect(result.isAcceptable, isTrue);
      expect(result.label, MasterPasswordStrengthLabel.fair);
    });

    test('rejects common entry passwords as weak', () {
      final result = EntryPasswordPolicy.evaluate('password123456');

      expect(result.isAcceptable, isFalse);
      expect(result.label, MasterPasswordStrengthLabel.weak);
      expect(result.messageCode, PasswordPolicyMessageCode.entryCommonWeak);
    });
  });
}
