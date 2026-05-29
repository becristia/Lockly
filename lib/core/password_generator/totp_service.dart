import 'package:otp/otp.dart';

class ParsedOtpAuth {
  const ParsedOtpAuth({required this.secret, this.label, this.issuer});
  final String secret;
  final String? label;
  final String? issuer;
}

class TotpService {
  static final RegExp _base32SecretPattern = RegExp(r'^[A-Z2-7]+$');
  static const Set<int> _validUnpaddedBase32Remainders = {0, 2, 4, 5, 7};

  String generate({
    required String base32Secret,
    required int timestampMs,
    int length = 6,
    int interval = 30,
    Algorithm algorithm = Algorithm.SHA1,
  }) {
    return OTP.generateTOTPCodeString(
      base32Secret,
      timestampMs,
      length: length,
      interval: interval,
      algorithm: algorithm,
      isGoogle: true,
    );
  }

  int remainingSeconds(int timestampMs, {int interval = 30}) {
    final seconds = timestampMs ~/ 1000;
    final elapsed = seconds % interval;
    return interval - elapsed;
  }

  static ParsedOtpAuth parseOtpauthUrl(String url) {
    final uri = Uri.parse(url);
    if (uri.scheme.toLowerCase() != 'otpauth') {
      throw const FormatException('Invalid otpauth URL scheme');
    }
    if (uri.host.toLowerCase() != 'totp') {
      throw const FormatException('Only otpauth TOTP URLs are supported');
    }
    _validateSupportedOtpParameter(
      uri.queryParameters['algorithm'],
      supportedValue: 'SHA1',
      parameter: 'algorithm',
    );
    _validateSupportedOtpParameter(
      uri.queryParameters['digits'],
      supportedValue: '6',
      parameter: 'digits',
    );
    _validateSupportedOtpParameter(
      uri.queryParameters['period'],
      supportedValue: '30',
      parameter: 'period',
    );
    final secret = _normalizeBase32Secret(uri.queryParameters['secret'] ?? '');
    String? label;
    if (uri.pathSegments.isNotEmpty) {
      label = Uri.decodeComponent(uri.pathSegments.first);
    }
    final issuer = uri.queryParameters['issuer'];
    return ParsedOtpAuth(secret: secret, label: label, issuer: issuer);
  }

  static String normalizeSecret(String input) {
    final trimmed = input.trim();
    if (trimmed.toLowerCase().startsWith('otpauth://')) {
      return parseOtpauthUrl(trimmed).secret;
    }

    return _normalizeBase32Secret(trimmed);
  }

  static bool isValidSecret(String input) {
    try {
      normalizeSecret(input);
      return true;
    } on FormatException {
      return false;
    }
  }

  static String formatCode(String code) {
    if (code.length <= 4) return code;
    final mid = code.length ~/ 2;
    return '${code.substring(0, mid)} ${code.substring(mid)}';
  }

  static String _normalizeBase32Secret(String input) {
    final compact = input.replaceAll(RegExp(r'[\s-]+'), '').toUpperCase();
    final normalized = compact.replaceFirst(RegExp(r'=+$'), '');
    if (normalized.isEmpty) {
      throw const FormatException('TOTP secret is required');
    }
    if (!_base32SecretPattern.hasMatch(normalized)) {
      throw const FormatException(
        'Invalid TOTP secret: expected Base32 characters A-Z and 2-7',
      );
    }
    if (!_validUnpaddedBase32Remainders.contains(normalized.length % 8)) {
      throw const FormatException('Invalid TOTP secret length');
    }
    return normalized;
  }

  static void _validateSupportedOtpParameter(
    String? value, {
    required String supportedValue,
    required String parameter,
  }) {
    if (value == null || value.isEmpty) {
      return;
    }
    if (value.toUpperCase() != supportedValue) {
      throw FormatException('Unsupported otpauth $parameter');
    }
  }
}
