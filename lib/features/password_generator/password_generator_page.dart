import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/password_generator/password_generator.dart';
import 'package:secure_box/features/vault_edit/vault_edit_page.dart';
import 'package:secure_box/shared/widgets/secure_scaffold.dart';

class PasswordGeneratorPage extends StatefulWidget {
  const PasswordGeneratorPage({super.key, required this.services});

  final AppServices services;

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

    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => VaultEditPage(
          services: widget.services,
          initialPassword: _generatedPassword,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SecureScaffold(
      title: '密码生成器',
      subtitle: '按本地规则生成强密码，并直接保存到加密密码库。',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('长度', style: theme.textTheme.titleMedium),
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
          const SizedBox(height: 20),
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
                    title: '小写字母',
                    value: _lowercase,
                    onChanged: (value) => setState(() => _lowercase = value),
                  ),
                  _GeneratorSwitch(
                    width: tileWidth,
                    title: '大写字母',
                    value: _uppercase,
                    onChanged: (value) => setState(() => _uppercase = value),
                  ),
                  _GeneratorSwitch(
                    width: tileWidth,
                    title: '数字',
                    value: _numbers,
                    onChanged: (value) => setState(() => _numbers = value),
                  ),
                  _GeneratorSwitch(
                    width: tileWidth,
                    title: '特殊符号',
                    value: _symbols,
                    onChanged: (value) => setState(() => _symbols = value),
                  ),
                  _GeneratorSwitch(
                    width: tileWidth,
                    title: '排除易混字符',
                    value: _excludeConfusing,
                    onChanged: (value) =>
                        setState(() => _excludeConfusing = value),
                  ),
                  _GeneratorSwitch(
                    width: tileWidth,
                    title: '每类至少一个',
                    value: _requireEverySelectedClass,
                    onChanged: (value) =>
                        setState(() => _requireEverySelectedClass = value),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          if (_generatedPassword.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outline),
              ),
              child: SelectableText(
                _generatedPassword,
                style: theme.textTheme.titleMedium,
              ),
            )
          else
            Text(
              _errorText ?? '生成后可直接进入新增密码页面保存。',
              style: theme.textTheme.bodyMedium,
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _generatePassword,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('生成密码'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _generatedPassword.isEmpty ? null : _savePassword,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存此密码'),
          ),
        ],
      ),
    );
  }
}

class _GeneratorSwitch extends StatelessWidget {
  const _GeneratorSwitch({
    required this.width,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final double width;
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
        title: Text(title),
        value: value,
        onChanged: (value) {
          onChanged(value);
        },
      ),
    );
  }
}
