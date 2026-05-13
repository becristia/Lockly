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
    this.onFieldSubmitted,
    this.keyboardType,
    this.autofillHints,
    this.minLines,
    this.maxLines = 1,
  });

  final VoidCallback onActivity;
  final InputDecoration decoration;
  final bool obscureText;
  final TextEditingController? controller;
  final FormFieldValidator<String>? validator;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final bool? enabled;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final int? minLines;
  final int? maxLines;

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
      minLines: minLines,
      maxLines: maxLines,
      onTap: onActivity,
      onChanged: (_) => onActivity(),
    );
  }
}
