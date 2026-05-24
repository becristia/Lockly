import 'package:flutter_test/flutter_test.dart';
import 'package:secure_box/core/migration/plaintext_csv_importer.dart';

void main() {
  test('CSV importer maps common password manager headers', () {
    final report = PlaintextCsvImporter.preview(
      'name,url,username,password,notes,tags,totp\n'
      'GitHub,https://github.com,user@example.com,secret-pass,private note,"dev, code",123456\n',
    );

    expect(report.totalRows, 1);
    expect(report.importableRows, 1);
    expect(report.skippedRows, 0);
    expect(report.previewRows.single.title, 'GitHub');
    expect(report.previewRows.single.website, 'https://github.com');
    expect(report.previewRows.single.username, 'user@example.com');
    final entry = PlaintextCsvImporter.parseEntries(
      'name,url,username,password,notes,tags,totp\n'
      'GitHub,https://github.com,user@example.com,secret-pass,private note,"dev, code",123456\n',
    ).single;
    expect(entry.password, 'secret-pass');
    expect(entry.notes, 'private note');
    expect(entry.tags, ['dev', 'code']);
    expect(entry.totpSecret, '123456');
  });

  test('CSV preview hides passwords notes and totp secrets', () {
    final report = PlaintextCsvImporter.preview(
      'title,website,username,password,notes,totp\n'
      'Bank,https://bank.example,alice,bank-secret,private banking note,OTPSECRET\n',
    );

    final preview = report.previewRows.single;
    expect(preview.title, 'Bank');
    expect(preview.website, 'https://bank.example');
    expect(preview.username, 'alice');
    expect(preview.toString(), isNot(contains('bank-secret')));
    expect(preview.toString(), isNot(contains('private banking note')));
    expect(preview.toString(), isNot(contains('OTPSECRET')));
  });

  test('CSV importer handles quoted commas and escaped quotes', () {
    final entry = PlaintextCsvImporter.parseEntries(
      'title,website,username,password\n'
      '"A, B ""Prod""",https://example.com,me,"p,ass"\n',
    ).single;
    expect(entry.title, 'A, B "Prod"');
    expect(entry.password, 'p,ass');
  });

  test('CSV importer skips incomplete rows', () {
    final report = PlaintextCsvImporter.preview(
      'title,website,username,password\n'
      'Missing password,https://example.com,me,\n'
      ',https://ok.example,ok-user,ok-pass\n',
    );

    expect(report.totalRows, 2);
    expect(report.importableRows, 1);
    expect(report.skippedRows, 1);
    expect(
      PlaintextCsvImporter.parseEntries(
        'title,website,username,password\n'
        'Missing password,https://example.com,me,\n'
        ',https://ok.example,ok-user,ok-pass\n',
      ).single.title,
      'https://ok.example',
    );
  });

  test('CSV importer rejects oversized input', () {
    final text = 'title,website,username,password\n${'a' * 1048577}';
    expect(
      () => PlaintextCsvImporter.preview(text),
      throwsA(isA<FormatException>()),
    );
  });
}
