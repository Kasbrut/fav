import 'package:fav/core/theme/app_dimens.dart';
import 'package:flutter/material.dart';

/// A flat, bordered surface card matching the mockups (12 px radius).
///
/// When [onTap] is provided the whole card becomes tappable with an ink ripple.
class AppCard extends StatelessWidget {
  /// Creates an [AppCard] wrapping [child].
  const AppCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    super.key,
  });

  /// The card content.
  final Widget child;

  /// Called when the card is tapped; the card is non-interactive when null.
  final VoidCallback? onTap;

  /// Inner padding around [child].
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Card(
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadii.card),
              child: content,
            ),
    );
  }
}
