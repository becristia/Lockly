import 'package:flutter/material.dart';
import 'package:secure_box/app/app_services.dart';
import 'package:secure_box/core/vault/vault_service.dart';
import 'package:secure_box/data/models/password_entry.dart';
import 'package:secure_box/shared/widgets/activity_text_form_field.dart';

class VaultEditPage extends StatefulWidget {
  const VaultEditPage({super.key, required this.services, this.itemId});

  final AppServices services;
  final String? itemId;

  @override
  State<VaultEditPage> createState() => _VaultEditPageState();
}

class _VaultEditPageState extends State<VaultEditPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _websiteController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isPasswordVisible = false;
  String? _pageError;

  bool get _isEditing => widget.itemId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _loadExistingItem();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _websiteController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingItem() async {
    setState(() {
      _isLoading = true;
      _pageError = null;
    });

    try {
      final entry = await widget.services.getVaultItem(widget.itemId!);
      if (!mounted) {
        return;
      }
      _titleController.text = entry.title;
      _websiteController.text = entry.website;
      _usernameController.text = entry.username;
      _passwordController.text = entry.password;
      _notesController.text = entry.notes;
      _tagsController.text = entry.tags.join(', ');
      setState(() => _isLoading = false);
    } on VaultItemNotFoundException {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _pageError = '这条记录不存在或已删除。';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _pageError = '暂时无法加载记录，请重试。';
      });
    }
  }

  Future<void> _save() async {
    widget.services.recordActivity();
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    final entry = PasswordEntry(
      title: _titleController.text.trim(),
      website: _websiteController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      notes: _notesController.text.trim(),
      tags: _parseTags(_tagsController.text),
    );

    try {
      if (_isEditing) {
        await widget.services.updateVaultItem(widget.itemId!, entry);
      } else {
        await widget.services.createVaultItem(entry);
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on VaultItemNotFoundException {
      if (!mounted) {
        return;
      }
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('这条记录不存在或已删除。')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存失败，请稍后重试。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditing ? '编辑密码' : '新增密码';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 64),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_pageError != null)
              _EditMessage(
                title: '无法编辑',
                message: _pageError!,
                actionLabel: '重试',
                onAction: _loadExistingItem,
              )
            else
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    ActivityTextFormField(
                      controller: _titleController,
                      onActivity: widget.services.recordActivity,
                      decoration: const InputDecoration(labelText: '标题'),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入标题';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    ActivityTextFormField(
                      controller: _websiteController,
                      onActivity: widget.services.recordActivity,
                      decoration: const InputDecoration(labelText: '网址'),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    ActivityTextFormField(
                      controller: _usernameController,
                      onActivity: widget.services.recordActivity,
                      decoration: const InputDecoration(labelText: '用户名'),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    ActivityTextFormField(
                      controller: _passwordController,
                      onActivity: widget.services.recordActivity,
                      decoration: InputDecoration(
                        labelText: '密码',
                        suffixIcon: IconButton(
                          onPressed: () {
                            widget.services.recordActivity();
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                          tooltip: _isPasswordVisible ? '隐藏密码' : '显示密码',
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                      obscureText: !_isPasswordVisible,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入密码';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    ActivityTextFormField(
                      controller: _notesController,
                      onActivity: widget.services.recordActivity,
                      decoration: const InputDecoration(labelText: '备注'),
                      keyboardType: TextInputType.multiline,
                      minLines: 4,
                      maxLines: 6,
                    ),
                    const SizedBox(height: 12),
                    ActivityTextFormField(
                      controller: _tagsController,
                      onActivity: widget.services.recordActivity,
                      decoration: const InputDecoration(
                        labelText: '标签',
                        hintText: '多个标签请用逗号分隔',
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('保存'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static List<String> _parseTags(String rawText) {
    return rawText
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
  }
}

class _EditMessage extends StatelessWidget {
  const _EditMessage({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        children: [
          Icon(
            Icons.edit_note_rounded,
            size: 36,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
