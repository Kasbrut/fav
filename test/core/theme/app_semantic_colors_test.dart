import 'package:fav/core/theme/app_semantic_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the [AppSemanticColors] theme extension.
void main() {
  test('copyWith replaces only the given field', () {
    const base = AppSemanticColors.light;
    final updated = base.copyWith(success: const Color(0xFF112233));

    expect(updated.success, const Color(0xFF112233));
    expect(updated.warning, base.warning);
    expect(updated.infoSurface, base.infoSurface);
    expect(updated.codeBackground, base.codeBackground);
  });

  test('lerp at the endpoints returns the endpoint colours', () {
    const light = AppSemanticColors.light;
    const dark = AppSemanticColors.dark;

    final atZero = light.lerp(dark, 0);
    final atOne = light.lerp(dark, 1);

    expect(atZero.success, light.success);
    expect(atOne.success, dark.success);
    expect(atOne.warningBorder, dark.warningBorder);
  });

  test('lerp with a non-matching extension returns the original', () {
    const light = AppSemanticColors.light;
    expect(light.lerp(null, 0.5), same(light));
  });
}
