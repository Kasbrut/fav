import 'dart:math' as math;

import 'package:fav/core/theme/app_dimens.dart';
import 'package:flutter/material.dart';

/// Keeps page content readable on wide windows without changing compact UI.
class ResponsiveContent extends StatelessWidget {
  /// Creates a centered, full-height content region.
  const ResponsiveContent({
    required this.child,
    this.maxWidth = AppSizes.contentMaxWidth,
    super.key,
  });

  /// Content rendered inside the responsive region.
  final Widget child;

  /// Maximum logical width on large displays.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: SizedBox(
          width: math.min(maxWidth, constraints.maxWidth),
          height: constraints.maxHeight,
          child: child,
        ),
      ),
    );
  }
}
