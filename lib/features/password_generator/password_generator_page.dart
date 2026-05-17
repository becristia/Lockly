import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/password_generator/password_generator.dart';
import 'package:secure_box/features/vault_edit/vault_edit_page.dart';
import 'package:secure_box/shared/widgets/secure_panel.dart';
import 'package:secure_box/shared/widgets/secure_visuals.dart';

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
      SnackBar(content: Text(copied ? '密码已复制，30 秒后将自动清理剪贴板。' : '复制失败，请重试。')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SecureVisualBackground(
      bottomInset: 0,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 92),
        children: [
          SecureReplicaHeader(
            title: '密码生成器',
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
              ),
              const SizedBox(height: 16),
              SecureSection(
                title: '生成规则',
                subtitle: '默认保证每类已选字符至少出现一次。',
                icon: Icons.tune_rounded,
                child: Column(
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
                              title: '小写字母',
                              value: _lowercase,
                              onChanged: (value) =>
                                  setState(() => _lowercase = value),
                            ),
                            _GeneratorSwitch(
                              width: tileWidth,
                              icon: Icons.title_rounded,
                              title: '大写字母',
                              value: _uppercase,
                              onChanged: (value) =>
                                  setState(() => _uppercase = value),
                            ),
                            _GeneratorSwitch(
                              width: tileWidth,
                              icon: Icons.pin_rounded,
                              title: '数字',
                              value: _numbers,
                              onChanged: (value) =>
                                  setState(() => _numbers = value),
                            ),
                            _GeneratorSwitch(
                              width: tileWidth,
                              icon: Icons.alternate_email_rounded,
                              title: '特殊符号',
                              value: _symbols,
                              onChanged: (value) =>
                                  setState(() => _symbols = value),
                            ),
                            _GeneratorSwitch(
                              width: tileWidth,
                              icon: Icons.visibility_off_outlined,
                              title: '排除易混字符',
                              value: _excludeConfusing,
                              onChanged: (value) =>
                                  setState(() => _excludeConfusing = value),
                            ),
                            _GeneratorSwitch(
                              width: tileWidth,
                              icon: Icons.done_all_rounded,
                              title: '每类至少一个',
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
  });

  final String password;
  final String? errorText;
  final VoidCallback onGenerate;
  final VoidCallback onCopy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPassword = password.isNotEmpty;

    return Container(
      key: hasPassword ? const ValueKey('generator-result-panel') : null,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF55B4FF), Color(0xFF0B66F6), Color(0xFF9A6BFF)],
        ),
        boxShadow: [
          BoxShadow(
            color: SecureVisualColors.blue.withValues(alpha: 0.24),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.86),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Text(
                    '生成结果',
                    style: TextStyle(
                      color: SecureVisualColors.blue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasPassword)
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    password,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: '复制密码',
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.86),
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy_rounded),
                      color: SecureVisualColors.blue,
                    ),
                  ),
                ),
              ],
            )
          else
            Text(
              errorText ?? '点击生成后，可直接保存到新增密码页面。',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFFB9FFD0)),
              const SizedBox(width: 8),
              Text(
                '强',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
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
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0B66F6),
              foregroundColor: Colors.white,
            ),
            label: Text(hasPassword ? '重新生成' : '生成密码'),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: hasPassword ? onSave : null,
            icon: const Icon(Icons.save_outlined),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.82),
              foregroundColor: SecureVisualColors.blue,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.42),
            ),
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
        secondary: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            icon,
            size: 15,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(title),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
