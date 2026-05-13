import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/password_generator/password_generator.dart';

void main() {
  test(
    'generated password deterministically includes every selected class',
    () {
      final generator = PasswordGenerator.forTesting(
        random: _SequenceRandom([0, 0, 0, 1, 3, 2, 1]),
      );
      final password = generator.generate(
        const PasswordGeneratorOptions(
          length: 4,
          lowercase: true,
          uppercase: true,
          numbers: true,
          symbols: true,
          excludeConfusing: true,
          requireEverySelectedClass: true,
        ),
      );

      expect(password, 'aA0@');
      expect(password.length, 4);
      expect(password, matches(RegExp(r'[a-z]')));
      expect(password, matches(RegExp(r'[A-Z]')));
      expect(password, matches(RegExp(r'[0-9]')));
      expect(password, matches(RegExp(r'[!@#\$%\^&*()\-_=+\[\]{};:,.<>?]')));
      expect(password.contains(RegExp(r'[Oo1lI]')), isFalse);
    },
  );

  test('symbols-only generation can emit the documented exclamation mark', () {
    final generator = PasswordGenerator.forTesting(
      random: _SequenceRandom([0]),
    );

    final password = generator.generate(
      const PasswordGeneratorOptions(
        length: 1,
        lowercase: false,
        uppercase: false,
        numbers: false,
        symbols: true,
        excludeConfusing: false,
        requireEverySelectedClass: true,
      ),
    );

    expect(password, '!');
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
    final generator = PasswordGenerator.forTesting(
      random: _SequenceRandom([0, 1, 0]),
    );

    final password = generator.generate(
      const PasswordGeneratorOptions(
        length: 2,
        lowercase: true,
        uppercase: false,
        numbers: true,
        symbols: false,
        excludeConfusing: false,
        requireEverySelectedClass: true,
      ),
    );

    expect(password, '1a');
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

  test(
    'exclude confusing characters deterministically strips O o 1 l and I',
    () {
      final lowercaseGenerator = PasswordGenerator.forTesting(
        random: _SequenceRandom([11, 14, 1]),
      );
      final uppercaseGenerator = PasswordGenerator.forTesting(
        random: _SequenceRandom([8, 13, 1]),
      );
      final numbersGenerator = PasswordGenerator.forTesting(
        random: _SequenceRandom([1]),
      );

      final lowercasePassword = lowercaseGenerator.generate(
        const PasswordGeneratorOptions(
          length: 2,
          lowercase: true,
          uppercase: false,
          numbers: false,
          symbols: false,
          excludeConfusing: true,
          requireEverySelectedClass: false,
        ),
      );
      final uppercasePassword = uppercaseGenerator.generate(
        const PasswordGeneratorOptions(
          length: 2,
          lowercase: false,
          uppercase: true,
          numbers: false,
          symbols: false,
          excludeConfusing: true,
          requireEverySelectedClass: false,
        ),
      );
      final numbersPassword = numbersGenerator.generate(
        const PasswordGeneratorOptions(
          length: 1,
          lowercase: false,
          uppercase: false,
          numbers: true,
          symbols: false,
          excludeConfusing: true,
          requireEverySelectedClass: false,
        ),
      );

      expect(lowercasePassword, 'mq');
      expect(uppercasePassword, 'JP');
      expect(numbersPassword, '2');
      expect(
        '$lowercasePassword$uppercasePassword$numbersPassword',
        isNot(matches(RegExp(r'[Oo1lI]'))),
      );
    },
  );

  test('exclude confusing characters still allows zero for numeric output', () {
    final generator = PasswordGenerator.forTesting(
      random: _SequenceRandom([0]),
    );

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

class _SequenceRandom implements Random {
  _SequenceRandom(this._values);

  final List<int> _values;
  int _index = 0;

  int _nextValue() {
    if (_index >= _values.length) {
      throw StateError('No more deterministic random values available');
    }

    return _values[_index++];
  }

  @override
  bool nextBool() => _nextValue().isEven;

  @override
  double nextDouble() => _nextValue().toDouble();

  @override
  int nextInt(int max) => _nextValue() % max;
}
