import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/backup/backup_service.dart';
import 'package:secure_box/core/migration/plaintext_csv_importer.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

enum _MigrationSource { locklyJson, csv }

class MigrationWizardPage extends StatefulWidget {
  const MigrationWizardPage({super.key, required this.services});

  final AppServices services;

  @override
  State<MigrationWizardPage> createState() => _MigrationWizardPageState();
}

class _MigrationWizardPageState extends State<MigrationWizardPage> {
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  _MigrationSource _source = _MigrationSource.locklyJson;
  PlaintextCsvImportReport? _csvReport;
  String? _preparedCsvText;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _sourceController.clear();
    _passwordController.clear();
    _sourceController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _previewCsv() {
    widget.services.recordActivity();
    try {
      final csvText = _sourceController.text;
      final report = widget.services.previewPlaintextCsvImport(csvText);
      setState(() {
        _preparedCsvText = csvText;
        _csvReport = report;
        _error = null;
      });
      _sourceController.clear();
    } catch (_) {
      setState(() {
        _preparedCsvText = null;
        _csvReport = null;
        _error = AppStrings.of(context).text('csvParseFailed');
      });
      _sourceController.clear();
    }
  }

  Future<void> _import() async {
    widget.services.recordActivity();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final count = switch (_source) {
        _MigrationSource.locklyJson =>
          await widget.services.importEncryptedBackupJson(
            backupJson: _sourceController.text,
            masterPassword: _passwordController.text,
            mode: BackupImportMode.merge,
          ),
        _MigrationSource.csv => await widget.services.importPlaintextCsv(
          _preparedCsvText ?? _sourceController.text,
        ),
      };
      if (!mounted) return;
      _sourceController.clear();
      _passwordController.clear();
      _preparedCsvText = null;
      Navigator.of(context).pop(count);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (_source == _MigrationSource.csv) {
          _preparedCsvText = null;
          _csvReport = null;
        }
        _error = AppStrings.of(context).text('importFailed');
      });
      if (_source == _MigrationSource.csv) {
        _sourceController.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final isCsv = _source == _MigrationSource.csv;
    final report = _csvReport;
    final canImport = !_busy && (!isCsv || report != null);
    return SecureVisualBackground(
      key: const ValueKey('migration-wizard-page'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      child: ListView(
        children: [
          SecureReplicaHeader(
            title: strings.text('migrationImport'),
            subtitle: strings.text('migrationLocalSubtitle'),
            leading: IconButton(
              onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          const SizedBox(height: 12),
          SecureGlassCard(
            borderRadius: 20,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<_MigrationSource>(
                  segments: [
                    ButtonSegment(
                      value: _MigrationSource.locklyJson,
                      icon: const Icon(Icons.lock_outline_rounded),
                      label: Text(strings.text('locklyJson')),
                    ),
                    ButtonSegment(
                      value: _MigrationSource.csv,
                      icon: const Icon(Icons.table_chart_outlined),
                      label: Text(strings.text('csv')),
                    ),
                  ],
                  selected: {_source},
                  onSelectionChanged: _busy
                      ? null
                      : (selection) {
                          setState(() {
                            _source = selection.single;
                            _preparedCsvText = null;
                            _csvReport = null;
                            _error = null;
                          });
                          _sourceController.clear();
                          _passwordController.clear();
                        },
                ),
                const SizedBox(height: 14),
                if (isCsv) ...[
                  SecureStatusSurface(
                    color: SecureVisualColors.warning,
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 20,
                          color: SecureVisualColors.warning,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            strings.text('plaintextCsvWarning'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  key: ValueKey(
                    isCsv ? 'migration-csv-input' : 'migration-json-input',
                  ),
                  controller: _sourceController,
                  onChanged: isCsv ? (_) => _clearCsvPreview() : null,
                  minLines: 6,
                  maxLines: 9,
                  decoration: InputDecoration(
                    labelText: isCsv
                        ? strings.text('plaintextCsvExport')
                        : strings.text('encryptedBackupJson'),
                    prefixIcon: const Icon(Icons.data_object_rounded),
                  ),
                ),
                if (!isCsv) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('migration-backup-password-input'),
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: strings.text('backupMasterPassword'),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (isCsv)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _previewCsv,
                    icon: const Icon(Icons.visibility_outlined),
                    label: Text(strings.text('preview')),
                  ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: canImport ? _import : null,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_download_outlined),
                  label: Text(
                    _busy ? strings.text('importing') : strings.text('import'),
                  ),
                ),
                if (report != null) ...[
                  const SizedBox(height: 12),
                  _CsvPreview(report: report),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _clearCsvPreview() {
    if (_preparedCsvText == null && _csvReport == null) {
      return;
    }
    setState(() {
      _preparedCsvText = null;
      _csvReport = null;
      _error = null;
    });
  }
}

class _CsvPreview extends StatelessWidget {
  const _CsvPreview({required this.report});

  final PlaintextCsvImportReport report;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final countLabel = report.importableRows == 1
        ? '1 ${strings.text('importableRow')}'
        : '${report.importableRows} ${strings.text('importableRows')}';
    final skippedRows = '${report.skippedRows} ${strings.text('skippedRows')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(countLabel, style: Theme.of(context).textTheme.titleSmall),
        Text(skippedRows),
        const SizedBox(height: 8),
        for (final row in report.previewRows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.key_rounded),
            title: Text(row.title),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (row.website.isNotEmpty) Text(row.website),
                if (row.username.isNotEmpty) Text(row.username),
              ],
            ),
          ),
      ],
    );
  }
}
