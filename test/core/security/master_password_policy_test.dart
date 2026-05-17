import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/security/master_password_policy.dart';

void main() {
  group('MasterPasswordPolicy', () {
    test('rejects short passwords', () {
      final result = MasterPasswordPolicy.evaluate('short-7');

      expect(result.isAcceptable, isFalse);
      expect(result.label, MasterPasswordStrengthLabel.weak);
      expect(result.message, contains('12'));
    });

    test('rejects common weak passwords even when length is long enough', () {
      final result = MasterPasswordPolicy.evaluate('password123456');

      expect(result.isAcceptable, isFalse);
      expect(result.message, contains('常见'));
    });

    test('rejects repeated single-character passwords', () {
      final result = MasterPasswordPolicy.evaluate('aaaaaaaaaaaa');

      expect(result.isAcceptable, isFalse);
      expect(result.message, contains('重复'));
    });

    test('accepts long passphrases', () {
      final result = MasterPasswordPolicy.evaluate(
        'correct horse battery staple',
      );

      expect(result.isAcceptable, isTrue);
      expect(result.label, MasterPasswordStrengthLabel.strong);
      expect(result.message, contains('强'));
    });

    test('accepts mixed random-looking passwords', () {
      final result = MasterPasswordPolicy.evaluate('R9!vK2#pL8@qZ4');

      expect(result.isAcceptable, isTrue);
      expect(result.label, MasterPasswordStrengthLabel.strong);
    });
  });
}
