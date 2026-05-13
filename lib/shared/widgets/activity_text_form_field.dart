import 'package:flutter/material.dart';

class ActivityTextFormField extends StatelessWidget {
  const ActivityTextFormField({
    super.key,
    required this.onActivity,
    required this.decoration,
    this.obscureText = false,
  });

  final VoidCallback onActivity;
  final InputDecoration decoration;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      obscureText: obscureText,
      decoration: decoration,
      onTap: onActivity,
      onChanged: (_) => onActivity(),
    );
  }
}
