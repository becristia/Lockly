import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/sync/sync_configuration.dart';

void main() {
  test('sync base url rejects cleartext non-local hosts', () {
    expect(
      () => validateSyncBaseUrl(Uri.parse('http://sync.example.test')),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('sync base url allows https and local http development hosts', () {
    expect(
      validateSyncBaseUrl(Uri.parse('https://sync.example.test')).scheme,
      'https',
    );
    expect(
      validateSyncBaseUrl(Uri.parse('http://localhost:8000')).host,
      'localhost',
    );
    expect(
      validateSyncBaseUrl(Uri.parse('http://127.0.0.1:8000')).host,
      '127.0.0.1',
    );
    expect(
      validateSyncBaseUrl(Uri.parse('http://[::1]:8000')).host,
      '::1',
    );
    expect(
      validateSyncBaseUrl(Uri.parse('http://10.0.2.2:8000')).host,
      '10.0.2.2',
    );
  });
}
