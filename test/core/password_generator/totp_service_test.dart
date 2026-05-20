import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/password_generator/totp_service.dart';

void main() {
  group('TotpService', () {
    // RFC 6238 test vector: Base32 of "12345678901234567890" = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    // At timestamp 59000ms (just past the first 30s boundary), the TOTP should be calculable
    const testSecret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

    test('generates 6-digit TOTP code string', () {
      final service = TotpService();
      final code = service.generate(
        base32Secret: testSecret,
        timestampMs: 59000,
      );
      expect(code.length, 6);
      expect(int.tryParse(code), isNotNull);
    });

    test('same inputs produce same code', () {
      final service = TotpService();
      final a = service.generate(base32Secret: testSecret, timestampMs: 59000);
      final b = service.generate(base32Secret: testSecret, timestampMs: 59000);
      expect(a, equals(b));
    });

    test('different timestamps produce different codes', () {
      final service = TotpService();
      final a = service.generate(base32Secret: testSecret, timestampMs: 59000);
      final b = service.generate(base32Secret: testSecret, timestampMs: 59000 + 30000);
      expect(a, isNot(equals(b)));
    });

    test('remainingSeconds computes correctly', () {
      final service = TotpService();
      // At 59000ms = 59s, remaining = 30 - (59 % 30) = 1
      expect(service.remainingSeconds(59000), 1);
      // At 30000ms = 30s, remaining = 30 - (30 % 30) = 30
      expect(service.remainingSeconds(30000), 30);
      // At 120000ms = 120s, remaining = 30 - (120 % 30) = 30
      expect(service.remainingSeconds(120000), 30);
    });

    test('parseOtpauthUrl extracts secret, label, issuer', () {
      final result = TotpService.parseOtpauthUrl(
        'otpauth://totp/Example:alice@google.com?secret=JBSWY3DPEHPK3PXP&issuer=Example',
      );
      expect(result.secret, 'JBSWY3DPEHPK3PXP');
      expect(result.label, 'Example:alice@google.com');
      expect(result.issuer, 'Example');
    });

    test('parseOtpauthUrl handles url without issuer', () {
      final result = TotpService.parseOtpauthUrl(
        'otpauth://totp/MyApp?secret=ABCDEFGH234567',
      );
      expect(result.secret, 'ABCDEFGH234567');
      expect(result.label, 'MyApp');
      expect(result.issuer, isNull);
    });

    test('formatCode inserts space for 6-digit code', () {
      expect(TotpService.formatCode('482931'), '482 931');
    });

    test('formatCode for 8-digit code', () {
      expect(TotpService.formatCode('48720691'), '4872 0691');
    });
  });
}
