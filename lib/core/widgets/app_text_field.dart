import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/core/widgets/section_header.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// A labelled form field with the label rendered above the input.
///
/// Matches the mockup form style, where each field carries an uppercase
/// caption rather than a floating Material label.
class AppTextField extends StatefulWidget {
  /// Creates an [AppTextField] captioned [label].
  const AppTextField({
    required this.label,
    this.controller,
    this.validator,
    this.obscureText = false,
    this.keyboardType,
    this.autofocus = false,
    this.readOnly = false,
    this.enabled = true,
    this.onFieldSubmitted,
    this.onChanged,
    this.helper,
    this.autovalidateMode,
    super.key,
  });

  /// The field caption, shown above the input.
  final String label;

  /// Controller for the field's text.
  final TextEditingController? controller;

  /// Validator invoked by the enclosing [Form].
  final FormFieldValidator<String>? validator;

  /// Whether the input hides the entered characters.
  final bool obscureText;

  /// Keyboard type for the input.
  final TextInputType? keyboardType;

  /// Whether the field requests focus when first shown.
  final bool autofocus;

  /// Whether the value is visible but cannot be edited.
  final bool readOnly;

  /// Whether the field accepts input and uses the enabled visual style.
  final bool enabled;

  /// Called when the user submits the field from the keyboard.
  final ValueChanged<String>? onFieldSubmitted;

  /// Called whenever the field value changes.
  final ValueChanged<String>? onChanged;

  /// Optional widget shown below the input (e.g. a strength indicator).
  final Widget? helper;

  /// When set, controls when this field auto-validates. Use
  /// [AutovalidateMode.onUserInteraction] so the field's error clears as soon
  /// as it becomes valid, without forcing sibling fields to validate too.
  final AutovalidateMode? autovalidateMode;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  void didUpdateWidget(AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.obscureText != widget.obscureText) {
      _obscured = widget.obscureText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(label: widget.label),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          textField: true,
          label: widget.label,
          child: TextFormField(
            controller: widget.controller,
            validator: widget.validator,
            autovalidateMode: widget.autovalidateMode,
            obscureText: widget.obscureText && _obscured,
            keyboardType: widget.keyboardType,
            autofocus: widget.autofocus,
            readOnly: widget.readOnly,
            enabled: widget.enabled,
            onFieldSubmitted: widget.onFieldSubmitted,
            onChanged: widget.onChanged,
            decoration: widget.obscureText
                ? InputDecoration(
                    suffixIcon: IconButton(
                      tooltip: _obscured
                          ? l10n.actionShowPassword
                          : l10n.actionHidePassword,
                      icon: Icon(
                        _obscured
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: widget.enabled
                          ? () => setState(() => _obscured = !_obscured)
                          : null,
                    ),
                  )
                : null,
          ),
        ),
        if (widget.helper != null) ...[
          const SizedBox(height: AppSpacing.sm),
          widget.helper!,
        ],
      ],
    );
  }
}
