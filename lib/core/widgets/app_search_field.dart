import 'package:flutter/material.dart';

/// A single-line search input with a leading magnifier icon.
class AppSearchField extends StatelessWidget {
  /// Creates an [AppSearchField].
  const AppSearchField({
    required this.hintText,
    this.controller,
    this.onChanged,
    super.key,
  });

  /// Placeholder text shown when the field is empty.
  final String hintText;

  /// Controller for the field's text.
  final TextEditingController? controller;

  /// Called whenever the query text changes.
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search),
      ),
    );
  }
}
