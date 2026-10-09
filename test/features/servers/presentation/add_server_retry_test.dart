import 'package:fav/core/theme/app_theme.dart';
import 'package:fav/features/servers/presentation/add_server_screen.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/server_fakes.dart';

void main() {
  testWidgets('retry prefills and locks connection until explicitly edited', (
    tester,
  ) async {
    final server = testServer().copyWith(
      label: 'Ubuntu retry',
      host: '198.51.100.108',
      sshPort: 2222,
      username: 'operator',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AddServerScreen(retryServer: server),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();
    expect(fields[0].controller!.text, 'Ubuntu retry');
    expect(fields[1].controller!.text, '198.51.100.108');
    expect(fields[2].controller!.text, '2222');
    expect(fields[3].controller!.text, 'operator');
    expect(fields[0].enabled, isTrue);
    expect(fields[1].enabled, isFalse);
    expect(fields[2].enabled, isFalse);
    expect(fields[3].enabled, isFalse);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(
      find.byTooltip(l10n.actionBackToServers),
      findsOneWidget,
    );
    await tester.tap(find.text(l10n.actionEditConnection));
    await tester.pump();

    final unlocked = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();
    expect(unlocked[1].enabled, isTrue);
    expect(unlocked[2].enabled, isTrue);
    expect(unlocked[3].enabled, isTrue);
    expect(find.text(l10n.actionEditConnection), findsNothing);
  });
}
