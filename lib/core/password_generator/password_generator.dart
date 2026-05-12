import 'dart:math';

import 'package:flutter/foundation.dart';

class PasswordGeneratorException implements Exception {
  const PasswordGeneratorException(this.message);

  final String message;

  @override
  String toString() => 'PasswordGeneratorException: $message';
}

class PasswordGeneratorOptions {
  const PasswordGeneratorOptions({
    required this.length,
    required this.lowercase,
    required this.uppercase,
    required this.numbers,
    required this.symbols,
    required this.excludeConfusing,
    required this.requireEverySelectedClass,
  });

  final int length;
  final bool lowercase;
  final bool uppercase;
  final bool numbers;
  final bool symbols;
  final bool excludeConfusing;
  final bool requireEverySelectedClass;
}

class PasswordGenerator {
  PasswordGenerator() : this._(Random.secure());

  @visibleForTesting
  factory PasswordGenerator.forTesting({required Random random}) {
    return PasswordGenerator._(random);
  }

  static const String _lowercase = 'abcdefghijklmnopqrstuvwxyz';
  static const String _uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _numbers = '0123456789';
  static const String _symbols = r'@#$%^&*()-_=+[]{};:,.<>?';
  static const String _confusing = 'Oo1lI';

  PasswordGenerator._(this._random);

  final Random _random;

  String generate(PasswordGeneratorOptions options) {
    if (options.length <= 0) {
      throw const PasswordGeneratorException(
        'Password length must be positive',
      );
    }

    final characterClasses = _buildCharacterClasses(options);
    if (characterClasses.isEmpty) {
      throw const PasswordGeneratorException(
        'At least one character class must be selected',
      );
    }

    if (options.requireEverySelectedClass &&
        options.length < characterClasses.length) {
      throw const PasswordGeneratorException(
        'Length is too short for the selected character classes',
      );
    }

    final allCharacters = characterClasses.join();
    final characters = <String>[];

    if (options.requireEverySelectedClass) {
      for (final characterClass in characterClasses) {
        characters.add(_pickCharacter(characterClass));
      }
    }

    while (characters.length < options.length) {
      characters.add(_pickCharacter(allCharacters));
    }

    _shuffle(characters);
    return characters.join();
  }

  List<String> _buildCharacterClasses(PasswordGeneratorOptions options) {
    final characterClasses = <String>[];

    if (options.lowercase) {
      characterClasses.add(_filterConfusing(_lowercase, options));
    }
    if (options.uppercase) {
      characterClasses.add(_filterConfusing(_uppercase, options));
    }
    if (options.numbers) {
      characterClasses.add(_filterConfusing(_numbers, options));
    }
    if (options.symbols) {
      characterClasses.add(_filterConfusing(_symbols, options));
    }

    return characterClasses.where((value) => value.isNotEmpty).toList();
  }

  String _filterConfusing(String characters, PasswordGeneratorOptions options) {
    if (!options.excludeConfusing) {
      return characters;
    }

    return characters
        .split('')
        .where((character) => !_confusing.contains(character))
        .join();
  }

  String _pickCharacter(String characters) {
    final index = _random.nextInt(characters.length);
    return characters[index];
  }

  void _shuffle(List<String> characters) {
    for (var i = characters.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final current = characters[i];
      characters[i] = characters[j];
      characters[j] = current;
    }
  }
}
