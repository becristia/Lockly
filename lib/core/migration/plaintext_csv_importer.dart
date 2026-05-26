import 'dart:convert';

import 'package:secure_box/data/models/password_entry.dart';

const int maxPlaintextCsvImportBytes = 1024 * 1024;

class PlaintextCsvImportReport {
  const PlaintextCsvImportReport({
    required this.totalRows,
    required this.importableRows,
    required this.skippedRows,
    required this.previewRows,
  });

  final int totalRows;
  final int importableRows;
  final int skippedRows;
  final List<PlaintextCsvPreviewRow> previewRows;
}

class PlaintextCsvPreviewRow {
  const PlaintextCsvPreviewRow({
    required this.title,
    required this.website,
    required this.username,
  });

  final String title;
  final String website;
  final String username;

  @override
  String toString() {
    return 'PlaintextCsvPreviewRow(title: $title, website: $website, '
        'username: $username)';
  }
}

class PlaintextCsvImporter {
  static PlaintextCsvImportReport preview(String csvText) {
    final parsed = _parseImport(csvText);
    return PlaintextCsvImportReport(
      totalRows: parsed.totalRows,
      importableRows: parsed.entries.length,
      skippedRows: parsed.skippedRows,
      previewRows: List.unmodifiable(parsed.previewRows),
    );
  }

  static List<PasswordEntry> parseEntries(String csvText) {
    return List.unmodifiable(_parseImport(csvText).entries);
  }
}

_PlaintextCsvParse _parseImport(String csvText) {
  if (utf8.encode(csvText).length > maxPlaintextCsvImportBytes) {
    throw const FormatException('CSV import is too large');
  }

  final rows = _parseCsv(csvText);
  if (rows.isEmpty) {
    throw const FormatException('CSV import is empty');
  }

  final headers = rows.first.map(_normalizeHeader).toList(growable: false);
  if (headers.every((header) => header.isEmpty)) {
    throw const FormatException('CSV headers are missing');
  }

  final entries = <PasswordEntry>[];
  final previews = <PlaintextCsvPreviewRow>[];
  var skipped = 0;
  for (final row in rows.skip(1)) {
    if (row.every((value) => value.trim().isEmpty)) {
      continue;
    }

    final entry = _entryFromRow(headers, row);
    if (entry == null) {
      skipped += 1;
      continue;
    }

    entries.add(entry);
    if (previews.length < 5) {
      previews.add(
        PlaintextCsvPreviewRow(
          title: entry.title,
          website: entry.website,
          username: entry.username,
        ),
      );
    }
  }

  return _PlaintextCsvParse(
    totalRows: rows.length - 1,
    skippedRows: skipped,
    previewRows: List.unmodifiable(previews),
    entries: List.unmodifiable(entries),
  );
}

class _PlaintextCsvParse {
  const _PlaintextCsvParse({
    required this.totalRows,
    required this.skippedRows,
    required this.previewRows,
    required this.entries,
  });

  final int totalRows;
  final int skippedRows;
  final List<PlaintextCsvPreviewRow> previewRows;
  final List<PasswordEntry> entries;
}

PasswordEntry? _entryFromRow(List<String> headers, List<String> row) {
  String read(Set<String> aliases) {
    for (var i = 0; i < headers.length; i += 1) {
      if (!aliases.contains(headers[i])) {
        continue;
      }
      if (i >= row.length) {
        return '';
      }
      return row[i].trim();
    }
    return '';
  }

  final titleValue = read(_titleHeaders);
  final website = read(_websiteHeaders);
  final username = read(_usernameHeaders);
  final password = read(_passwordHeaders);
  if (password.isEmpty ||
      (titleValue.isEmpty && website.isEmpty && username.isEmpty)) {
    return null;
  }

  return PasswordEntry(
    title: _firstNonEmpty([titleValue, website, username, 'Imported item']),
    website: website,
    username: username,
    password: password,
    notes: read(_notesHeaders),
    tags: _splitTags(read(_tagsHeaders)),
    totpSecret: _emptyToNull(read(_totpHeaders)),
  );
}

List<String> _splitTags(String value) {
  if (value.trim().isEmpty) {
    return const [];
  }
  return value
      .split(RegExp(r'[,;]'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
}

String _firstNonEmpty(List<String> values) {
  return values.firstWhere((value) => value.trim().isNotEmpty).trim();
}

String? _emptyToNull(String value) => value.isEmpty ? null : value;

String _normalizeHeader(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

const _titleHeaders = {'title', 'name', 'login_title'};
const _websiteHeaders = {'website', 'url', 'uri', 'login_uri'};
const _usernameHeaders = {'username', 'login_username', 'email'};
const _passwordHeaders = {'password', 'login_password'};
const _notesHeaders = {'notes', 'note'};
const _tagsHeaders = {'tags', 'folder'};
const _totpHeaders = {'totp', 'totp_secret', 'otp'};

List<List<String>> _parseCsv(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < input.length; i += 1) {
    final char = input[i];
    if (inQuotes) {
      if (char == '"') {
        final nextIsQuote = i + 1 < input.length && input[i + 1] == '"';
        if (nextIsQuote) {
          field.write('"');
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(char);
      }
      continue;
    }

    if (char == '"') {
      inQuotes = true;
    } else if (char == ',') {
      row.add(field.toString());
      field.clear();
    } else if (char == '\n') {
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else if (char != '\r') {
      field.write(char);
    }
  }

  if (inQuotes) {
    throw const FormatException('CSV quote is not closed');
  }

  row.add(field.toString());
  if (row.any((value) => value.isNotEmpty) || rows.isEmpty) {
    rows.add(row);
  }
  return rows;
}
