import 'package:fav/features/install/data/provisioner/run_state_parser.dart';
import 'package:fav/features/install/presentation/install_step_labels.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every run step key has a localized label', () async {
    // A key missing from the switch falls back to the raw snake_case id in
    // the timeline (seen live for deploy_app_key, device test 2026-08-19).
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    for (final key in kRunStepKeys) {
      expect(
        installStepLabel(l10n, key),
        isNot(key),
        reason: 'step "$key" must not surface as its raw id',
      );
    }
  });
}
