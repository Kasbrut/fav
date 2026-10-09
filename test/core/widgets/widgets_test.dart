import 'package:fav/core/theme/app_text_theme.dart';
import 'package:fav/core/utils/password_strength.dart';
import 'package:fav/core/widgets/app_banner.dart';
import 'package:fav/core/widgets/app_card.dart';
import 'package:fav/core/widgets/app_search_field.dart';
import 'package:fav/core/widgets/app_text_field.dart';
import 'package:fav/core/widgets/code_block.dart';
import 'package:fav/core/widgets/detail_row.dart';
import 'package:fav/core/widgets/empty_state.dart';
import 'package:fav/core/widgets/install_step_tile.dart';
import 'package:fav/core/widgets/monospace_text.dart';
import 'package:fav/core/widgets/password_strength_bar.dart';
import 'package:fav/core/widgets/primary_button.dart';
import 'package:fav/core/widgets/qr_container.dart';
import 'package:fav/core/widgets/secondary_button.dart';
import 'package:fav/core/widgets/section_header.dart';
import 'package:fav/core/widgets/status_badge.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../support/widget_harness.dart';

/// Widget tests for the shared design-system component library.
void main() {
  group('StatusBadge', () {
    for (final brightness in Brightness.values) {
      testWidgets('renders every variant in $brightness', (tester) async {
        for (final variant in StatusBadgeVariant.values) {
          await pumpThemed(
            tester,
            StatusBadge(label: 'WG active', variant: variant),
            brightness: brightness,
          );
          expect(find.text('WG active'), findsOneWidget);
        }
      });
    }

    testWidgets('renders an optional leading icon', (tester) async {
      await pumpThemed(
        tester,
        const StatusBadge(label: 'Done', icon: Icons.check),
      );
      expect(find.byIcon(Icons.check), findsOneWidget);
    });
  });

  group('AppBanner', () {
    for (final brightness in Brightness.values) {
      testWidgets('renders every variant in $brightness', (tester) async {
        for (final variant in AppBannerVariant.values) {
          await pumpThemed(
            tester,
            AppBanner(
              message: 'Banner body',
              title: 'Banner title',
              icon: Icons.info,
              variant: variant,
            ),
            brightness: brightness,
          );
          expect(find.text('Banner body'), findsOneWidget);
          expect(find.text('Banner title'), findsOneWidget);
          expect(find.byIcon(Icons.info), findsOneWidget);
        }
      });
    }

    testWidgets('shows the trailing action', (tester) async {
      await pumpThemed(
        tester,
        const AppBanner(message: 'msg', action: Text('Resume')),
      );
      expect(find.text('Resume'), findsOneWidget);
    });
  });

  group('AppCard', () {
    testWidgets('invokes onTap when tapped', (tester) async {
      var tapped = false;
      await pumpThemed(
        tester,
        AppCard(onTap: () => tapped = true, child: const Text('card')),
      );
      await tester.tap(find.text('card'));
      expect(tapped, isTrue);
    });

    testWidgets('renders without an onTap', (tester) async {
      await pumpThemed(tester, const AppCard(child: Text('static')));
      expect(find.text('static'), findsOneWidget);
    });
  });

  group('PrimaryButton', () {
    testWidgets('invokes onPressed when enabled', (tester) async {
      var pressed = false;
      await pumpThemed(
        tester,
        PrimaryButton(label: 'Go', onPressed: () => pressed = true),
      );
      await tester.tap(find.byType(PrimaryButton));
      expect(pressed, isTrue);
    });

    testWidgets('shows a spinner and is disabled while loading', (
      tester,
    ) async {
      var pressed = false;
      await pumpThemed(
        tester,
        PrimaryButton(
          label: 'Go',
          isLoading: true,
          onPressed: () => pressed = true,
        ),
        settle: false,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Go'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byType(PrimaryButton));
      expect(pressed, isFalse);
    });
  });

  group('SecondaryButton', () {
    testWidgets('invokes onPressed and renders its icon', (tester) async {
      var pressed = false;
      await pumpThemed(
        tester,
        SecondaryButton(
          label: 'Advanced',
          icon: Icons.tune,
          onPressed: () => pressed = true,
        ),
      );
      expect(find.byIcon(Icons.tune), findsOneWidget);
      await tester.tap(find.byType(SecondaryButton));
      expect(pressed, isTrue);
    });

    testWidgets('shows a spinner and blocks taps while loading', (
      tester,
    ) async {
      var presses = 0;
      await pumpThemed(
        tester,
        SecondaryButton(
          label: 'Cancel',
          isLoading: true,
          onPressed: () => presses++,
        ),
        settle: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byType(SecondaryButton));
      expect(presses, 0);
    });
  });

  group('SectionHeader', () {
    testWidgets('uppercases the label and shows the hint', (tester) async {
      await pumpThemed(
        tester,
        const SectionHeader(label: 'connection', hint: 'how to connect'),
      );
      expect(find.text('CONNECTION'), findsOneWidget);
      expect(find.text('how to connect'), findsOneWidget);
    });
  });

  group('MonospaceText', () {
    testWidgets('applies the monospace font family', (tester) async {
      await pumpThemed(tester, const MonospaceText('a1b2c3'));
      final widget = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(widget.style?.fontFamily, kMonospacePrimaryFont);
      expect(widget.style?.fontFamilyFallback, contains('monospace'));
    });

    testWidgets('renders plain text when not selectable', (tester) async {
      await pumpThemed(
        tester,
        const MonospaceText('a1b2c3', selectable: false),
      );
      expect(find.byType(SelectableText), findsNothing);
      expect(find.text('a1b2c3'), findsOneWidget);
    });
  });

  group('CodeBlock', () {
    testWidgets('renders its content as monospace text', (tester) async {
      await pumpThemed(tester, const CodeBlock(content: '[Interface]'));
      expect(find.text('[Interface]'), findsOneWidget);
      expect(find.byType(MonospaceText), findsOneWidget);
    });
  });

  group('DetailRow', () {
    testWidgets('renders the label and value', (tester) async {
      await pumpThemed(
        tester,
        const DetailRow(label: 'Host', value: '203.0.113.9'),
      );
      expect(find.text('Host'), findsOneWidget);
      expect(find.text('203.0.113.9'), findsOneWidget);
    });

    testWidgets('renders a monospace value when requested', (tester) async {
      await pumpThemed(
        tester,
        const DetailRow(
          label: 'Fingerprint',
          value: 'SHA256:abc',
          monospaceValue: true,
        ),
      );
      expect(find.byType(MonospaceText), findsOneWidget);
    });
  });

  group('EmptyState', () {
    testWidgets('renders icon, title, message and action', (tester) async {
      await pumpThemed(
        tester,
        const EmptyState(
          icon: Icons.dns_outlined,
          title: 'No servers yet',
          message: 'Add one to begin',
          action: Text('Add'),
        ),
      );
      expect(find.byIcon(Icons.dns_outlined), findsOneWidget);
      expect(find.text('No servers yet'), findsOneWidget);
      expect(find.text('Add one to begin'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
    });
  });

  group('InstallStepTile', () {
    testWidgets('shows a spinner while running', (tester) async {
      await pumpThemed(
        tester,
        const InstallStepTile(
          name: 'probe',
          status: InstallStepStatusView.running,
        ),
        settle: false,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('probe'), findsOneWidget);
    });

    testWidgets('shows an icon and detail for finished states', (
      tester,
    ) async {
      for (final status in [
        InstallStepStatusView.pending,
        InstallStepStatusView.done,
        InstallStepStatusView.error,
        InstallStepStatusView.skipped,
      ]) {
        await pumpThemed(
          tester,
          InstallStepTile(name: 'probe', status: status, detail: 'detail'),
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('detail'), findsOneWidget);
      }
    });

    testWidgets('exposes the semantic label and hides the icon-only status', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpThemed(
        tester,
        const InstallStepTile(
          name: 'Install packages',
          status: InstallStepStatusView.done,
          semanticLabel: 'Install packages, Done',
        ),
      );
      // The composed phrase is announced as a single node...
      expect(
        find.bySemanticsLabel('Install packages, Done'),
        findsOneWidget,
      );
      // ...and the visual name is excluded from the semantics tree to avoid a
      // fragmented, status-less announcement.
      expect(find.bySemanticsLabel('Install packages'), findsNothing);
      handle.dispose();
    });
  });

  group('AppSearchField', () {
    testWidgets('reports query changes', (tester) async {
      var query = '';
      await pumpThemed(
        tester,
        AppSearchField(
          hintText: 'Search',
          onChanged: (value) => query = value,
        ),
      );
      await tester.enterText(find.byType(AppSearchField), 'vps');
      expect(query, 'vps');
      expect(find.byIcon(Icons.search), findsOneWidget);
    });
  });

  group('AppTextField', () {
    testWidgets('uppercases the label and shows the helper', (tester) async {
      await pumpThemed(
        tester,
        const AppTextField(label: 'password', helper: Text('strength')),
      );
      expect(find.text('PASSWORD'), findsOneWidget);
      expect(find.text('strength'), findsOneWidget);
    });

    testWidgets('accepts entered text', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpThemed(
        tester,
        AppTextField(label: 'host', controller: controller),
      );
      await tester.enterText(find.byType(AppTextField), 'example.com');
      expect(controller.text, 'example.com');
    });

    testWidgets('toggles password visibility', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await pumpThemed(
        tester,
        const AppTextField(label: 'password', obscureText: true),
      );

      expect(
        tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        isTrue,
      );
      await tester.tap(find.byTooltip(l10n.actionShowPassword));
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        isFalse,
      );
      expect(find.byTooltip(l10n.actionHidePassword), findsOneWidget);
    });
  });

  group('QrContainer', () {
    testWidgets('renders a QR image for its data', (tester) async {
      await pumpThemed(tester, const QrContainer(data: 'wg-config'));
      expect(find.byType(QrImageView), findsOneWidget);
    });
  });

  group('PasswordStrengthBar', () {
    testWidgets('renders the label for each strength', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final labels = {
        PasswordStrength.weak: l10n.passwordStrengthWeak,
        PasswordStrength.fair: l10n.passwordStrengthFair,
        PasswordStrength.strong: l10n.passwordStrengthStrong,
      };
      for (final entry in labels.entries) {
        await pumpThemed(
          tester,
          PasswordStrengthBar(strength: entry.key),
        );
        expect(find.text(entry.value), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      }
    });
  });
}
