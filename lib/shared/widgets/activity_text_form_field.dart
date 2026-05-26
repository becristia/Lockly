import 'package:flutter/material.dart';

class ActivityTextFormField extends StatelessWidget {
  const ActivityTextFormField({
    super.key,
    required this.onActivity,
    required this.decoration,
    this.obscureText = false,
    this.controller,
    this.validator,
    this.textInputAction,
    this.autofocus = false,
    this.enabled,
    this.onChanged,
    this.onFieldSubmitted,
    this.keyboardType,
    this.autofillHints,
    this.minLines,
    this.maxLines = 1,
    this.enableSuggestions,
    this.autocorrect,
  });

  final VoidCallback onActivity;
  final InputDecoration decoration;
  final bool obscureText;
  final TextEditingController? controller;
  final FormFieldValidator<String>? validator;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final bool? enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final int? minLines;
  final int? maxLines;
  final bool? enableSuggestions;
  final bool? autocorrect;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      decoration: decoration,
      validator: validator,
      textInputAction: textInputAction,
      autofocus: autofocus,
      enabled: enabled,
      onFieldSubmitted: onFieldSubmitted,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      enableSuggestions: enableSuggestions ?? false,
      autocorrect: autocorrect ?? false,
      minLines: minLines,
      maxLines: maxLines,
      onTap: onActivity,
      onChanged: (value) {
        onActivity();
        onChanged?.call(value);
      },
    );
  }
}
