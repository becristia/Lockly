import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/password_generator/password_generator.dart';
import 'package:secure_box/features/vault_edit/vault_edit_page.dart';
import 'package:secure_box/shared/i18n/app_strings.dart';
import 'package:secure_box/shared/widgets/secure_panel.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

enum PasswordGeneratorMode { standalone, picker }

class PasswordGeneratorPage extends StatefulWidget {
  const PasswordGeneratorPage({
    super.key,
    required this.services,
    this.mode = PasswordGeneratorMode.standalone,
    this.onSavedToVault,
  });

  final AppServices services;
  final PasswordGeneratorMode mode;
  final VoidCallback? onSavedToVault;

  @override
  State<PasswordGeneratorPage> createState() => _PasswordGeneratorPageState();
}

class _PasswordGeneratorPageState extends State<PasswordGeneratorPage> {
  static const _lengthChoices = <int>{8, 12, 16, 24, 32, 64};

  final PasswordGenerator _generator = PasswordGenerator();

  int _length = 16;
  bool _lowercase = true;
  bool _uppercase = true;
  bool _numbers = true;
  bool _symbols = true;
  bool _excludeConfusing = true;
  bool _requireEverySelectedClass = true;
  String _generatedPassword = '';
  String? _errorText;

  void _generatePassword() {
    widget.services.recordActivity();
    try {
      final password = _generator.generate(
        PasswordGeneratorOptions(
          length: _length,
          lowercase: _lowercase,
          uppercase: _uppercase,
          numbers: _numbers,
          symbols: _symbols,
          excludeConfusing: _excludeConfusing,
          requireEverySelectedClass: _requireEverySelectedClass,
        ),
      );
      setState(() {
        _generatedPassword = password;
        _errorText = null;
      });
    } on PasswordGeneratorException catch (error) {
      setState(() {
        _generatedPassword = '';
        _errorText = error.message;
      });
    }
  }

  Future<void> _savePassword() async {
    widget.services.recordActivity();
    if (_generatedPassword.isEmpty) {
      return;
    }

    if (widget.mode == PasswordGeneratorMode.picker) {
      Navigator.of(context).pop(_generatedPassword);
      return;
    }

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => VaultEditPage(
          services: widget.services,
          initialPassword: _generatedPassword,
        ),
      ),
    );
    if (saved == true && mounted) {
      widget.onSavedToVault?.call();
    }
  }

  Future<void> _copyGeneratedPassword() async {
    widget.services.recordActivity();
    if (_generatedPassword.isEmpty) {
      return;
    }
    final copied = await widget.services.copyPassword(_generatedPassword);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          copied
              ? AppStrings.of(context).passwordCopied
              : AppStrings.of(context).copyFailed,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);

    return SecureVisualBackground(
      bottomInset: 0,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 92),
        children: [
          SecureReplicaHeader(
            title: strings.passwordGeneratorTitle,
            leading: Icon(
              Icons.auto_awesome_rounded,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 22),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ResultPanel(
                password: _generatedPassword,
                errorText: _errorText,
                onGenerate: _generatePassword,
                onCopy: _copyGeneratedPassword,
                onSave: _savePassword,
                saveLabel: widget.mode == PasswordGeneratorMode.picker
                    ? strings.text('useGeneratedPassword')
                    : strings.saveThisPassword,
                strings: strings,
              ),
              const SizedBox(height: 16),
              SecureSection(
                title: strings.generatorRulesTitle,
                subtitle: strings.generatorRulesSubtitle,
                icon: Icons.tune_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      strings.generatorLengthLabel,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<int>(
                      segments: _lengthChoices
                          .map(
                            (length) => ButtonSegment<int>(
                              value: length,
                              label: Text(length.toString()),
                            ),
                          )
                          .toList(growable: false),
                      selected: {_length},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) {
                        widget.services.recordActivity();
                        setState(() => _length = selection.single);
                      },
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final tileWidth = constraints.maxWidth >= 420
                            ? (constraints.maxWidth - 12) / 2
                            : constraints.maxWidth;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            _GeneratorSwitch(
                              width: tileWidth,
                              icon: Icons.text_fields_rounded,
                              title: strings.generatorLowercase,
                              value: _lowercase,
                              onChanged: (value) =>
                                  setState(() => _lowercase = value),
                            ),
                            _GeneratorSwitch(
                              width: tileWidth,
                              icon: Icons.title_rounded,
                              title: strings.generatorUppercase,
                              value: _uppercase,
                              onChanged: (value) =>
                                  setState(() => _uppercase = value),
                            ),
                            _GeneratorSwitch(
                              width: tileWidth,
                              icon: Icons.pin_rounded,
                              title: strings.generatorNumbers,
                              value: _numbers,
                              onChanged: (value) =>
                                  setState(() => _numbers = value),
                            ),
                            _GeneratorSwitch(
                              width: tileWidth,
                              icon: Icons.alternate_email_rounded,
                              title: strings.generatorSymbols,
                              value: _symbols,
                              onChanged: (value) =>
                                  setState(() => _symbols = value),
                            ),
                            _GeneratorSwitch(
                              width: tileWidth,
                              icon: Icons.visibility_off_outlined,
                              title: strings.generatorExcludeConfusing,
                              value: _excludeConfusing,
                              onChanged: (value) =>
                                  setState(() => _excludeConfusing = value),
                            ),
                            _GeneratorSwitch(
                              width: tileWidth,
                              icon: Icons.done_all_rounded,
                              title: strings.generatorRequireEveryClass,
                              value: _requireEverySelectedClass,
                              onChanged: (value) => setState(
                                () => _requireEverySelectedClass = value,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.password,
    required this.errorText,
    required this.onGenerate,
    required this.onCopy,
    required this.onSave,
    required this.saveLabel,
    required this.strings,
  });

  final String password;
  final String? errorText;
  final VoidCallback onGenerate;
  final VoidCallback onCopy;
  final VoidCallback onSave;
  final String saveLabel;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPassword = password.isNotEmpty;

    return SecureGlassCard(
      key: hasPassword ? const ValueKey('generator-result-panel') : null,
      padding: const EdgeInsets.all(18),
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SecureStatusPill(
                icon: hasPassword
                    ? Icons.check_circle_rounded
                    : Icons.auto_awesome_rounded,
                label: strings.generatorResult,
                color: hasPassword
                    ? SecureVisualColors.success
                    : SecureVisualColors.blue,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasPassword)
            SecureStatusSurface(
              color: SecureVisualColors.success,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      password,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Tooltip(
                    message: strings.copyPasswordTooltip,
                    child: IconButton.filledTonal(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              errorText ?? strings.generatorEmptyHint,
              style: theme.textTheme.bodyMedium,
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: SecureVisualColors.success,
              ),
              const SizedBox(width: 8),
              Text(
                strings.generatorStrengthStrong,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('generator-generate-button'),
            onPressed: onGenerate,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(
              hasPassword
                  ? strings.regeneratePassword
                  : strings.generatePassword,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: hasPassword ? onSave : null,
            icon: const Icon(Icons.save_outlined),
            label: Text(saveLabel),
          ),
        ],
      ),
    );
  }
}

class _GeneratorSwitch extends StatelessWidget {
  const _GeneratorSwitch({
    required this.width,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final double width;
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: VisualDensity.compact,
        secondary: SecureIconTile(icon: icon, size: 28),
        title: Text(title),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
