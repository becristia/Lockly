import 'dart:io';
import 'dart:math';

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

  test('throws when password length is zero or negative', () {
    final generator = PasswordGenerator();

    expect(
      () => generator.generate(
        const PasswordGeneratorOptions(
          length: 0,
          lowercase: true,
          uppercase: false,
          numbers: false,
          symbols: false,
          excludeConfusing: false,
          requireEverySelectedClass: false,
        ),
      ),
      throwsA(isA<PasswordGeneratorException>()),
    );
    expect(
      () => generator.generate(
        const PasswordGeneratorOptions(
          length: -1,
          lowercase: true,
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

  test('throws when required classes exceed requested length', () {
    final generator = PasswordGenerator();

    expect(
      () => generator.generate(
        const PasswordGeneratorOptions(
          length: 2,
          lowercase: true,
          uppercase: true,
          numbers: true,
          symbols: false,
          excludeConfusing: false,
          requireEverySelectedClass: true,
        ),
      ),
      throwsA(isA<PasswordGeneratorException>()),
    );
  });

  test('generated password stays within enabled subset of classes', () {
    final generator = PasswordGenerator();

    final password = generator.generate(
      const PasswordGeneratorOptions(
        length: 128,
        lowercase: true,
        uppercase: false,
        numbers: true,
        symbols: false,
        excludeConfusing: false,
        requireEverySelectedClass: true,
      ),
    );

    expect(password, matches(RegExp(r'^[a-z0-9]+$')));
  });

  test('public generator surface keeps RNG injection behind test-only API', () {
    final source = File(
      'lib/core/password_generator/password_generator.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('PasswordGenerator({Random? random})')));
    expect(source, contains('@visibleForTesting'));
    expect(source, contains('PasswordGenerator.forTesting'));
  });

  test('exclude confusing characters still allows zero for numeric output', () {
    final generator = PasswordGenerator.forTesting(random: _FixedRandom(0));

    final password = generator.generate(
      const PasswordGeneratorOptions(
        length: 1,
        lowercase: false,
        uppercase: false,
        numbers: true,
        symbols: false,
        excludeConfusing: true,
        requireEverySelectedClass: true,
      ),
    );

    expect(password, '0');
  });
}

class _FixedRandom implements Random {
  _FixedRandom(this._value);

  final int _value;

  @override
  bool nextBool() => _value.isEven;

  @override
  double nextDouble() => _value.toDouble();

  @override
  int nextInt(int max) => _value % max;
}
