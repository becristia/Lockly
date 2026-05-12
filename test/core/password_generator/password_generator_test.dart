import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/password_generator/password_generator.dart';

void main() {
  test('generated password has exact length and required classes', () {
    final generator = PasswordGenerator();
    final password = generator.generate(
      const PasswordGeneratorOptions(
        length: 24,
        lowercase: true,
        uppercase: true,
        numbers: true,
        symbols: true,
        excludeConfusing: true,
        requireEverySelectedClass: true,
      ),
    );

    expect(password.length, 24);
    expect(password, matches(RegExp(r'[a-z]')));
    expect(password, matches(RegExp(r'[A-Z]')));
    expect(password, matches(RegExp(r'[2-9]')));
    expect(password, matches(RegExp(r'[@#\$%\^&*()\-_=+\[\]{};:,.<>?]')));
    expect(password.contains(RegExp(r'[Oo1lI]')), isFalse);
  });

  test('throws when no character classes are selected', () {
    final generator = PasswordGenerator();
    expect(
      () => generator.generate(
        const PasswordGeneratorOptions(
          length: 16,
          lowercase: false,
          uppercase: false,
          numbers: false,
          symbols: false,
          excludeConfusing: false,
          requireEverySelectedClass: false,
        ),
      ),
      throwsA(isA<PasswordGeneratorException>()),
    );
  });
}
