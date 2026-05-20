import 'package:otp/otp.dart';

class ParsedOtpAuth {
  const ParsedOtpAuth({required this.secret, this.label, this.issuer});
  final String secret;
  final String? label;
  final String? issuer;
}

class TotpService {
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
    );
  }

  int remainingSeconds(int timestampMs, {int interval = 30}) {
    final seconds = timestampMs ~/ 1000;
    final elapsed = seconds % interval;
    return interval - elapsed;
  }

  static ParsedOtpAuth parseOtpauthUrl(String url) {
    final uri = Uri.parse(url);
    final secret = uri.queryParameters['secret'] ?? '';
    String? label;
    if (uri.pathSegments.isNotEmpty) {
      label = Uri.decodeComponent(uri.pathSegments.first);
    }
    final issuer = uri.queryParameters['issuer'];
    return ParsedOtpAuth(secret: secret, label: label, issuer: issuer);
  }

  static String formatCode(String code) {
    if (code.length <= 4) return code;
    final mid = code.length ~/ 2;
    return '${code.substring(0, mid)} ${code.substring(mid)}';
  }
}
